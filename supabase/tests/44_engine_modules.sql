-- 44_engine_modules.sql: each rung's SMART engine module (0165). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_khs uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r_po public.reports; r_hs public.reports; j jsonb; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999971', 'Module, Super'), (v_kpo, '+639999999972', 'Module, Kagawad'), (v_stf, '+639999999973', 'Module, Staff'),
                 (v_khs, '+639999999974', 'Module, Other Kagawad'), (v_res, '+639999999975', 'Module, Resident')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_stf, v_khs, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'health_sanitation' where id = v_khs;
  -- one case each committee sees, kept to its committee so the test does not depend on which kinds each committee sees
  perform set_config('request.jwt.claim.sub', v_res::text, true);
  r_po := public.file_report('peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'Malakas na videoke hanggang hatinggabi.', lat, lng);
  r_hs := public.file_report('animal_welfare', 'Stray / Nuisance Animals', 'Maraming asong gala sa kanto.', lat, lng);
  perform set_config('request.jwt.claim.sub', '', true);   -- the setup below is the system's, not a person's
  update public.reports set committee = 'peace_order' where id = r_po.id;
  update public.reports set committee = 'health_sanitation' where id = r_hs.id;

  -- 1. a resident has no module; each administrator gets their rung's
  begin
    begin perform public.smart_module(); raise exception 'a resident got a module'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.smart_module();
    if j->>'module' <> 'barangay' or j->'decisions' is null or j->'categories' <> 'null'::jsonb then raise exception 'the super admin''s module: %', left(j::text, 200); end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    j := public.smart_module();
    if j->>'module' <> 'committee' or j->>'committee' <> 'peace_order' or j->'decisions' is null then raise exception 'the Kagawad''s module: %', left(j::text, 200); end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    j := public.smart_module();
    if j->>'module' <> 'staff' or jsonb_typeof(j->'decisions') <> 'null' then raise exception 'the staff module has decisions: %', left(j::text, 200); end if;
    v_log := v_log || E'\n' || 'ok  a resident has no module; the super admin gets the barangay''s, a Kagawad the committee''s with decisions, staff theirs without';
  exception when others then v_log := v_log || E'\n' || 'FAIL modules: ' || sqlerrm; end;

  -- 2. a committee's module counts only the cases it may open; the super admin's counts both
  declare v_all integer; v_po integer; v_hs integer;
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    v_all := (public.smart_module()->'counts'->>'open')::int;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    v_po := (public.smart_module()->'counts'->>'open')::int;
    perform set_config('request.jwt.claim.sub', v_khs::text, true);
    v_hs := (public.smart_module()->'counts'->>'open')::int;
    if v_po < 1 or v_hs < 1 then raise exception 'a committee does not count its own case (% / %)', v_po, v_hs; end if;
    if v_po >= v_all or v_hs >= v_all then
      raise exception 'the committees'' counts are not smaller than the barangay''s: % % %', v_all, v_po, v_hs;
    end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    select count(*) into n from jsonb_array_elements(public.smart_module()->'deadline_risk') x where (x->>'report_id')::uuid = r_hs.id;
    if n > 0 then raise exception 'another committee''s case is in the deadline risk'; end if;
    select count(*) into n from jsonb_array_elements(public.smart_module()->'quiet') x where (x->>'report_id')::uuid = r_hs.id;
    if n > 0 then raise exception 'another committee''s case is in the quiet cases'; end if;
    v_log := v_log || E'\n' || 'ok  a committee''s module counts and lists only the cases it may open; the barangay''s counts every case';
  exception when others then v_log := v_log || E'\n' || 'FAIL scope: ' || sqlerrm; end;

  -- 3. a case taken by the staff member is theirs in their module
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    update public.reports set handler_id = v_stf where id = r_po.id;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if (public.smart_module()->'counts'->>'mine')::int < 1 then raise exception 'the staff member''s case is not theirs in the module'; end if;
    v_log := v_log || E'\n' || 'ok  the staff module counts the cases the staff member handles';
  exception when others then v_log := v_log || E'\n' || 'FAIL mine: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
