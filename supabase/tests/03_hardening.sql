do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_adm uuid;
  k1 uuid; k2 uuid;
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
  v_log := 'setup ok';
  begin
        perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    perform public.clear_login_attempts('+639999999903');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD signed out, nobody can clear a number (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  signed out, nobody can clear a number (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
        perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.7"}', true);
    perform public.register_login_failure('+639999999903');
    if (select failed_count from public.login_attempts where mobile_number = '+639999999903') <> 1 then raise exception 'not counted'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a failed sign-in is counted';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL a failed sign-in is counted: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.clear_login_attempts('+639999999903');
    execute 'reset role';
    if not exists (select 1 from public.login_attempts where mobile_number = '+639999999903') then raise exception 'cleared by someone else'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  another user cannot clear someone else''s count';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL another user cannot clear someone else''s count: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.clear_login_attempts('+639999999903');
    execute 'reset role';
    if exists (select 1 from public.login_attempts where mobile_number = '+639999999903') then raise exception 'still there'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the owner clears their own count once signed in';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL the owner clears their own count once signed in: ' || left(sqlerrm, 220);
  end;
  begin
        perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.8"}', true);
    perform public.register_login_failure('+6399999990' || lpad(g::text, 2, '0')) from generate_series(10, 34) g;
    if (select count(*) from public.login_attempts where mobile_number between '+639999999010' and '+639999999034') <> 20 then
      raise exception 'counted %', (select count(*) from public.login_attempts where mobile_number between '+639999999010' and '+639999999034'); end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  one address counts at most 20 failures per 15 minutes';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL one address counts at most 20 failures per 15 minutes: ' || left(sqlerrm, 220);
  end;
  begin
        perform set_config('request.headers', '{"cf-connecting-ip": "203.0.113.9"}', true);
    perform public.register_login_failure('+639999999950') from generate_series(1, 5);
    if not (select locked from public.check_login_lockout('+639999999950')) then raise exception 'not locked'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  five failures still lock a number';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL five failures still lock a number: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.otp_attempt(v_res, 'password', 'x');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD the app cannot call otp_attempt (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the app cannot call otp_attempt (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.revoke_user_sessions(v_res);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD the app cannot end sessions (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the app cannot end sessions (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
        insert into public.password_otps (user_id, code_hash, expires_at) values (v_res, 'RIGHT', now() + interval '10 minutes');
    if (select outcome || '/' || attempts_left from public.otp_attempt(v_res, 'password', 'nope')) <> 'wrong/4' then raise exception 'not wrong/4'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a wrong code counts one try';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL a wrong code counts one try: ' || left(sqlerrm, 220);
  end;
  begin
        if (select outcome from public.otp_attempt(v_res, 'password', 'RIGHT')) <> 'ok' then raise exception 'not ok'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the right code is accepted';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL the right code is accepted: ' || left(sqlerrm, 220);
  end;
  begin
        perform public.otp_attempt(v_res, 'password', 'nope') from generate_series(1, 4);
    if (select outcome from public.otp_attempt(v_res, 'password', 'RIGHT')) <> 'expired' then raise exception 'still open'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  after five wrong tries even the right code is refused';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL after five wrong tries even the right code is refused: ' || left(sqlerrm, 220);
  end;
  begin
        insert into auth.sessions (user_id) values (v_res), (v_res);
    perform public.revoke_user_sessions(v_res);
    if exists (select 1 from auth.sessions where user_id = v_res) then raise exception 'sessions left'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  revoke_user_sessions ends every session';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL revoke_user_sessions ends every session: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.sweep_overdue_reports();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD the app cannot run the overdue sweep (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the app cannot run the overdue sweep (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.sweep_overdue_verifications();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD the app cannot run the verification sweep (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the app cannot run the verification sweep (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
        update public.operational_settings set max_reports_per_day = 2 where id = 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    k1 := gen_random_uuid();
    perform public.file_report('street_obstruction', 'Sweep limit 1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, k1);
    perform public.file_report('street_obstruction', 'Sweep limit 2', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files up to the daily limit';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL resident files up to the daily limit: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep limit 3', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD one more than the limit is refused (should have been refused)';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  one more than the limit is refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    if (select subject from public.file_report('street_obstruction', 'Sweep limit 1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, k1)) <> 'Sweep limit 1' then raise exception 'wrong report'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a resend of a filed outbox report still answers';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL a resend of a filed outbox report still answers: ' || left(sqlerrm, 220);
  end;
  begin
        insert into public.notifications (user_id, kind, message, is_read, created_at) values
      (v_res, 'status_change', 'Sweep old read', true, now() - interval '91 days'),
      (v_res, 'status_change', 'Sweep old unread', false, now() - interval '91 days'),
      (v_res, 'status_change', 'Sweep ancient', false, now() - interval '400 days');
    perform public.purge_old_notifications();
    if exists (select 1 from public.notifications where message in ('Sweep old read', 'Sweep ancient')) then raise exception 'not purged'; end if;
    if not exists (select 1 from public.notifications where message = 'Sweep old unread') then raise exception 'unread purged too soon'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  old read notifications are purged, recent ones kept';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL old read notifications are purged, recent ones kept: ' || left(sqlerrm, 220);
  end;
  begin
        if not exists (select 1 from cron.job where jobname = 'purge-old-notifications' and active) then raise exception 'no job'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  purge job scheduled';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL purge job scheduled: ' || left(sqlerrm, 220);
  end;
  begin
        insert into auth.sessions (user_id) values (v_tan);
    update public.users set avatar_url = null where id = v_tan;
    if not exists (select 1 from auth.sessions where user_id = v_tan) then raise exception 'signed out'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  an ordinary profile change keeps sessions';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL an ordinary profile change keeps sessions: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_account_suspension(v_tan, true, 'Sweep test');
    execute 'reset role';
    if exists (select 1 from auth.sessions where user_id = v_tan) then raise exception 'still signed in'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  suspension signs the person out';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL suspension signs the person out: ' || left(sqlerrm, 220);
  end;
  begin
        insert into auth.sessions (user_id) values (v_res2);
    update public.users set must_change_password = true where id = v_res2;
    if exists (select 1 from auth.sessions where user_id = v_res2) then raise exception 'still signed in'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a barangay password reset signs the person out';
  exception when others then
    execute 'reset role';
    v_log := v_log || E'\n' || 'FAIL a barangay password reset signs the person out: ' || left(sqlerrm, 220);
  end;
  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
