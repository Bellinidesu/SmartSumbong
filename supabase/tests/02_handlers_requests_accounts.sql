do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_adm uuid;
  h1 uuid;
begin
  -- four throwaway accounts, through the real sign-up trigger
  v_res  := gen_random_uuid(); v_res2 := gen_random_uuid(); v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_res, '+639999999901', 'Sweep, Resident', 'resident'),
                 (v_res2, '+639999999902', 'Sweep, Neighbour', 'resident'),
                 (v_tan, '+639999999903', 'Sweep, Tanod', 'tanod'),
                 (v_adm, '+639999999904', 'Sweep, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_res2, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(121.0155, 14.5269), 4326), last_location_at = now() where id = v_tan;
  update public.users set role = 'admin' where id = v_res2;
  v_log := 'setup ok';
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test h1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into h1 from public.reports where resident_id = v_res and subject = 'Sweep test h1';
    if h1 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files h1';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL resident files h1: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(h1, 'validate');
    execute 'reset role';
    if (select handler_id from public.reports where id = h1) is distinct from v_adm then raise exception 'handler is %', (select handler_id from public.reports where id = h1); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  accepting claims the case (admin 1 is the handler)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL accepting claims the case (admin 1 is the handler): ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from public.case_handler_log where report_id = h1 and action = 'take' and admin_id = v_adm) then raise exception 'no take row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the claim is logged as a take';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL the claim is logged as a take: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    begin perform public.set_resolution_target(h1, now() + interval '2 days', null); exception when others then if sqlerrm not like 'Admin Sweep is handling%' then raise exception '%', sqlerrm; end if; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  lock message names the handler First Last';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL lock message names the handler First Last: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(h1, now() + interval '2 days', null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD second admin cannot act on a case someone else handles (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  second admin cannot act on a case someone else handles (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.take_over_case(h1, '');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD take over without a reason refused (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  take over without a reason refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.take_over_case(h1, 'Covering while the first admin is out');
    execute 'reset role';
    if (select handler_id from public.reports where id = h1) is distinct from v_res2 then raise exception 'handler not moved'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  second admin takes over with a reason';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL second admin takes over with a reason: ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from public.notifications where user_id = v_adm and report_id = h1 and message ilike '%took over%') then raise exception 'no notification'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  first admin is told the case was taken over';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL first admin is told the case was taken over: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(h1, now() + interval '2 days', null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD first admin can no longer act on it (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  first admin can no longer act on it (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(h1, now() + interval '2 days', null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  new handler can act on it';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL new handler can act on it: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.take_over_case(h1, 'I want it');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot take a case (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident cannot take a case (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
        if (select version from public.reports where id = h1) < 2 then raise exception 'version %', (select version from public.reports where id = h1); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  version bumps on every change (stale-page guard)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL version bumps on every change (stale-page guard): ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_profile_change('full_name', 'Testing, Sweep', 'Typo in my name');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident asks for a name change';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL resident asks for a name change: ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from public.notifications where user_id = v_adm and subject_user_id = v_res and message ilike '%change their name%') then raise exception 'no linked notification'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admins notified, linked to the resident';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL admins notified, linked to the resident: ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from public.notifications where user_id = v_adm and subject_user_id = v_res and message ilike 'Resident Sweep%') then raise exception '%', (select message from public.notifications where user_id = v_adm and subject_user_id = v_res limit 1); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  name in the notification reads First Last';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL name in the notification reads First Last: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.decide_profile_request((select id from public.profile_requests where user_id = v_res and status = 'pending' limit 1), true, null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot approve their own request (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident cannot approve their own request (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.decide_profile_request((select id from public.profile_requests where user_id = v_res and status = 'pending' limit 1), true, null);
    execute 'reset role';
    if (select full_name from public.users where id = v_res) <> 'Testing, Sweep' then raise exception 'name is %', (select full_name from public.users where id = v_res); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin approves the name change';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL admin approves the name change: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_id_reupload('barangay_id', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg', null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident sends a new ID photo';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL resident sends a new ID photo: ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from public.profile_requests where user_id = v_res and kind = 'id_document' and status = 'pending') then raise exception 'no pending ID request'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  ID request waits for an admin';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL ID request waits for an admin: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.create_admin_account('sweep.no@example.com', 'No, Admin', '09999999906');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot create an admin (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident cannot create an admin (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.create_admin_account('sweep.newadmin@example.com', 'Admin, New', '09999999905');
    execute 'reset role';
    if not exists (select 1 from public.users where email = 'sweep.newadmin@example.com' and role = 'admin' and must_change_password) then raise exception 'new admin row missing or not flagged'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin creates a new admin';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL admin creates a new admin: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_account_deletion();
    execute 'reset role';
    if (select full_name from public.users where id = v_res) <> 'Deleted Resident' then raise exception 'not scrubbed'; end if;
    if not exists (select 1 from public.reports where id = h1) then raise exception 'report gone'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident with complaints deletes their account (scrubbed, reports kept)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL resident with complaints deletes their account (scrubbed, reports kept): ' || left(sqlerrm, 220);
  end;
  begin
        perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); if exists (select 1 from public.audit_integrity() where broken > 0) then raise exception 'broken: %', (select string_agg(scope || '=' || broken, ', ') from public.audit_integrity() where broken > 0); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  every case trail intact (audit_integrity)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL every case trail intact (audit_integrity): ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from cron.job where jobname = 'keep-portal-awake' and active) then raise exception 'no job'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  keep-awake job scheduled';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL keep-awake job scheduled: ' || left(sqlerrm, 220);
  end;
  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
