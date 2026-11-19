-- 54_one_category.sql: one category per case (0176). Every new concern is under its report's category; a report filed with
-- concerns from a second category is refused with one clear message; cases that already mix are left as they are. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_res uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid();
  o_a bigint; o_b bigint; o_c bigint; o_x bigint;
  r public.reports; r_old uuid; n integer; c_old uuid; v_ref uuid := gen_random_uuid();
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999981', 'Kategorya, Ana'), (v_sup, '+639999999982', 'Kategorya, Super')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_sup);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  insert into public.complaint_options (category, label_en, label_fil) values ('peace_order_nuisance', 'Videoke past midnight', 'Videoke lampas hatinggabi') returning id into o_a;
  insert into public.complaint_options (category, label_en, label_fil) values ('peace_order_nuisance', 'Drinking in the street', 'Inuman sa kalye') returning id into o_b;
  insert into public.complaint_options (category, label_en, label_fil) values ('peace_order_nuisance', 'Street brawl', 'Away sa kalye') returning id into o_c;
  insert into public.complaint_options (category, label_en, label_fil) values ('environmental_waste_hazard', 'Garbage pile', 'Tambak na basura') returning id into o_x;

  -- 1. filing with a concern from a second category is refused, with the message in English and Tagalog, and nothing is filed
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin
      perform public.file_report('peace_order_nuisance', 'Videoke past midnight', 'Gabi-gabi ang videoke at may basura pa sa kanto.', lat, lng, false, '[]'::jsonb, v_ref,
                                 o_a, jsonb_build_array(jsonb_build_object('category', 'peace_order_nuisance', 'option', o_b),
                                                        jsonb_build_object('category', 'environmental_waste_hazard', 'option', o_x)));
      raise exception 'a report with two categories was filed';
    exception when check_violation then
      if sqlerrm not like 'A report can have concerns from one category only: %. Report the other concern on its own. / Isang kategorya lamang%Isumbong nang hiwalay%' then raise; end if;
      if sqlerrm not like '%' || (select label_en from public.complaint_categories where key = 'peace_order_nuisance') || '%' then raise exception 'the message does not name the category: %', sqlerrm; end if;
    end;
    if exists (select 1 from public.reports where client_ref = v_ref) then raise exception 'the refused report was filed anyway'; end if;
    v_log := v_log || E'\n' || 'ok  a report with concerns from two categories is refused with one bilingual message naming its category, and nothing is filed';
  exception when others then v_log := v_log || E'\n' || 'FAIL filing two categories: ' || sqlerrm; end;

  -- 2. several concerns of one category file as before
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    r := public.file_report('peace_order_nuisance', 'Videoke past midnight', 'Gabi-gabi ang videoke at may nag-iinuman pa sa kanto.', lat, lng, false, '[]'::jsonb, null,
                            o_a, jsonb_build_array(jsonb_build_object('category', 'peace_order_nuisance', 'option', o_b)));
    select count(*) into n from public.report_concerns where report_id = r.id and category = 'peace_order_nuisance';
    if n <> 2 then raise exception '% concerns, not 2', n; end if;
    v_log := v_log || E'\n' || 'ok  several concerns of one category still file in one report';
  exception when others then v_log := v_log || E'\n' || 'FAIL one category: ' || sqlerrm; end;

  -- 3. adding a concern later: the resident and the handling admin add only the case's own category; a direct insert is refused too
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.add_report_concern(r.id, 'environmental_waste_hazard', null, o_x); raise exception 'the resident added a second category';
    exception when check_violation then if sqlerrm not like 'A report can have concerns from one category only%' then raise; end if; end;
    perform public.add_report_concern(r.id, 'peace_order_nuisance', null, o_c);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.take_case(r.id);
    begin perform public.add_report_concern(r.id, 'traffic_violation', 'Mabilis ang tricycle', null); raise exception 'the admin added a second category';
    exception when check_violation then if sqlerrm not like 'A report can have concerns from one category only%' then raise; end if; end;
    perform set_config('request.jwt.claim.sub', '', true);
    begin insert into public.report_concerns (report_id, category) values (r.id, 'animal_welfare'); raise exception 'a direct insert of a second category went in';
    exception when check_violation then null; end;
    select count(*) into n from public.report_concerns where report_id = r.id;
    if n <> 3 then raise exception '% concerns, not 3', n; end if;
    if exists (select 1 from public.report_concerns where report_id = r.id and category <> 'peace_order_nuisance') then raise exception 'a second category got in'; end if;
    v_log := v_log || E'\n' || 'ok  the resident, the handling admin and a direct insert all add only the case''s own category';
  exception when others then v_log := v_log || E'\n' || 'FAIL adding: ' || sqlerrm; end;

  -- 4. a case from before 0176 that already mixes categories is left as it is and can still be worked; nothing new of another category joins it
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_res, 'environmental_waste_hazard', 'Basura sa kanal', 'Tambak na basura at mga daga sa kanal.', lat, lng) returning id into r_old;
    alter table public.report_concerns disable trigger one_category_per_case;   -- as such a case was written before 0176
    insert into public.report_concerns (report_id, category, note, created_by) values (r_old, 'animal_welfare', 'Daga', v_res) returning id into c_old;
    alter table public.report_concerns enable trigger one_category_per_case;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.take_case(r_old);
    perform public.set_concern_status(c_old, true, 'Nag-spray na ang health center.');
    if (select status from public.report_concerns where id = c_old) <> 'resolved' then raise exception 'the old concern could not be resolved'; end if;
    perform public.set_concern_status(c_old, false, null);
    perform public.add_report_concern(r_old, 'environmental_waste_hazard', 'Kanal', o_x);
    begin perform public.add_report_concern(r_old, 'animal_welfare', 'Pusa', (select o.id from public.complaint_options o where o.category = 'animal_welfare' order by o.id limit 1));
          raise exception 'a mixed case took another concern of its second category';
    exception when check_violation then if sqlerrm not like 'A report can have concerns from one category only%' then raise; end if; end;
    select count(*) into n from public.report_concerns where report_id = r_old;
    if n <> 3 then raise exception '% concerns on the old case, not 3', n; end if;
    v_log := v_log || E'\n' || 'ok  a case that already mixes categories keeps them and can be worked; only its own category can be added';
  exception when others then
    begin alter table public.report_concerns enable trigger one_category_per_case; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL a mixed case: ' || sqlerrm;
  end;

  -- 5. the refusal is a function residents can reach only through filing; the trigger function is nobody's to call
  begin
    if has_function_privilege('anon', 'public._one_category_refuse(public.complaint_category)', 'execute') then raise exception 'anon can call the refusal'; end if;
    if has_function_privilege('authenticated', 'public._one_category_per_case()', 'execute') then raise exception 'the trigger function can be called'; end if;
    v_log := v_log || E'\n' || 'ok  the helpers are kept from the API';
  exception when others then v_log := v_log || E'\n' || 'FAIL grants: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
