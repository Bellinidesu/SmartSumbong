"""Builds sweep.sql: the whole complaint life cycle, as each role, in one
DO block that always ends by raising, so Postgres rolls everything back.
The raised message carries the log."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

ROLES = {'res': 'v_res', 'res2': 'v_res2', 'tan': 'v_tan', 'adm': 'v_adm'}


def as_role(who):
    if who == 'pg':
        return ''
    v = ROLES[who]
    return (f"perform set_config('request.jwt.claims', json_build_object('sub', {v}::text, 'role', 'authenticated')::text, true);\n"
            f"    perform set_config('request.jwt.claim.sub', {v}::text, true);\n"
            f"    execute 'set local role authenticated';\n")


steps = []


def step(label, who, sql, fail=False):
    steps.append((label, who, sql.strip(), fail))


def body():
    out = []
    for label, who, sql, fail in steps:
        lab = label.replace("'", "''")
        ok = f"v_log := v_log || E'\\n' || '{'BAD ' if fail else 'ok  '}{lab}' || {'' if not fail else chr(39) + ' (should have been refused)' + chr(39) + ' ||'} '';"
        err = (f"v_log := v_log || E'\\n' || 'ok  {lab} (refused: ' || left(sqlerrm, 120) || ')';" if fail
               else f"v_log := v_log || E'\\n' || 'FAIL {lab}: ' || left(sqlerrm, 220);")
        out.append(f"""  begin
    {as_role(who)}    {sql}
    execute 'reset role';
    {ok}
  exception when others then
    {err}
  end;""")
    return '\n'.join(out)


IMG = "https://res.cloudinary.com/nwb2kryl/image/upload/v1/{f}/{u}.jpg"


def media(folder, u):
    return f"""jsonb_build_array(jsonb_build_object('media_url', '{IMG.format(f=folder, u=u)}', 'mime_type', 'image/jpeg', 'bytes', 1000))"""


LAT, LON = 14.5269, 121.0155


def file(var, who='res', cat='street_obstruction'):
    step(f'resident files {var}', who,
         f"perform public.file_report('{cat}', 'Sweep test {var}', 'Automated sweep, rolled back.', {LAT}, {LON}, false, '[]'::jsonb, gen_random_uuid());\n"
         f"    execute 'reset role';\n"
         f"    select id into {var} from public.reports where resident_id = {ROLES[who]} and subject = 'Sweep test {var}';\n"
         f"    if {var} is null then raise exception 'no report row'; end if;")


def dispatched(rv, dv):
    step(f'{dv} found', 'pg', f"select id into {dv} from public.dispatches where report_id = {rv} and state in ('assigned','accepted') order by assigned_at desc limit 1; if {dv} is null then raise exception 'no live dispatch'; end if;")


def expect(label, who, cond_sql):
    step(label, who, f"if not ({cond_sql}) then raise exception 'condition false'; end if;")


# ---------- setup ----------
setup = f"""
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
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint({LON}, {LAT}), 4326), last_location_at = now() where id = v_tan;
  v_log := 'setup ok: 4 accounts';
"""

# ---------- report 1: the main cycle ----------
expect('role switch works (acting as the resident, not postgres)', 'res', "current_user = 'authenticated' and auth.uid() = v_res")
file('r1')
expect('resident reads own report', 'res', "exists (select 1 from public.reports where id = r1)")
expect('other resident cannot read it (RLS)', 'res2', "not exists (select 1 from public.reports where id = r1)")
expect('tanod cannot read it before dispatch (RLS)', 'tan', "not exists (select 1 from public.reports where id = r1)")
step('resident cannot validate own report', 'res', "perform public.review_report(r1, 'validate');", fail=True)
step('admin validates', 'adm', "perform public.review_report(r1, 'validate');")
step('dispatch refused without a target date', 'adm', "perform public.admin_dispatch(r1, v_tan, 'Check the sidewalk');", fail=True)
step('admin sets target date', 'adm', "perform public.set_resolution_target(r1, now() + interval '2 days');")
expect('tanod roster lists the tanod as assignable', 'adm', "exists (select 1 from public.tanod_roster(r1) t where t.tanod_id = v_tan and t.assignable)")
step('admin dispatches', 'adm', "perform public.admin_dispatch(r1, v_tan, 'Check the sidewalk');")
dispatched('r1', 'd1')
expect('tanod now reads the report', 'tan', "exists (select 1 from public.reports where id = r1)")
expect('tanod got an assignment notification', 'pg', "exists (select 1 from public.notifications where user_id = v_tan and report_id = r1)")
step('tanod accepts', 'tan', "perform public.accept_dispatch(d1);")
expect('report is in progress after accept', 'pg', "(select status from public.reports where id = r1) = 'in_progress'")
step('tanod: on the way', 'tan', "perform public.set_dispatch_step(d1, 'on_the_way');")
step('tanod: arrived', 'tan', "perform public.set_dispatch_step(d1, 'arrived');")
step('tanod posts an update with a photo', 'tan', f"perform public.post_dispatch_update(d1, 'Owner is moving the cart.', {media('dispatch', 'aaaaaaaa-1111-4111-8111-111111111111')});")
step('tanod photo outside the pinned folder refused', 'tan', f"perform public.post_dispatch_update(d1, 'x', {media('ids', 'aaaaaaaa-1111-4111-8111-111111111112')});", fail=True)
step('admin replies in the dispatch thread', 'adm', "perform public.post_dispatch_update(d1, 'Thanks, take a photo after.');")
step('admin asks the resident for details', 'adm', "perform public.request_additional_details(r1, 'Which store exactly?');")
step('resident answers the details request', 'res', "perform public.submit_additional_details((select id from public.detail_requests where report_id = r1 and responded_at is null limit 1), 'The one beside the bakery.');")
step('resident asks the barangay', 'res', "perform public.post_report_message(r1, 'Any news?');")
step('admin answers the resident', 'adm', "perform public.post_report_message(r1, 'A tanod is there now.');")
step('tanod resolves (field report)', 'tan', "perform public.submit_field_report(d1, 'Cart moved, sidewalk clear.');")
expect('resolution waits for approval (still in progress)', 'pg', "(select status from public.reports where id = r1) = 'in_progress' and (select resolution_submitted_at from public.reports where id = r1) is not null")
step('admin returns the resolution', 'adm', "perform public.reject_resolution(r1, 'Please attach a photo.');")
step('tanod resolves again', 'tan', "perform public.submit_field_report((select id from public.dispatches where report_id = r1 order by assigned_at desc limit 1), 'Photo attached this time.');")
step('admin approves the resolution', 'adm', "perform public.approve_resolution(r1);")
expect('report is resolved', 'pg', "(select status from public.reports where id = r1) = 'resolved'")
step('resident rates it', 'res', "insert into public.feedback (report_id, resident_id, rating, comment) values (r1, v_res, 5, 'Fast.');")
step('second rating refused', 'res', "insert into public.feedback (report_id, resident_id, rating, comment) values (r1, v_res, 1, 'Again');", fail=True)
step('other resident cannot rate it', 'res2', "insert into public.feedback (report_id, resident_id, rating) values (r1, v_res2, 1);", fail=True)
step('resident requests reopening', 'res', "perform public.request_reopen(r1, 'The cart came back.');")
step('admin reopens', 'adm', "perform public.reopen_report(r1, 'Confirmed on site.');")
expect('reopened report is back with the barangay', 'pg', "(select status from public.reports where id = r1) not in ('resolved','closed')")
step('admin publishes it to the residents map', 'adm', "perform public.set_report_public(r1, true);")
expect('residents map lists it', 'res2', "exists (select 1 from public.public_incidents())")
expect('r1 trail (30+ entries, many in one transaction) fully intact', 'adm', "(select bool_and(intact) and count(*) > 10 from public.verify_report_trail(r1))")
expect('resident may verify own trail', 'res', "(select bool_and(intact) from public.verify_report_trail(r1))")
step('other resident may not verify it', 'res2', "perform public.verify_report_trail(r1);", fail=True)
expect('resident sees notifications for it', 'res', "(select count(*) from public.notifications where report_id = r1) >= 3")

# ---------- report 2: Rose's 0079 ----------
file('r2')
step('admin validates r2', 'adm', "perform public.review_report(r2, 'validate');")
step('admin sets r2 target', 'adm', "perform public.set_resolution_target(r2, now() + interval '1 day');")
step('extension without a reason refused', 'adm', "perform public.set_resolution_target(r2, now() + interval '2 days');", fail=True)
step('extension 1 with a reason', 'adm', "perform public.set_resolution_target(r2, now() + interval '2 days', 'Owner away until Monday');")
step('extension 2 with a reason', 'adm', "perform public.set_resolution_target(r2, now() + interval '3 days', 'Waiting for the city crew');")
step('extension 3 refused (cap 2)', 'adm', "perform public.set_resolution_target(r2, now() + interval '4 days', 'One more week please');", fail=True)
expect('extensions recorded in sla_extensions', 'pg', "(select count(*) from public.sla_extensions where report_id = r2) = 2")
step('resident cannot hand a case up', 'res', "perform public.hand_to_higher_official(r2, 'Punong Barangay');", fail=True)
step('admin hands r2 to a higher official', 'adm', "perform public.hand_to_higher_official(r2, 'Punong Barangay', 'For mediation.');")
expect('r2 handled by the official, still open', 'pg', "(select higher_official from public.reports where id = r2) = 'Punong Barangay' and (select status from public.reports where id = r2) = 'in_progress'")
step('fresh extension after the hand-up', 'adm', "perform public.set_resolution_target(r2, now() + interval '5 days', 'New official needs time');")
step('admin posts an update with a photo, no tanod', 'adm', f"perform public.admin_barangay_update(r2, 'Talked to the owner.', {media('barangay', 'bbbbbbbb-2222-4222-8222-222222222222')});")
step('admin photo outside the barangay folder refused', 'adm', f"perform public.admin_barangay_update(r2, 'x', {media('reports', 'bbbbbbbb-2222-4222-8222-222222222223')});", fail=True)
step('empty update refused', 'adm', "perform public.admin_barangay_update(r2, '  ');", fail=True)
step('admin resolves r2 with proof photos', 'adm', f"perform public.admin_set_status(r2, 'resolved', 'Cleared by the barangay.', {media('barangay', 'bbbbbbbb-2222-4222-8222-222222222224')});")
expect('resident sees both barangay photos', 'res', "(select count(*) from public.report_evidence where report_id = r2) = 2")
expect('other resident sees none', 'res2', "(select count(*) from public.report_evidence where report_id = r2) = 0")
step('resident cannot insert evidence directly', 'res', f"insert into public.report_evidence (report_id, posted_by, kind, media_url, mime_type, bytes) values (r2, v_res, 'update', '{IMG.format(f='barangay', u='bbbbbbbb-2222-4222-8222-222222222225')}', 'image/jpeg', 10);", fail=True)

# ---------- report 3: escalation through the tanod ----------
file('r3', cat='peace_order_nuisance')
step('admin validates r3', 'adm', "perform public.review_report(r3, 'validate');")
step('admin sets r3 target', 'adm', "perform public.set_resolution_target(r3, now() + interval '1 day');")
step('admin dispatches r3', 'adm', "perform public.admin_dispatch(r3, v_tan, 'Talk to both sides');")
dispatched('r3', 'd3')
step('tanod accepts r3', 'tan', "perform public.accept_dispatch(d3);")
step('tanod requests escalation', 'tan', "perform public.request_escalation(d3, 'Domestic dispute, needs VAWC', 'VAWC Desk');")
step('admin approves the escalation', 'adm', "perform public.approve_escalation((select id from public.escalation_requests where report_id = r3 and status = 'pending' limit 1), 'VAWC Desk', 'Bring an ID.');")
expect('r3 referred out', 'pg', "(select referred_to from public.reports where id = r3) is not null")

# ---------- report 4: reject and appeal ----------
file('r4')
step('admin rejects r4', 'adm', "perform public.review_report(r4, 'reject', 'Outside the barangay.');")
step('appeal photo from the tanod folder refused', 'res', f"perform public.request_appeal(r4, 'It is inside, near the chapel.', {media('dispatch', 'cccccccc-3333-4333-8333-333333333333')});", fail=True)
step('resident appeals with a photo', 'res', f"perform public.request_appeal(r4, 'It is inside, near the chapel.', {media('reports', 'cccccccc-3333-4333-8333-333333333334')});")
step('admin grants the appeal', 'adm', "perform public.appeal_report(r4, 'Checked the map.');")
expect('r4 back to validated', 'pg', "(select status from public.reports where id = r4) = 'validated'")

# ---------- report 5: cancel ----------
file('r5')
step('other resident cannot cancel it', 'res2', "perform public.cancel_report(r5);", fail=True)
step('resident cancels r5', 'res', "perform public.cancel_report(r5, 'Sorted it out myself.');")
expect('r5 cancelled', 'pg', "(select status from public.reports where id = r5) = 'cancelled'")

# ---------- report 6: tanod hands back, admin reroutes ----------
file('r6')
step('admin validates r6', 'adm', "perform public.review_report(r6, 'validate');")
step('admin sets r6 target', 'adm', "perform public.set_resolution_target(r6, now() + interval '1 day');")
step('admin dispatches r6', 'adm', "perform public.admin_dispatch(r6, v_tan, 'Check it');")
dispatched('r6', 'd6')
step('tanod hands r6 back', 'tan', "perform public.reroute_dispatch(d6, 'On another call.');")
expect('r6 dispatch no longer live for the tanod', 'pg', "not exists (select 1 from public.dispatches where id = d6 and state in ('assigned','accepted'))")

# ---------- report 7: overdue follow-up, direct referral ----------
file('r7')
step('admin validates r7', 'adm', "perform public.review_report(r7, 'validate');")
step('r7 made overdue', 'pg', "update public.reports set due_at = now() - interval '1 hour' where id = r7;")
step('resident follows up on the overdue case', 'res', "perform public.follow_up_report(r7, 'Still there.');")
step('second follow-up the same day refused', 'res', "perform public.follow_up_report(r7, 'Again.');", fail=True)
step('admin escalates r7 directly', 'adm', "perform public.refer_report(r7, 'PNP', 'Police matter.');")

# ---------- reads and scheduled jobs ----------
step('dashboard figures', 'adm', "perform public.dashboard_metrics(now() - interval '30 days', now());")
step('hotspots', 'adm', "perform public.report_hotspots(now() - interval '30 days', now());")
step('tanod reports a location', 'tan', f"perform public.update_my_location({LAT}, {LON});")
step('sweep: overdue verifications', 'pg', "perform public.sweep_overdue_verifications();")
step('sweep: unaccepted dispatches', 'pg', "perform public.sweep_unaccepted_dispatches();")
step('sweep: awaiting units', 'pg', "perform public.sweep_awaiting_units();")
step('sweep: overdue reports', 'pg', "perform public.sweep_overdue_reports();")
expect('timeline bylines function exists (my_status_log_authors)', 'pg', "exists (select 1 from pg_proc where proname = 'my_status_log_authors')")

sql = f"""do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_adm uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; r5 uuid; r6 uuid; r7 uuid;
  d1 uuid; d3 uuid; d6 uuid;
begin
{setup}
{body()}
  raise exception 'SWEEP-ROLLBACK%', v_log;
end
$sweep$;
"""
open(os.path.join(HERE, '01_lifecycle.sql'), 'w', encoding='utf-8').write(sql)
print(len(steps), 'steps')
