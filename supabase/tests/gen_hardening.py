"""03_hardening.sql: checks for 0114-0120 (login lockout, SMS codes, cron-only
sweeps, daily filing limit, notification retention, sign-out on access
changes), same rolled-back pattern as 01_lifecycle.sql."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROLES = {'res': 'v_res', 'res2': 'v_res2', 'tan': 'v_tan', 'adm': 'v_adm'}
steps = []


def as_role(who):
    if who == 'pg':
        return ''
    v = ROLES[who]
    return (f"perform set_config('request.jwt.claims', json_build_object('sub', {v}::text, 'role', 'authenticated')::text, true);\n"
            f"    perform set_config('request.jwt.claim.sub', {v}::text, true);\n"
            f"    execute 'set local role authenticated';\n")


def step(label, who, sql, fail=False):
    steps.append((label, who, sql.strip(), fail))



# setup: the same four throwaway accounts as 01_lifecycle.sql
src = open(os.path.join(HERE, '01_lifecycle.sql'), encoding='utf-8').read()
setup = src[src.index('  -- four throwaway accounts'):src.index("  v_log := 'setup ok: 4 accounts';")]


def anon(sql):
    return ("perform set_config('request.jwt.claims', '', true);\n"
            "    perform set_config('request.jwt.claim.sub', '', true);\n"
            "    execute 'set local role anon';\n    " + sql)


# ---- 0114: login lockout
step('signed out, nobody can clear a number', 'pg', anon("perform public.clear_login_attempts('+639999999903');"), fail=True)
step('a failed sign-in is counted', 'pg',
     "perform set_config('request.headers', '{\"cf-connecting-ip\": \"203.0.113.7\"}', true);\n"
     "    perform public.register_login_failure('+639999999903');\n"
     "    if (select failed_count from public.login_attempts where mobile_number = '+639999999903') <> 1 then raise exception 'not counted'; end if;")
step("another user cannot clear someone else's count", 'res',
     "perform public.clear_login_attempts('+639999999903');\n    execute 'reset role';\n"
     "    if not exists (select 1 from public.login_attempts where mobile_number = '+639999999903') then raise exception 'cleared by someone else'; end if;")
step('the owner clears their own count once signed in', 'tan',
     "perform public.clear_login_attempts('+639999999903');\n    execute 'reset role';\n"
     "    if exists (select 1 from public.login_attempts where mobile_number = '+639999999903') then raise exception 'still there'; end if;")
step('one address counts at most 20 failures per 15 minutes', 'pg',
     "perform set_config('request.headers', '{\"cf-connecting-ip\": \"203.0.113.8\"}', true);\n"
     "    perform public.register_login_failure('+6399999990' || lpad(g::text, 2, '0')) from generate_series(10, 34) g;\n"
     "    if (select count(*) from public.login_attempts where mobile_number between '+639999999010' and '+639999999034') <> 20 then\n"
     "      raise exception 'counted %', (select count(*) from public.login_attempts where mobile_number between '+639999999010' and '+639999999034'); end if;")
step('five failures still lock a number', 'pg',
     "perform set_config('request.headers', '{\"cf-connecting-ip\": \"203.0.113.9\"}', true);\n"
     "    perform public.register_login_failure('+639999999950') from generate_series(1, 5);\n"
     "    if not (select locked from public.check_login_lockout('+639999999950')) then raise exception 'not locked'; end if;")

# ---- 0114: SMS codes and sessions
step('the app cannot call otp_attempt', 'res', "perform public.otp_attempt(v_res, 'password', 'x');", fail=True)
step('the app cannot end sessions', 'res', "perform public.revoke_user_sessions(v_res);", fail=True)
step('a wrong code counts one try', 'pg',
     "insert into public.password_otps (user_id, code_hash, expires_at) values (v_res, 'RIGHT', now() + interval '10 minutes');\n"
     "    if (select outcome || '/' || attempts_left from public.otp_attempt(v_res, 'password', 'nope')) <> 'wrong/4' then raise exception 'not wrong/4'; end if;")
step('the right code is accepted', 'pg',
     "if (select outcome from public.otp_attempt(v_res, 'password', 'RIGHT')) <> 'ok' then raise exception 'not ok'; end if;")
step('after five wrong tries even the right code is refused', 'pg',
     "perform public.otp_attempt(v_res, 'password', 'nope') from generate_series(1, 4);\n"
     "    if (select outcome from public.otp_attempt(v_res, 'password', 'RIGHT')) <> 'expired' then raise exception 'still open'; end if;")
step('revoke_user_sessions ends every session', 'pg',
     "insert into auth.sessions (user_id) values (v_res), (v_res);\n    perform public.revoke_user_sessions(v_res);\n"
     "    if exists (select 1 from auth.sessions where user_id = v_res) then raise exception 'sessions left'; end if;")

# ---- 0114: cron-only sweeps, daily filing limit
step('the app cannot run the overdue sweep', 'res', "perform public.sweep_overdue_reports();", fail=True)
step('the app cannot run the verification sweep', 'adm', "perform public.sweep_overdue_verifications();", fail=True)
step('resident files up to the daily limit', 'pg',
     "update public.operational_settings set max_reports_per_day = 2 where id = 1;\n"
     "    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);\n"
     "    perform set_config('request.jwt.claim.sub', v_res2::text, true);\n"
     "    execute 'set local role authenticated';\n"
     "    k1 := gen_random_uuid();\n"
     "    perform public.file_report('street_obstruction', 'Sweep limit 1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, k1);\n"
     "    perform public.file_report('street_obstruction', 'Sweep limit 2', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());")
step('one more than the limit is refused', 'res2',
     "perform public.file_report('street_obstruction', 'Sweep limit 3', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());", fail=True)
step('a resend of a filed outbox report still answers', 'res2',
     "if (select subject from public.file_report('street_obstruction', 'Sweep limit 1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, k1)) <> 'Sweep limit 1' then raise exception 'wrong report'; end if;")

# ---- 0116: upload signing rate limit
step('the app cannot take rate slots itself', 'res', "perform public.take_rate_slot('upload-ids:x', 10, interval '1 hour');", fail=True)
step('ten registration uploads an hour per address, then refused', 'pg',
     "if (select count(*) filter (where ok) from (select public.take_rate_slot('upload-ids:sweep', 10, interval '1 hour') as ok from generate_series(1, 12)) t) <> 10 then raise exception 'not 10'; end if;")

# ---- 0117: private identity photos
U = "0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11"
step('a private ID or selfie address is accepted', 'pg',
     f"if not (public.is_media_url('https://res.cloudinary.com/nwb2kryl/image/authenticated/v17/ids/{U}.jpg') and public.is_media_url('https://res.cloudinary.com/nwb2kryl/image/authenticated/v17/selfies/{U}.jpg')) then raise exception 'refused'; end if;")
step('a signed (shareable) address is never stored', 'pg',
     f"if public.is_media_url('https://res.cloudinary.com/nwb2kryl/image/authenticated/s--Ab3_-xYz--/v17/ids/{U}.jpg') then raise exception 'accepted'; end if;")
step('only identity photos may be private', 'pg',
     f"if public.is_media_url('https://res.cloudinary.com/nwb2kryl/image/authenticated/v17/reports/{U}.jpg') then raise exception 'accepted'; end if;")
step('a profile picture in avatars/ is accepted', 'res',
     f"update public.users set avatar_url = 'https://res.cloudinary.com/nwb2kryl/image/upload/v17/avatars/{U}.jpg' where id = v_res;\n    execute 'reset role';\n"
     "    if (select avatar_url from public.users where id = v_res) is null then raise exception 'not saved'; end if;")

# ---- 0118: identity photo cleanup
A1 = "https://res.cloudinary.com/nwb2kryl/image/upload/v17/avatars/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e12.jpg"
A2 = "https://res.cloudinary.com/nwb2kryl/image/upload/v17/avatars/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e13.jpg"
step('a replaced profile picture is queued for deletion', 'pg',
     f"update public.users set avatar_url = '{A1}' where id = v_res2;\n"
     f"    update public.users set avatar_url = '{A2}' where id = v_res2;\n"
     f"    if not exists (select 1 from public.media_trash where url = '{A1}') then raise exception 'not queued'; end if;\n"
     f"    if exists (select 1 from public.media_trash where url = '{A2}') then raise exception 'current one queued'; end if;")
step('nothing is deleted within the first week', 'pg',
     f"if '{A1}' = any (array(select public.media_trash_due())) then raise exception 'due too soon'; end if;")
step('after a week an unused photo is due', 'pg',
     f"update public.media_trash set queued_at = now() - interval '8 days' where url = '{A1}';\n"
     f"    if not ('{A1}' = any (array(select public.media_trash_due()))) then raise exception 'not due'; end if;")
step('a photo back in use is never due', 'pg',
     f"update public.users set avatar_url = '{A1}' where id = v_tan;\n"
     f"    if '{A1}' = any (array(select public.media_trash_due())) then raise exception 'in-use photo due'; end if;\n"
     f"    perform public.media_trash_done(array[]::text[]);\n"
     f"    if exists (select 1 from public.media_trash where url = '{A1}') then raise exception 'not dropped from queue'; end if;")
step('complaint evidence is never queued', 'pg',
     "perform public.queue_media_trash('https://res.cloudinary.com/nwb2kryl/image/upload/v17/reports/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e14.jpg');\n"
     "    if exists (select 1 from public.media_trash where url like '%/reports/%') then raise exception 'evidence queued'; end if;")
step('a deleted account queues its ID and selfie', 'pg',
     "perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);\n"
     "    delete from public.media_trash;\n"
     "    update public.users set id_image_url = 'https://res.cloudinary.com/nwb2kryl/image/upload/v17/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e15.jpg' where id = v_res2;\n"
     "    update public.users set id_image_url = null, selfie_url = null where id = v_res2;\n"
     "    if not exists (select 1 from public.media_trash where url like '%/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e15.jpg') then raise exception 'ID not queued'; end if;\n"
    "    if not exists (select 1 from public.media_trash where url like '%/selfies/%') then raise exception 'selfie not queued'; end if;")
step('the app cannot read or clear the queue', 'res', "perform public.media_trash_due();", fail=True)
step('cleanup job scheduled, and idle without its Vault secrets', 'pg',
     "if not exists (select 1 from cron.job where jobname = 'media-cleanup' and active) then raise exception 'no job'; end if;\n"
     "    perform public.run_media_cleanup();")

# ---- 0119: system health
step('a browser cannot log errors as an Edge Function', 'pg',
     "perform set_config('request.jwt.claims', '{\"role\": \"anon\"}', true);\n"
     "    perform public.log_portal_error('function', 'sign-upload', 'Sweep forged');\n"
     "    perform set_config('request.jwt.claims', '', true);\n"
     "    if exists (select 1 from public.portal_errors where message = 'Sweep forged') then raise exception 'logged'; end if;")
step('an Edge Function failure is logged and raises one alert', 'pg',
     "perform set_config('request.jwt.claims', '{\"role\": \"service_role\"}', true);\n"
     "    perform public.log_portal_error('function', 'send-dispatch-push', 'Sweep FCM refused');\n"
     "    perform set_config('request.jwt.claims', '', true);\n"
     "    perform public.check_system_health();\n"
     "    if not exists (select 1 from public.system_alerts where key = 'functions' and cleared_at is null) then raise exception 'no alert'; end if;\n"
     "    if not exists (select 1 from public.notifications where user_id = v_adm and message like 'System check: Edge Functions failed%') then raise exception 'admin not told'; end if;")
step('a second check does not tell the admins again', 'pg',
     "perform public.check_system_health();\n"
     "    if (select count(*) from public.notifications where user_id = v_adm and message like 'System check: Edge Functions%') <> 1 then raise exception 'told twice'; end if;")
step('a failed scheduled job raises its own alert, and clears', 'pg',
     "insert into cron.job_run_details (jobid, runid, job_pid, database, username, command, status, return_message, start_time, end_time)\n"
     "      select jobid, 999999, 0, 'postgres', 'postgres', command, 'failed', 'Sweep: relation missing', now(), now() from cron.job where jobname = 'purge-old-notifications';\n"
     "    perform public.check_system_health();\n"
     "    if not exists (select 1 from public.system_alerts where key = 'job:purge-old-notifications' and cleared_at is null) then raise exception 'no alert'; end if;\n"
     "    delete from cron.job_run_details where runid = 999999;\n"
     "    perform public.check_system_health();\n"
     "    if exists (select 1 from public.system_alerts where key = 'job:purge-old-notifications' and cleared_at is null) then raise exception 'not cleared'; end if;")
step('health check scheduled hourly', 'pg',
     "if not exists (select 1 from cron.job where jobname = 'system-health' and active) then raise exception 'no job'; end if;")
step('filing can be paused, with the reason shown to residents', 'pg',
     "update public.operational_settings set filing_paused = true, filing_paused_message = 'Sweep paused for repairs' where id = 1;\n"
     "    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);\n"
     "    perform set_config('request.jwt.claim.sub', v_res::text, true);\n"
     "    execute 'set local role authenticated';\n"
     "    begin\n"
     "      perform public.file_report('street_obstruction', 'Sweep paused', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());\n"
     "      raise exception 'filed while paused';\n"
     "    exception when check_violation then\n"
     "      if sqlerrm <> 'Sweep paused for repairs' then raise exception 'message was %', sqlerrm; end if;\n"
     "    end;\n"
     "    execute 'reset role';\n"
     "    update public.operational_settings set filing_paused = false where id = 1;")
step('only admins see the alerts', 'res',
     "if exists (select 1 from public.system_alerts) then raise exception 'resident sees alerts'; end if;")

# ---- 0120: tracking IDs past 9,999
step('the 10,000th complaint gets its own tracking ID', 'pg',
     "perform setval('public.report_seq', 9999);\n"
     "    insert into public.reports (resident_id, category, subject, description, latitude, longitude)\n"
     "      values (v_res2, 'street_obstruction', 'Sweep 10000', 'Automated sweep, rolled back.', 14.5269, 121.0155);\n"
     "    if (select tracking_id from public.reports where subject = 'Sweep 10000') <> 'BRG-' || to_char(now(), 'YYYY') || '-10000' then\n"
     "      raise exception 'got %', (select tracking_id from public.reports where subject = 'Sweep 10000'); end if;")

# ---- 0115: notification retention, sign-out on access changes
step('old read notifications are purged, recent ones kept', 'pg',
     "insert into public.notifications (user_id, kind, message, is_read, created_at) values\n"
     "      (v_res, 'status_change', 'Sweep old read', true, now() - interval '91 days'),\n"
     "      (v_res, 'status_change', 'Sweep old unread', false, now() - interval '91 days'),\n"
     "      (v_res, 'status_change', 'Sweep ancient', false, now() - interval '400 days');\n"
     "    perform public.purge_old_notifications();\n"
     "    if exists (select 1 from public.notifications where message in ('Sweep old read', 'Sweep ancient')) then raise exception 'not purged'; end if;\n"
     "    if not exists (select 1 from public.notifications where message = 'Sweep old unread') then raise exception 'unread purged too soon'; end if;")
step('purge job scheduled', 'pg',
     "if not exists (select 1 from cron.job where jobname = 'purge-old-notifications' and active) then raise exception 'no job'; end if;")
step('an ordinary profile change keeps sessions', 'pg',
     "insert into auth.sessions (user_id) values (v_tan);\n    update public.users set avatar_url = null where id = v_tan;\n"
     "    if not exists (select 1 from auth.sessions where user_id = v_tan) then raise exception 'signed out'; end if;")
step('suspension signs the person out', 'adm',
     "perform public.set_account_suspension(v_tan, true, 'Sweep test');\n    execute 'reset role';\n"
     "    if exists (select 1 from auth.sessions where user_id = v_tan) then raise exception 'still signed in'; end if;")
step('a barangay password reset signs the person out', 'pg',
     "insert into auth.sessions (user_id) values (v_res2);\n    update public.users set must_change_password = true where id = v_res2;\n"
     "    if exists (select 1 from auth.sessions where user_id = v_res2) then raise exception 'still signed in'; end if;")

def body():
    out = []
    for label, who, sql, fail in steps:
        lab = label.replace("'", "''")
        ok = (f"v_log := v_log || E'\\n' || 'BAD {lab} (should have been refused)';" if fail
              else f"v_log := v_log || E'\\n' || 'ok  {lab}';")
        err = (f"v_log := v_log || E'\\n' || 'ok  {lab} (refused: ' || left(sqlerrm, 120) || ')';" if fail
               else f"v_log := v_log || E'\\n' || 'FAIL {lab}: ' || left(sqlerrm, 220);")
        out.append(f"""  begin
    {as_role(who)}    {sql}
    execute 'reset role';
    {ok}
  exception when others then
    execute 'reset role';
    {err}
  end;""")
    return '\n'.join(out)


sql = f"""do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_adm uuid;
  k1 uuid; k2 uuid;
begin
{setup}  v_log := 'setup ok';
{body()}
  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
"""
open(os.path.join(HERE, '03_hardening.sql'), 'w', encoding='utf-8').write(sql)
print(len(steps), 'steps')
