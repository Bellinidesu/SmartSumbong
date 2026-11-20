#!/usr/bin/env python3
"""Generator for DRAFT 0191 case_rule_consistency (Ace, 21 Nov: "do the recommendation on the four old behaviours"). Never applies anything.
Reads the CURRENT definitions from the local database (a full build of the migrations on main), writes into supabase/drafts/:
  0191_case_rule_consistency.sql   the change (header 'DRAFT: not applied until Ace says apply 0191')
  0191_undo.sql                    the previous definitions, word for word, plus the previous reports_resident_read policy
  tests/71_case_rule_consistency.test.sql   pgTAP-style, rolled back: fails before, passes after
The four intended changes, in the per-case function (_user_sees_case) and in the 0189 set helpers / reports policy, in lockstep:
  1 deleted cases  : a Kagawad or staff member no longer reads a soft-deleted case or any row hanging off it (super admins and captain still do)
  2 retired        : a retired admin sees nothing as an administrator in the rule; _notifications_scope drops CASE notices addressed to retired admins
  3 committee on   : the committee branch needs the viewer's committee switched on (committees.active); assign_case refuses to place a case with a switched-off committee
  4 awaiting place : a Kagawad (any admin) who is the case's handler keeps seeing their own case while it awaits placement
usage: SWEEP_PORT=55444 FIX_TEMPLATE=postgres python fix/gen_case_rule_consistency.py"""
import re
from fixlib import *


def must(text, old, new, what):
    if old not in text:
        raise SystemExit(f"cannot rewrite {what}: the current definition has changed shape")
    return text.replace(old, new, 1)


def main():
    # ---- the new per-case rule ----
    usc_old = fn_def("_user_sees_case(uuid,uuid,complaint_category,uuid)")
    usc_new = """create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    -- 0191 (2): a retired admin sees nothing as an administrator, in any branch (even a case they handled)
    when r.retired then false
    -- 0191 (1): a Kagawad or staff member no longer sees a soft-deleted case (super admins and captain still do)
    when r.deleted and r.tier in ('committee', 'moderator') then false
    -- 19 Nov 2026 (Rose): staff see a complaint only once their councilor (or a super admin) has assigned it to them
    when r.tier = 'moderator' then
         (p_handler is not null and p_handler = p_user)
      or (r.assigned_to is not null and r.assigned_to = p_user)
      or exists (select 1 from public.case_handler_log l
                  where l.report_id = p_report and l.admin_id = p_user and l.action in ('take', 'take_over', 'accept'))
    -- 0191 (4): the case's own handler keeps seeing it while it waits for placement; everyone else still does not
    when r.awaiting_placement then (r.tier is not null and p_handler is not null and p_handler = p_user)
    when r.committee is not null then
         coalesce((select u.committee = r.committee and u.role = 'admin' and not coalesce(u.is_suspended, false)
                          -- 0191 (3): the committee must be switched on, as the category branch below already requires
                          and exists (select 1 from public.committees c where c.key = u.committee and c.active)
                     from public.users u where u.id = p_user), false)
      or (p_handler is not null and p_handler = p_user)
    else coalesce(public._user_sees_category(p_user, p_cat), false)
      or (p_handler is not null and p_handler = p_user)
      or exists (select 1 from public.report_concerns rc where rc.report_id = p_report and public._user_sees_category(p_user, rc.category))
  end
    from (select x.committee, coalesce(x.awaiting_placement, false) as awaiting_placement, x.assigned_to, (x.deleted_at is not null) as deleted,
                 (select u.admin_tier from public.users u where u.id = p_user and u.role = 'admin' and not coalesce(u.is_suspended, false)) as tier,
                 exists (select 1 from public.users u where u.id = p_user and u.role = 'admin' and coalesce(u.is_retired, false)) as retired
            from (select 1) one left join public.reports x on x.id = p_report) r
$function$;"""

    # ---- the set helpers of 0189, in lockstep ----
    helpers = """-- the caller's committee (Kagawad only), when that committee is switched on
create or replace function public._my_committee()
returns text language sql stable security definer set search_path = public as $$
  select u.committee from public.users u
    join public.committees c on c.key = u.committee and c.active
   where u.id = auth.uid() and public.admin_tier() = 'committee'
$$;

-- cases with no committee yet, not waiting for placement, not deleted, OUTSIDE the caller's categories but with a concern in one of them (Kagawad only)
create or replace function public._my_concern_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 200 as $$
  select distinct rc.report_id
    from public.report_concerns rc
    join public.reports r on r.id = rc.report_id
   where rc.category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.category <> all (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.committee is null and not coalesce(r.awaiting_placement, false) and r.deleted_at is null
$$;

-- cases the caller took, took over or accepted before (staff only), not deleted
create or replace function public._my_handled_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 100 as $$
  select l.report_id from public.case_handler_log l
    join public.reports r on r.id = l.report_id and r.deleted_at is null
   where l.admin_id = (select auth.uid()) and l.action in ('take', 'take_over', 'accept')
     and (select public.admin_tier()) = 'moderator'
$$;

-- every case a Kagawad or staff member sees: not deleted (0191 1); a Kagawad's own handled case even while it awaits placement (0191 4);
-- their committee's cases only while the committee is on (0191 3, in _my_committee()); empty for everyone else (a retired admin has no admin_tier, 0191 2)
create or replace function public._my_scoped_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 1000 as $$
  select r.id from public.reports r
   where (select public.admin_tier()) = 'moderator' and r.deleted_at is null
     and (r.handler_id = (select auth.uid()) or r.assigned_to = (select auth.uid()))
  union all
  select h.id from public._my_handled_case_ids() h(id)
  union all
  select r.id from public.reports r
   where (select public.admin_tier()) = 'committee' and r.deleted_at is null
     and (r.handler_id = (select auth.uid())
          or (not coalesce(r.awaiting_placement, false)
              and (r.committee = (select public._my_committee())
                   or (r.committee is null and r.category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))))))
  union all
  select c.id from public._my_concern_case_ids() c(id)
$$;"""
    reports_policy = """alter policy reports_resident_read on public.reports using (
  (deleted_at is null) and (
       (resident_id = (select auth.uid()))
    or (select public.is_full_viewer())
    or ((select public.admin_tier()) = 'moderator'
        and ((handler_id = (select auth.uid())) or (assigned_to = (select auth.uid()))
             or (id in (select s.id from public._my_handled_case_ids() s(id)))))
    or ((select public.admin_tier()) = 'committee'
        and ((handler_id = (select auth.uid()))
             or (not coalesce(awaiting_placement, false)
                 and ((committee = (select public._my_committee()))
                      or (committee is null and ((category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[])))
                                                 or (id in (select s.id from public._my_concern_case_ids() s(id)))))))))
    or (exists (select 1 from public.dispatches d where d.report_id = reports.id and d.tanod_id = (select auth.uid())))
  ));"""

    # ---- the notice trigger (0188): drop case notices addressed to retired admins ----
    ns_old = fn_def("_notifications_scope()")
    ns_new = must(ns_old, "select role::text, coalesce(admin_tier, 'super') into v_role, v_tier from public.users where id = new.user_id;",
                  "select role::text, coalesce(admin_tier, 'super'), coalesce(is_retired, false) into v_role, v_tier, v_ret from public.users where id = new.user_id;\n"
                  "    -- 0191 (2): a retired admin is told nothing about a case (a notice with no case, e.g. their own retirement, still arrives)\n"
                  "    if v_role = 'admin' and v_ret and new.report_id is not null then return null; end if;", "_notifications_scope")
    ns_new = must(ns_new, "declare v_role text; v_tier text;", "declare v_role text; v_tier text; v_ret boolean;", "_notifications_scope declare")
    ns_new = ns_new.replace("CREATE OR REPLACE FUNCTION", "create or replace function")

    # ---- assign_case: a super admin placing a case with a switched-off committee ----
    ac_old = fn_def("assign_case(uuid,uuid,text)")
    ac_new = must(ac_old, "  if v_tier = 'super' and a.committee is distinct from v_com then\n    perform set_config('smartsumbong.forwarding', 'on', true);",
                  "  if v_tier = 'super' and a.committee is distinct from v_com then\n"
                  "    -- 0191 (3): forward_case already refuses a committee that is switched off; assigning to its staff places the case the same way, so it refuses too\n"
                  "    if not exists (select 1 from public.committees c where c.key = a.committee and c.active) then\n"
                  "      raise exception 'That committee is switched off; choose someone of an active committee' using errcode = 'check_violation';\n"
                  "    end if;\n"
                  "    perform set_config('smartsumbong.forwarding', 'on', true);", "assign_case")
    ac_new = ac_new.replace("CREATE OR REPLACE FUNCTION", "create or replace function")

    up = "\n\n".join(["set search_path = public, extensions;\nset local lock_timeout = '5s';", usc_new, helpers, reports_policy, ns_new, ac_new])
    # ---- the undo: previous definitions, word for word ----
    pol = psql("select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.reports'::regclass and polname = 'reports_resident_read'", raw=True).replace(chr(13), "").strip()
    hel_old = "\n\n".join(fn_def(s).replace("CREATE OR REPLACE FUNCTION", "create or replace function") for s in
                          ["_my_committee()", "_my_concern_case_ids()", "_my_handled_case_ids()", "_my_scoped_case_ids()"])
    undo_sql = "\n\n".join(["set search_path = public, extensions;\nset local lock_timeout = '5s';",
                            usc_old.replace("CREATE OR REPLACE FUNCTION", "create or replace function"), hel_old,
                            f"alter policy reports_resident_read on public.reports using ({pol});", ns_old.replace("CREATE OR REPLACE FUNCTION", "create or replace function"),
                            ac_old.replace("CREATE OR REPLACE FUNCTION", "create or replace function")])
    undo_sql = "-- UNDO of 0191_case_rule_consistency: the definitions as they were after 0190 (word for word); no data changes. Tested: applying this after 0191 restores every function body and the policy text.\n" + undo_sql + "\n"

    why = """Ace, 21 Nov 2026: the recommendation on the four old behaviours of the case rule, one migration. Everything else about who sees what is unchanged.
  (1) DELETED CASES: rows hanging off a soft-deleted case (all the tables 0189's set covers) become invisible to Kagawad and staff; super admins and captain keep them (audit).
  (2) RETIRED: a retired admin sees nothing as an administrator in the rule (_user_sees_case and the set helpers); _notifications_scope drops CASE notices addressed to
      retired admins (a notice with no case, such as their own retirement, still arrives: the retiring person must be told).
  (3) COMMITTEE ON: the committee branch needs the viewer's committee switched on (committees.active), in the function and in _my_committee(); forward_case already refuses
      a switched-off committee; assign_case did not (a super admin giving a case to staff of another committee places it there): it now refuses too.
      Consequence to know: switching a committee off hides its existing cases from its own Kagawad (super admins still see them); live has 0 cases in the 7 switched-off committees.
  (4) AWAITING PLACEMENT: the case's own handler keeps seeing it while it waits for placement (staff assigned to it already did); other Kagawads still do not.
The per-case function (guards, notices, the queue, smart_module) and the 0189 set helpers / reports policy are kept in lockstep: tools/sweep/equiv_0191.py proves that the only
differences against 0190, per person and per table, are the four intended sets (and nothing else)."""
    undo_note = "supabase/drafts/0191_undo.sql restores _user_sees_case, the four helpers, reports_resident_read, _notifications_scope and assign_case word for word (tested); no data changes."
    test_sql = test_text()
    num, proven = emit_and_prove("case_rule_consistency", "the case rule: deleted cases, retired admins, switched-off committees, awaiting placement (four intended changes)",
                                 why, undo_note, up, "-- see supabase/drafts/0191_undo.sql", test_sql, "gen_case_rule_consistency.py")
    wt(DRAFTS / "0191_undo.sql", undo_sql)
    t = DRAFTS / "tests" / f"{num}_case_rule_consistency.test.sql"
    if t.exists(): t.replace(DRAFTS / "tests" / "71_case_rule_consistency.test.sql")
    # the undo is tested: apply the draft, then the undo; every function body and the policy text equal the original
    import hashlib
    scratch()
    sig = lambda: hashlib.md5("|".join(psql("select proname || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = any(array['_user_sees_case','_my_committee','_my_concern_case_ids','_my_handled_case_ids','_my_scoped_case_ids','_notifications_scope','assign_case']) order by 1", db=SCRATCH, raw=True).replace(chr(13), "").splitlines()).encode() + psql("select md5(pg_get_expr(polqual, polrelid)) from pg_policy where polname = 'reports_resident_read'", db=SCRATCH, raw=True).encode()).hexdigest()
    h0 = sig(); run_sql(DRAFTS / f"{num}_case_rule_consistency.sql"); h1 = sig(); run_sql(DRAFTS / "0191_undo.sql"); h2 = sig()
    print(f"  undo tested: the draft changes the definitions: {h0 != h1}; the undo restores them exactly: {h0 == h2}")


def test_text():
    t = _test_text()
    n = [0]
    def tid(m):
        n[0] += 1
        return f"values ('CONS-{n[0]:02d}', res,"
    t = t.replace("insert into public.reports (resident_id,", "insert into public.reports (tracking_id, resident_id,")
    return re.sub(r"values \(res,", tid, t)


def _test_text():
    return r"""-- 71_case_rule_consistency.sql (DRAFT test for 0191; moves to supabase/tests/ when Ace says apply 0191). Rolled back.
-- The four intended changes, each against an unchanged baseline: fails before 0191, passes after. (The 0189 equivalence stays pgTAP 67's.)
do $sweep$
declare
  v_log text := 'setup ok';
  ca text; cb text; cat_a public.complaint_category; cat_b public.complaint_category; n integer; b boolean;
  kA uuid := gen_random_uuid(); kA2 uuid := gen_random_uuid(); kOff uuid := gen_random_uuid(); kRet uuid := gen_random_uuid(); sA uuid := gen_random_uuid();
  sOff uuid := gen_random_uuid(); sup uuid := gen_random_uuid(); cap uuid := gen_random_uuid(); res uuid := gen_random_uuid();
  c_plain uuid; c_del uuid; c_ret uuid; c_off uuid; c_offh uuid; c_wait uuid; c_wait2 uuid;
  img text := 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/';
begin
  select c.key into ca from public.committees c where c.active and exists (select 1 from public.committee_categories cc where cc.committee = c.key) order by c.sort, c.key limit 1;
  select c.key into cb from public.committees c where c.active and c.key <> ca and exists (select 1 from public.committee_categories cc where cc.committee = c.key
          and cc.category not in (select category from public.committee_categories where committee = ca)) order by c.sort, c.key limit 1;
  select cc.category into cat_a from public.committee_categories cc where cc.committee = ca and cc.category not in (select category from public.committee_categories where committee = cb) limit 1;
  select cc.category into cat_b from public.committee_categories cc where cc.committee = cb and cc.category not in (select category from public.committee_categories where committee = ca) limit 1;
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', img || 'ids/' || gen_random_uuid() || '.jpg', 'selfie_url', img || 'selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (kA, '+639999997101', 'Cons, Kagawad A'), (kA2, '+639999997102', 'Cons, Kagawad A Two'), (kOff, '+639999997103', 'Cons, Kagawad Off'),
                 (kRet, '+639999997104', 'Cons, Kagawad Retired'), (sA, '+639999997105', 'Cons, Staff A'), (sOff, '+639999997106', 'Cons, Staff Off'),
                 (sup, '+639999997107', 'Cons, Super'), (cap, '+639999997108', 'Cons, Captain'), (res, '+639999997109', 'Cons, Resident')) as x(id, mob, nm);
  set local session_replication_role = replica;
  update public.users set verification_status = 'verified', verified_at = now() where id in (kA, kA2, kOff, kRet, sA, sOff, sup, cap, res);
  update public.users set role = 'admin', admin_tier = 'committee', committee = ca where id in (kA, kA2, kRet);
  update public.users set role = 'admin', admin_tier = 'committee', committee = cb where id = kOff;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = ca where id = sA;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = cb where id = sOff;
  update public.users set role = 'admin', admin_tier = 'super' where id = sup;
  update public.users set role = 'admin', admin_tier = 'captain' where id = cap;
  update public.users set is_retired = true where id = kRet;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_a, 'Plain', 'ordinary case of committee A', 14.519, 121.012, ca, false, null, null) returning id into c_plain;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_a, 'Deleted', 'a deleted case of committee A', 14.519, 121.012, ca, false, null, now()) returning id into c_del;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_a, 'Retired handler', 'handled by a retired Kagawad', 14.519, 121.012, ca, false, kRet, null) returning id into c_ret;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_b, 'Off committee', 'with committee B, which is switched off below', 14.519, 121.012, cb, false, null, null) returning id into c_off;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_b, 'Off committee handled', 'with committee B, handled by its Kagawad', 14.519, 121.012, cb, false, kOff, null) returning id into c_offh;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_a, 'Awaiting, handled by A', 'waiting for placement, handled by Kagawad A', 14.519, 121.012, null, true, kA, null) returning id into c_wait;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values (res, cat_a, 'Awaiting, handled by A2', 'waiting for placement, handled by another Kagawad of A', 14.519, 121.012, null, true, kA2, null) returning id into c_wait2;
  insert into public.status_logs (report_id, changed_by, new_status, remark, is_system) select id, res, 'pending_review', 'cons', true from public.reports where subject in
    ('Plain', 'Deleted', 'Retired handler', 'Off committee', 'Off committee handled', 'Awaiting, handled by A', 'Awaiting, handled by A2');
  set local session_replication_role = origin;
  update public.committees set active = false where key = cb;   -- (3) committee B is switched off from here on

  -- the baseline that must not change: an ordinary case of the Kagawad's committee is read by both Kagawads of it and by the staff only once assigned
  begin
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_plain; execute 'reset role';
    if n <> 1 then raise exception 'Kagawad A does not read the ordinary case'; end if;
    if not public._user_sees_case(kA, c_plain, cat_a, null) or not public._user_sees_case(kA2, c_plain, cat_a, null) then raise exception 'the function says a Kagawad of the committee does not see it'; end if;
    if public._user_sees_case(sA, c_plain, cat_a, null) then raise exception 'unassigned staff see it'; end if;
    v_log := v_log || E'\nok  baseline: an ordinary case of committee A is read by its Kagawads and not by unassigned staff';
  exception when others then reset role; v_log := v_log || E'\nFAIL baseline: ' || sqlerrm; end;

  -- 1. deleted cases
  begin
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n <> 0 then raise exception 'a Kagawad reads the status log of a deleted case (% rows)', n; end if;
    if public._user_sees_case(kA, c_del, cat_a, null) then raise exception 'the function says a Kagawad sees the deleted case'; end if;
    perform set_config('request.jwt.claim.sub', sup::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n = 0 then raise exception 'a super admin no longer reads a deleted case''s rows'; end if;
    perform set_config('request.jwt.claim.sub', cap::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n = 0 then raise exception 'the captain no longer reads a deleted case''s rows'; end if;
    v_log := v_log || E'\nok  (1) a deleted case and its rows are hidden from a Kagawad (policy and function); the super admin and the captain still read them';
  exception when others then reset role; v_log := v_log || E'\nFAIL (1) deleted: ' || sqlerrm; end;

  -- 2. retired
  begin
    if public._user_sees_case(kRet, c_ret, cat_a, kRet) or public._user_sees_case(kRet, c_plain, cat_a, null) then raise exception 'the function says a retired Kagawad sees a case'; end if;
    perform set_config('request.jwt.claim.sub', kRet::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id in (c_ret, c_plain); execute 'reset role';
    if n <> 0 then raise exception 'a retired Kagawad reads % cases', n; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (kRet, c_ret, 'status_change', 'for a retired admin about a case');
    insert into public.notifications (user_id, kind, message) values (kRet, 'status_change', 'for a retired admin, no case');
    if exists (select 1 from public.notifications where message = 'for a retired admin about a case') then raise exception 'a case notice reached a retired admin'; end if;
    if not exists (select 1 from public.notifications where message = 'for a retired admin, no case') then raise exception 'a notice with no case no longer reaches a retired admin'; end if;
    v_log := v_log || E'\nok  (2) a retired Kagawad sees nothing (not even the case they handled) and case notices to them are dropped; a notice with no case still arrives';
  exception when others then reset role; v_log := v_log || E'\nFAIL (2) retired: ' || sqlerrm; end;

  -- 3. committee switched on
  begin
    if public._user_sees_case(kOff, c_off, cat_b, null) then raise exception 'the function says the Kagawad of a switched-off committee sees its case'; end if;
    perform set_config('request.jwt.claim.sub', kOff::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_off; execute 'reset role';
    if n <> 0 then raise exception 'the Kagawad of a switched-off committee reads its case'; end if;
    perform set_config('request.jwt.claim.sub', kOff::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_offh; execute 'reset role';
    if n <> 1 then raise exception 'the Kagawad no longer reads the case they handle'; end if;
    perform set_config('request.jwt.claim.sub', sup::text, true); execute 'set local role authenticated';
    begin perform public.assign_case(c_plain, sOff, 'probe'); raise exception 'assign_case placed a case with a switched-off committee';
    exception when check_violation then null; end;
    select count(*) into n from public.reports where id = c_off; execute 'reset role';
    if n <> 1 then raise exception 'a super admin no longer reads the case'; end if;
    v_log := v_log || E'\nok  (3) a switched-off committee''s Kagawad no longer sees its cases (the one they handle stays); a super admin sees it and cannot place a case with that committee';
  exception when others then reset role; v_log := v_log || E'\nFAIL (3) committee on: ' || sqlerrm; end;

  -- 4. awaiting placement
  begin
    if not public._user_sees_case(kA, c_wait, cat_a, kA) then raise exception 'the function says the handling Kagawad does not see their awaiting case'; end if;
    if public._user_sees_case(kA, c_wait2, cat_a, kA2) then raise exception 'the function says a Kagawad sees another Kagawad''s awaiting case'; end if;
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_wait; if n <> 1 then raise exception 'the handling Kagawad does not read their awaiting case'; end if;
    select count(*) into n from public.status_logs where report_id = c_wait; if n <> 1 then raise exception 'the handling Kagawad does not read its status log'; end if;
    select count(*) into n from public.reports where id = c_wait2; execute 'reset role';
    if n <> 0 then raise exception 'a Kagawad reads another Kagawad''s awaiting case'; end if;
    v_log := v_log || E'\nok  (4) the Kagawad who handles a case that awaits placement still sees it (case and rows); another Kagawad of the committee does not';
  exception when others then reset role; v_log := v_log || E'\nFAIL (4) awaiting placement: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
"""


if __name__ == "__main__":
    main()
