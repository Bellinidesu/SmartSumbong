-- 42_concern_options.sql: several categories and sub-categories on one report, kept as filed (0163). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_res uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid();
  o_a bigint; o_b bigint; o_c bigint; o_off bigint;
  r public.reports; r2 public.reports; n integer; t text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999941', 'Concern, Ana'), (v_sup, '+639999999942', 'Concern, Super')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_sup);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  insert into public.complaint_options (category, label_en, label_fil) values ('barangay_service', 'Delayed response', 'Naantalang tugon') returning id into o_a;
  insert into public.complaint_options (category, label_en, label_fil) values ('barangay_service', 'Duty negligence', 'Pagpapabaya sa tungkulin') returning id into o_b;
  insert into public.complaint_options (category, label_en, label_fil) values ('animal_welfare', 'Stray dog', 'Asong gala') returning id into o_c;
  insert into public.complaint_options (category, label_en, label_fil, active) values ('animal_welfare', 'Old option', 'Lumang opsyon', false) returning id into o_off;

  -- 1. one report, its main option by id, two options of one category and another category; a switched-off one left out
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    r := public.file_report('barangay_service', 'Delayed response', 'Walang sumagot sa hotline ng barangay.', lat, lng, false, '[]'::jsonb, null,
                            o_a, jsonb_build_array(jsonb_build_object('category', 'barangay_service', 'option', o_b),
                                                   jsonb_build_object('category', 'animal_welfare', 'option', o_c),
                                                   jsonb_build_object('category', 'animal_welfare', 'option', o_off)));
    select count(*) into n from public.report_concerns where report_id = r.id;
    if n <> 3 then raise exception '% concerns, not 3 (main, a second option of it, another category; the switched-off one left out)', n; end if;
    if not exists (select 1 from public.report_concerns where report_id = r.id and category = 'barangay_service' and option_id = o_a
                    and filed_option_en = 'Delayed response' and filed_category_en is not null) then
      raise exception 'the main concern does not carry its option and its names';
    end if;
    if not exists (select 1 from public.report_concerns where report_id = r.id and option_id = o_b and filed_option_fil = 'Pagpapabaya sa tungkulin') then
      raise exception 'the second option of the same category is missing';
    end if;
    -- an old app (no option, no concerns) still files, and the subject finds its option
    r2 := public.file_report('barangay_service', 'Duty negligence', 'Hindi dumating ang tanod sa oras.', lat, lng);
    if (select option_id from public.report_concerns where report_id = r2.id) is distinct from o_b then raise exception 'the subject did not find its option'; end if;
    v_log := v_log || E'\n' || 'ok  one report files several categories and sub-categories; a switched-off one is left out; an old app still files';
  exception when others then v_log := v_log || E'\n' || 'FAIL filing: ' || sqlerrm; end;

  -- 2. the same concern twice is refused; a resident cannot add one that is not offered, nor a fifth
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.add_report_concern(r.id, 'barangay_service', null, o_b); raise exception 'the same concern was added twice';
    exception when raise_exception then if sqlerrm not like '%already has that concern%' then raise; end if; end;
    begin perform public.add_report_concern(r.id, 'animal_welfare', null, o_off); raise exception 'a switched-off option was added';
    exception when check_violation then null; end;
    perform public.add_report_concern(r.id, 'animal_welfare', 'Sa kanto', null);   -- the category itself, the fourth
    begin perform public.add_report_concern(r.id, 'traffic_violation', null, null); raise exception 'a fifth concern was added';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  the same concern twice is refused; a resident adds only what is offered, four at most';
  exception when others then v_log := v_log || E'\n' || 'FAIL adding: ' || sqlerrm; end;

  -- 3. the Control Room renames a category and switches off an option: the case keeps what it was filed as, and its timeline says so
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select filed_category_en into t from public.report_concerns where report_id = r.id and option_id = o_a;
    update public.complaint_categories set label_en = 'Barangay Help Desk' where key = 'barangay_service';
    update public.complaint_options set active = false where id = o_c;
    if (select filed_category_en from public.report_concerns where report_id = r.id and option_id = o_a) is distinct from t then
      raise exception 'renaming the category changed what the case was filed under';
    end if;
    if not exists (select 1 from public.status_logs where report_id = r.id and is_system and remark like '%now called "Barangay Help Desk"%' and remark like '%filed under "' || t || '"%') then
      raise exception 'no note on the timeline for the renamed category';
    end if;
    if not exists (select 1 from public.status_logs where report_id = r.id and is_system and remark like '%"Stray dog" was switched off%filed as "Stray dog"%') then
      raise exception 'no note on the timeline for the switched-off option';
    end if;
    if (select handler_id from public.reports where id = r.id) is not null then raise exception 'the note made the super admin take the case'; end if;
    begin update public.report_concerns set filed_option_en = 'Edited' where report_id = r.id and option_id = o_a;
          if (select filed_option_en from public.report_concerns where report_id = r.id and option_id = o_a) <> 'Delayed response' then raise exception 'the filed name was changed'; end if; end;
    v_log := v_log || E'\n' || 'ok  a renamed category or a switched-off option leaves each case as filed, notes it on the timeline, and takes nobody''s case';
  exception when others then v_log := v_log || E'\n' || 'FAIL changes: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
