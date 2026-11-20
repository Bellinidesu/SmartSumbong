-- 0189: the case rule at scale (K-04 option B, Ace 20 Nov 2026). WHO SEES WHAT DOES NOT CHANGE; only how the database works it out.
-- DRAFT: not applied until Ace says "apply 0189". Undo: supabase/drafts/0189_undo.sql (restores every policy below word for word and drops the helpers).
--
-- Why: every row of reports (and of 20 tables hanging off a case) ran the case rule as a function, once per row, and each run re-read the case and
-- the caller several times. Fine at today's 82 cases (~100 ms), seconds at 4,000, 15-30 s at 20,000 (docs/sweep/options/K-04-f09-case-rule.md).
-- Now the caller's facts are read ONCE per query (their rung, committee, the committee's categories, the cases they handled before) and the rule is a
-- plain condition on the row the planner can run in one pass. Nothing is remembered between queries: a revoked assignment, a forward or a suspension
-- counts from the very next query, exactly as before.
--
-- The rule, unchanged (0175, _user_sees_case):
--   super admin, captain   every case
--   Kagawad                a case of their committee (forwarded to it); a case with no committee yet in one of their committee's categories (or with a
--                          concern in one); a case they handle; never a case waiting for placement; a case forwarded away from them drops off
--   staff                  a case they handle, are assigned, or took / took over / accepted before (case_handler_log)
--   resident               their own; tanod: the cases they were dispatched to
--   suspended, retired     nothing as an administrator (their own rows as before)
-- Deleted cases: reports never shows them (as before); the rows hanging off a deleted case stay readable to the administrators who could read them
-- before (admin_sees_report never looked at deleted_at; kept identical on purpose, see the report).
--
-- What is new: 7 small helpers (security definer, search_path pinned, callable by signed-in users only; each returns only what the caller may already
-- read) and 22 policies rewritten with ALTER POLICY. _user_sees_case, admin_sees_report, admin_sees_case, admin_sees_dispatch, _admin_sees_user stay
-- as they are: the functions (guards, notices, the queue) still call them for one case at a time, which is cheap.
-- Not touched: the two INSERT checks (status_logs_insert, look_shares_admin_insert) run once per inserted row; nothing else changes.
--
-- Proof (tools/sweep/equiv_case_rule.py, on copies built from 0001-0188 whose 167 policies equal live): 28 people x 139,724 rows of an exhaustive fixture
-- (3,912,272 pairs): the rows each person reads in all 22 tables are identical before, after, and after the undo. pgTAP 67 passes on the old and the new
-- rule and fails on 5 deliberately broken ones; all 66 pgTAP scripts and the 37,642 probes give the same results before and after; every page request
-- replayed at 1x/50x/250x answers the same rows. Draft test 68 (supabase/drafts/tests) fails before this file and passes after it.
--
-- Rollout: one transaction (supabase db push runs the file as one; by hand psql -1 -f). CREATE FUNCTION takes no table lock; each ALTER POLICY takes an
-- ACCESS EXCLUSIVE lock on its table (22 tables) held until COMMIT: well under a second on 82 cases, but reads of those tables queue behind it, and it
-- queues behind any long query: lock_timeout 5s makes it give up and roll back rather than stall the portal. Order: helpers, reports, the rest.
-- Each rewritten policy is equivalent on its own, so even a partial apply would not change who sees what.
-- Realtime: Supabase Realtime checks each change against each subscriber's policies; a Kagawad/staff subscriber now builds the case set once per
-- check (sub-millisecond at 82 cases, grows with the case count; see the report), where it used to run the per-case function once.

set search_path = public, extensions;
set local lock_timeout = '5s';

-- ---------- the caller's facts, once per query ----------

-- the caller's committee (Kagawad only)
create or replace function public._my_committee()
returns text language sql stable security definer set search_path = public as $$
  select u.committee from public.users u
   where u.id = auth.uid() and public.admin_tier() = 'committee'
$$;

-- the categories of the caller's committee, if it is switched on (Kagawad only)
create or replace function public._my_categories()
returns public.complaint_category[] language sql stable security definer set search_path = public as $$
  select coalesce(array(
    select cc.category
      from public.users u
      join public.committees c on c.key = u.committee and c.active
      join public.committee_categories cc on cc.committee = c.key
     where u.id = auth.uid() and public.admin_tier() = 'committee'), '{}')
$$;

-- cases with no committee yet, not waiting for placement, OUTSIDE the caller's categories but with a concern in one of them (Kagawad only).
-- (A case inside the categories is already seen by its category; every case has a concern of its own category, so leaving those out halves the work.)
create or replace function public._my_concern_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 200 as $$
  select distinct rc.report_id
    from public.report_concerns rc
    join public.reports r on r.id = rc.report_id
   where rc.category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.category <> all (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.committee is null and not coalesce(r.awaiting_placement, false)
$$;

-- cases the caller took, took over or accepted before (staff only)
create or replace function public._my_handled_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 100 as $$
  select l.report_id from public.case_handler_log l
   where l.admin_id = (select auth.uid()) and l.action in ('take', 'take_over', 'accept')
     and (select public.admin_tier()) = 'moderator'
$$;

-- every case a Kagawad or staff member sees (deleted ones included, as admin_sees_report did); empty for everyone else
create or replace function public._my_scoped_case_ids()
returns setof uuid language sql stable security definer set search_path = public rows 1000 as $$
  select r.id from public.reports r
   where (select public.admin_tier()) = 'moderator'
     and (r.handler_id = (select auth.uid()) or r.assigned_to = (select auth.uid()))
  union all
  select h.id from public._my_handled_case_ids() h(id)
  union all
  select r.id from public.reports r
   where (select public.admin_tier()) = 'committee'
     and not coalesce(r.awaiting_placement, false)
     and (r.handler_id = (select auth.uid())
          or r.committee = (select public._my_committee())
          or (r.committee is null and r.category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))))
  union all
  select c.id from public._my_concern_case_ids() c(id)
$$;

-- the dispatches of those cases
create or replace function public._my_scoped_dispatch_ids()
returns setof uuid language sql stable security definer set search_path = public rows 1000 as $$
  select d.id from public.dispatches d where d.report_id in (select s.id from public._my_scoped_case_ids() s(id))
$$;

-- the residents who filed those cases (not deleted ones: as _admin_sees_user)
create or replace function public._my_scoped_resident_ids()
returns setof uuid language sql stable security definer set search_path = public rows 1000 as $$
  select r.resident_id from public.reports r
   where r.deleted_at is null and r.id in (select s.id from public._my_scoped_case_ids() s(id))
$$;

do $grants$
declare f text;
begin
  foreach f in array array['_my_committee()', '_my_categories()', '_my_concern_case_ids()', '_my_handled_case_ids()', '_my_scoped_case_ids()',
                           '_my_scoped_dispatch_ids()', '_my_scoped_resident_ids()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $grants$;

comment on function public._my_scoped_case_ids() is
  '0189: the ids of every case the signed-in Kagawad or staff member sees (the 0175 rule, as _user_sees_case, deleted cases included as admin_sees_report). Read once per query by the policies; empty for every other caller.';

-- ---------- reports: the rule written out on the row ----------
alter policy reports_resident_read on public.reports using (
  (deleted_at is null) and (
       (resident_id = (select auth.uid()))
    or (select public.is_full_viewer())
    or ((select public.admin_tier()) = 'moderator'
        and ((handler_id = (select auth.uid())) or (assigned_to = (select auth.uid()))
             or (id in (select s.id from public._my_handled_case_ids() s(id)))))
    or ((select public.admin_tier()) = 'committee'
        and not coalesce(awaiting_placement, false)
        and ((handler_id = (select auth.uid()))
             or (committee = (select public._my_committee()))
             or (committee is null and ((category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[])))
                                        or (id in (select s.id from public._my_concern_case_ids() s(id))))))
    )
    or (exists (select 1 from public.dispatches d where d.report_id = reports.id and d.tanod_id = (select auth.uid())))
  ));

-- ---------- the tables hanging off a case: one set per query ----------
alter policy case_handler_log_read on public.case_handler_log using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy case_forwards_read on public.case_forwards using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))
  or (((select public.admin_tier()) = 'committee') and (from_committee = (select u.committee from public.users u where u.id = (select auth.uid())))));

alter policy detail_requests_read on public.detail_requests using (
  (exists (select 1 from public.reports r where r.id = detail_requests.report_id and r.resident_id = (select auth.uid())))
  or (exists (select 1 from public.dispatches d where d.report_id = detail_requests.report_id and d.tanod_id = (select auth.uid())))
  or ((select public.is_full_viewer()) or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))));

alter policy dispatch_media_read on public.dispatch_media using (
  exists (select 1 from public.dispatches d join public.reports r on r.id = d.report_id
           where d.id = dispatch_media.dispatch_id
             and ((d.tanod_id = (select auth.uid()))
                  or ((select public.is_full_viewer()) or ((select public.admin_scoped()) and (d.report_id in (select s.id from public._my_scoped_case_ids() s(id)))))
                  or ((r.resident_id = (select auth.uid())) and (r.deleted_at is null) and (dispatch_media.update_id is null)))));

alter policy dispatch_updates_read on public.dispatch_updates using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (dispatch_id in (select s.id from public._my_scoped_dispatch_ids() s(id))))
  or (exists (select 1 from public.dispatches d where d.id = dispatch_updates.dispatch_id and d.tanod_id = (select auth.uid()))));

alter policy dispatches_read on public.dispatches using (
  (tanod_id = (select auth.uid()))
  or ((select public.is_full_viewer()) or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))));

alter policy escalation_requests_read on public.escalation_requests using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))
  or (requested_by = (select auth.uid())));

alter policy feedback_read on public.feedback using (
  (resident_id = (select auth.uid()))
  or ((select public.is_full_viewer()) or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))));

alter policy look_shares_admin_read on public.look_shares using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

-- the CASE keeps "is it my notice" first: the planner may reorder the two halves of an AND, and the case set must not be built for other people's rows
alter policy notifications_read on public.notifications using (
  (user_id = (select auth.uid()))
  and (case when user_id = (select auth.uid()) and report_id is not null and (select public.admin_scoped())
            then report_id in (select s.id from public._my_scoped_case_ids() s(id))
            else true end));

alter policy report_concerns_admin_read on public.report_concerns using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy report_evidence_read on public.report_evidence using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))
  or (exists (select 1 from public.reports r where r.id = report_evidence.report_id and r.resident_id = (select auth.uid()))));

alter policy report_media_read on public.report_media using (
  exists (select 1 from public.reports r
           where r.id = report_media.report_id
             and ((r.resident_id = (select auth.uid()))
                  or ((select public.is_full_viewer()) or ((select public.admin_scoped()) and (report_media.report_id in (select s.id from public._my_scoped_case_ids() s(id)))))
                  or (exists (select 1 from public.dispatches d where d.report_id = r.id and d.tanod_id = (select auth.uid()))))));

alter policy report_messages_read on public.report_messages using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))
  or (exists (select 1 from public.reports r where r.id = report_messages.report_id and r.resident_id = (select auth.uid()) and r.deleted_at is null)));

alter policy report_triage_admin_read on public.report_triage using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy resolution_checks_admin_read on public.resolution_checks using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy sla_extensions_read on public.sla_extensions using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy smart_events_admin_read on public.smart_events using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy smart_overrides_admin_read on public.smart_overrides using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id)))));

alter policy status_logs_read on public.status_logs using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (report_id in (select s.id from public._my_scoped_case_ids() s(id))))
  or (exists (select 1 from public.reports r where r.id = status_logs.report_id and r.resident_id = (select auth.uid())))
  or (exists (select 1 from public.dispatches d where d.report_id = status_logs.report_id and d.tanod_id = (select auth.uid()))));

-- ---------- users: a resident only through a case the administrator sees ----------
alter policy users_self_read on public.users using (
  (id = (select auth.uid()))
  or (select public.is_full_viewer())
  or ((select public.admin_scoped()) and ((role = any (array['admin'::public.user_role, 'tanod'::public.user_role]))
                                          or (id in (select s.id from public._my_scoped_resident_ids() s(id))))));
