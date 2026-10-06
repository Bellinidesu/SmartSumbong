"""sweep2.sql: checks for 0084-0091 (case handlers, profile requests, new
admins, account deletion, keep-awake), same rolled-back pattern as sweep.sql."""
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


IMG = "https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg"

# setup: the same four throwaway accounts as sweep.sql; v_res2 becomes the second admin
src = open(os.path.join(HERE, '01_lifecycle.sql'), encoding='utf-8').read()
setup = src[src.index('  -- four throwaway accounts'):src.index("  v_log := 'setup ok: 4 accounts';")]

step('resident files h1', 'res',
     "perform public.file_report('street_obstruction', 'Sweep test h1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());\n"
     "    execute 'reset role';\n"
     "    select id into h1 from public.reports where resident_id = v_res and subject = 'Sweep test h1';\n"
     "    if h1 is null then raise exception 'no report row'; end if;")
step('accepting claims the case (admin 1 is the handler)', 'adm',
     "perform public.review_report(h1, 'validate');\n    execute 'reset role';\n"
     "    if (select handler_id from public.reports where id = h1) is distinct from v_adm then raise exception 'handler is %', (select handler_id from public.reports where id = h1); end if;")
step('the claim is logged as a take', 'pg',
     "if not exists (select 1 from public.case_handler_log where report_id = h1 and action = 'take' and admin_id = v_adm) then raise exception 'no take row'; end if;")
step('lock message names the handler First Last', 'res2',
     "begin perform public.set_resolution_target(h1, now() + interval '2 days', null); exception when others then if sqlerrm not like 'Admin Sweep is handling%' then raise exception '%', sqlerrm; end if; end;")
step('second admin cannot act on a case someone else handles', 'res2',
     "perform public.set_resolution_target(h1, now() + interval '2 days', null);", fail=True)
step('take over without a reason refused', 'res2', "perform public.take_over_case(h1, '');", fail=True)
step('second admin takes over with a reason', 'res2',
     "perform public.take_over_case(h1, 'Covering while the first admin is out');\n    execute 'reset role';\n"
     "    if (select handler_id from public.reports where id = h1) is distinct from v_res2 then raise exception 'handler not moved'; end if;")
step('first admin is told the case was taken over', 'pg',
     "if not exists (select 1 from public.notifications where user_id = v_adm and report_id = h1 and message ilike '%took over%') then raise exception 'no notification'; end if;")
step('first admin can no longer act on it', 'adm',
     "perform public.set_resolution_target(h1, now() + interval '2 days', null);", fail=True)
step('new handler can act on it', 'res2', "perform public.set_resolution_target(h1, now() + interval '2 days', null);")
step('resident cannot take a case', 'res', "perform public.take_over_case(h1, 'I want it');", fail=True)
step('version bumps on every change (stale-page guard)', 'pg',
     "if (select version from public.reports where id = h1) < 2 then raise exception 'version %', (select version from public.reports where id = h1); end if;")

step('resident asks for a name change', 'res', "perform public.request_profile_change('full_name', 'Testing, Sweep', 'Typo in my name');")
step('admins notified, linked to the resident', 'pg',
     "if not exists (select 1 from public.notifications where user_id = v_adm and subject_user_id = v_res and message ilike '%change their name%') then raise exception 'no linked notification'; end if;")
step('name in the notification reads First Last', 'pg',
     "if not exists (select 1 from public.notifications where user_id = v_adm and subject_user_id = v_res and message ilike 'Resident Sweep%') then raise exception '%', (select message from public.notifications where user_id = v_adm and subject_user_id = v_res limit 1); end if;")
step('resident cannot approve their own request', 'res',
     "perform public.decide_profile_request((select id from public.profile_requests where user_id = v_res and status = 'pending' limit 1), true, null);", fail=True)
step('admin approves the name change', 'adm',
     "perform public.decide_profile_request((select id from public.profile_requests where user_id = v_res and status = 'pending' limit 1), true, null);\n    execute 'reset role';\n"
     "    if (select full_name from public.users where id = v_res) <> 'Testing, Sweep' then raise exception 'name is %', (select full_name from public.users where id = v_res); end if;")
step('resident sends a new ID photo', 'res', f"perform public.request_id_reupload('barangay_id', '{IMG}', null);")
step('ID request waits for an admin', 'pg',
     "if not exists (select 1 from public.profile_requests where user_id = v_res and kind = 'id_document' and status = 'pending') then raise exception 'no pending ID request'; end if;")

step('resident cannot create an admin', 'res', "perform public.create_admin_account('sweep.no@example.com', 'No, Admin', '09999999906');", fail=True)
step('admin creates a new admin', 'adm',
     "perform public.create_admin_account('sweep.newadmin@example.com', 'Admin, New', '09999999905');\n    execute 'reset role';\n"
     "    if not exists (select 1 from public.users where email = 'sweep.newadmin@example.com' and role = 'admin' and must_change_password) then raise exception 'new admin row missing or not flagged'; end if;")

step('resident with complaints deletes their account (scrubbed, reports kept)', 'res',
     "perform public.request_account_deletion();\n    execute 'reset role';\n"
     "    if (select full_name from public.users where id = v_res) <> 'Deleted Resident' then raise exception 'not scrubbed'; end if;\n"
     "    if not exists (select 1 from public.reports where id = h1) then raise exception 'report gone'; end if;")

step('every case trail intact (audit_integrity)', 'pg',
     "perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); if exists (select 1 from public.audit_integrity() where broken > 0) then raise exception 'broken: %', (select string_agg(scope || '=' || broken, ', ') from public.audit_integrity() where broken > 0); end if;")
step('keep-awake job scheduled', 'pg',
     "if not exists (select 1 from cron.job where jobname = 'keep-portal-awake' and active) then raise exception 'no job'; end if;")


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
  h1 uuid;
begin
{setup}  update public.users set role = 'admin' where id = v_res2;
  v_log := 'setup ok';
{body()}
  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
"""
open(os.path.join(HERE, '02_handlers_requests_accounts.sql'), 'w', encoding='utf-8').write(sql)
print(len(steps), 'steps')
