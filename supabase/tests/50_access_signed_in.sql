-- 50_access_signed_in.sql: the access rules apply to signed-in users, except the eight signed-out callers read (0171). Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  n integer;
  v_res uuid := gen_random_uuid();
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  -- 1. only the eight named policies still apply to every role
  begin
    select count(*) into n from pg_policies where schemaname = 'public' and roles @> '{public}';
    if n <> 8 then raise exception '% policies apply to every role, expected 8: %', n,
      (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where schemaname = 'public' and roles @> '{public}'); end if;
    select count(*) into n from pg_policies where schemaname = 'public' and roles @> '{public}'
       and (tablename, policyname) not in (('complaint_categories', 'complaint_categories_read'), ('complaint_options', 'complaint_options_read'),
             ('hotline_groups', 'hotline_groups_read'), ('hotline_numbers', 'hotline_numbers_read'), ('barangay_profile', 'barangay_profile_read'),
             ('wording', 'wording_read'), ('barangay_boundary', 'boundary_read'), ('hazard_zones', 'hazard_zones_read'));
    if n <> 0 then raise exception 'an unexpected policy applies to every role'; end if;
    v_log := v_log || E'\n' || 'ok  only the eight rules signed-out callers need apply to every role';
  exception when others then v_log := v_log || E'\n' || 'FAIL roles: ' || sqlerrm; end;

  -- 2. a signed-out caller still reads what the app shows before sign-in, and nothing private
  begin
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select '00000000-0000-0000-0000-000000000000', v_res, 'authenticated', 'authenticated', public.auth_email_for('+639999999991'),
           jsonb_build_object('full_name', 'Access, Ana', 'mobile_number', '+639999999991', 'role', 'resident', 'id_type', 'barangay_id',
                              'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                              'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now();
    update public.users set verification_status = 'verified', verified_at = now() where id = v_res;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.file_report('peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'Malakas na videoke hanggang hatinggabi.', lat, lng);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    if (select count(*) from public.complaint_categories where active) = 0 then raise exception 'signed out: no active complaint categories'; end if;
    if (select count(*) from public.complaint_options where active) = 0 then raise exception 'signed out: no active complaint options'; end if;
    if (select count(*) from public.barangay_profile) = 0 then raise exception 'signed out: no barangay profile'; end if;
    if (select count(*) from public.reports) <> 0 then raise exception 'signed out: reports are readable'; end if;
    if (select count(*) from public.users) <> 0 then raise exception 'signed out: users are readable'; end if;
    if (select count(*) from public.status_logs) <> 0 then raise exception 'signed out: case history is readable'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  signed out: complaint types and the barangay profile still read; reports, users and history do not';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL signed out: ' || sqlerrm;
  end;

  -- 3. a signed-in resident still reads their own report through the now signed-in-only rule
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.reports where resident_id = v_res;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if n < 1 then raise exception 'the resident does not see their own report'; end if;
    v_log := v_log || E'\n' || 'ok  signed in: a resident still reads their own report';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL signed in: ' || sqlerrm;
  end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
