-- DRAFT: not applied until Ace says apply 0191
-- 0191_case_rule_consistency: the case rule: deleted cases, retired admins, switched-off committees, awaiting placement (four intended changes)
--
-- Ace, 21 Nov 2026: the recommendation on the four old behaviours of the case rule, one migration. Everything else about who sees what is unchanged.
--   (1) DELETED CASES: rows hanging off a soft-deleted case (all the tables 0189's set covers) become invisible to Kagawad and staff; super admins and captain keep them (audit).
--   (2) RETIRED: a retired admin sees nothing as an administrator in the rule (_user_sees_case and the set helpers); _notifications_scope drops CASE notices addressed to
--       retired admins (a notice with no case, such as their own retirement, still arrives: the retiring person must be told).
--   (3) COMMITTEE ON: the committee branch needs the viewer's committee switched on (committees.active), in the function and in _my_committee(); forward_case already refuses
--       a switched-off committee; assign_case did not (a super admin giving a case to staff of another committee places it there): it now refuses too.
--       Consequence to know: switching a committee off hides its existing cases from its own Kagawad (super admins still see them); live has 0 cases in the 7 switched-off committees.
--   (4) AWAITING PLACEMENT: the case's own handler keeps seeing it while it waits for placement (staff assigned to it already did); other Kagawads still do not.
-- The per-case function (guards, notices, the queue, smart_module) and the 0189 set helpers / reports policy are kept in lockstep: tools/sweep/equiv_0191.py proves that the only
-- differences against 0190, per person and per table, are the four intended sets (and nothing else).
--
-- UNDO (plain language): supabase/drafts/0191_undo.sql restores _user_sees_case, the four helpers, reports_resident_read, _notifications_scope and assign_case word for word (tested); no data changes.
-- Proof: supabase/drafts/tests/0191_case_rule_consistency.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_case_rule_consistency.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

set search_path = public, extensions;
set local lock_timeout = '5s';

create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid)
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
$function$;

-- the caller's committee (Kagawad only), when that committee is switched on
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
$$;

alter policy reports_resident_read on public.reports using (
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
  ));

create or replace function public._notifications_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text; v_tier text; v_ret boolean;
begin
  begin
    -- what would make the INSERT itself fail (foreign keys, NOT NULLs) is repaired or the notice dropped, so a press never aborts on a notice
    if new.user_id is null or not exists (select 1 from public.users where id = new.user_id) then return null; end if;       -- the person is gone
    if new.report_id is not null and not exists (select 1 from public.reports where id = new.report_id) then return null; end if;   -- the case is gone
    if new.subject_user_id is not null and not exists (select 1 from public.users where id = new.subject_user_id) then new.subject_user_id := null; end if;
    new.message := coalesce(nullif(new.message, ''), '(no text)');
    -- the scope rule (unchanged from 0175/0185)
    select role::text, coalesce(admin_tier, 'super'), coalesce(is_retired, false) into v_role, v_tier, v_ret from public.users where id = new.user_id;
    -- 0191 (2): a retired admin is told nothing about a case (a notice with no case, e.g. their own retirement, still arrives)
    if v_role = 'admin' and v_ret and new.report_id is not null then return null; end if;
    if v_role <> 'admin' or v_tier not in ('committee', 'moderator') then return new; end if;
    if new.report_id is null then
      if new.subject_user_id is null
         and (new.message like 'System check:%' or new.message like 'The admin portal %' or new.message like 'SMART:%') then
        return null;
      end if;
      return new;
    end if;
    if not coalesce((select public._user_sees_case(new.user_id, r.id, r.category, r.handler_id) from public.reports r where r.id = new.report_id), false) then
      return null;
    end if;
    return new;
  exception when others then
    -- fail closed (a notice that cannot be scoped is not sent) and leave a trace an administrator can read (0187's event log, itself best-effort)
    begin
      perform public._smart_event('notice_error', null, 'Notification not delivered: ' || sqlerrm, jsonb_build_object('user', new.user_id, 'case', new.report_id, 'kind', new.kind));
    exception when others then null;
    end;
    return null;
  end;
end $function$;

create or replace function public.assign_case(p_report uuid, p_to uuid, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_tier text := public.admin_tier();
  v_me   uuid := auth.uid();
  me public.users%rowtype;
  a  public.users%rowtype;
  r  public.reports%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_by text; v_com text; v_who text;
begin
  if v_tier is null then raise exception 'Only an administrator assigns a case' using errcode = 'insufficient_privilege'; end if;
  if v_tier = 'moderator' then raise exception 'Staff are assigned cases by their Kagawad; they do not assign them.' using errcode = 'insufficient_privilege'; end if;
  if v_tier = 'captain' then raise exception 'This account can look at cases but not change them.' using errcode = 'insufficient_privilege'; end if;
  perform public._scope_guard(p_report, true);
  if v_note is not null and char_length(v_note) > 300 then raise exception 'Keep the note to 300 characters' using errcode = 'check_violation'; end if;
  select * into r from public.reports where reports.id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such case' using errcode = 'check_violation'; end if;
  if r.status in ('resolved', 'closed', 'archived', 'rejected', 'cancelled') or r.referred_to is not null then
    raise exception 'Only an open case that is still with the barangay can be assigned' using errcode = 'check_violation';
  end if;
  if r.handler_id is not null and r.handler_id <> v_me then
    raise exception '% is handling this case. Take it over first to assign it.',
      coalesce((select public.display_name(full_name) from public.users where users.id = r.handler_id), 'Another administrator');
  end if;
  select * into me from public.users where users.id = v_me;
  select public.display_name(me.full_name) into v_by;

  if p_to is null then   -- withdraw the waiting assignment
    if r.assigned_to is null then return; end if;
    perform set_config('smartsumbong.handler_change', 'on', true);
    perform set_config('smartsumbong.assignment', 'on', true);
    update public.reports set assigned_to = null, assigned_by = null, assigned_at = null, assign_note = null where reports.id = p_report;
    perform set_config('smartsumbong.assignment', 'off', true);
    perform set_config('smartsumbong.handler_change', 'off', true);
    insert into public.case_handler_log (report_id, admin_id, action, to_id, reason) values (p_report, v_me, 'unassign', r.assigned_to, v_note);
    -- without the case's link: it is no longer theirs to open
    insert into public.notifications (user_id, kind, message)
    values (r.assigned_to, 'status_change', left(format('%s took back case %s; it is no longer waiting for you%s', coalesce(v_by, 'An administrator'),
            r.tracking_id, coalesce(': ' || v_note, '.')), 500));
    return;
  end if;

  select * into a from public.users where users.id = p_to;
  if not found or a.role <> 'admin' or coalesce(a.is_suspended, false) or coalesce(a.is_retired, false) then
    raise exception 'Choose an active councilor or staff member' using errcode = 'check_violation';
  end if;
  if a.id = v_me then raise exception 'The case is already with you' using errcode = 'check_violation'; end if;
  if coalesce(a.is_test, false) and not (coalesce(me.is_dev, false) or coalesce(me.is_test, false)) then
    raise exception 'That is a development team test account' using errcode = 'check_violation';
  end if;
  if v_tier = 'super' and (a.admin_tier not in ('committee', 'moderator') or a.committee is null) then
    raise exception 'A super admin assigns a case to a councilor or a staff member' using errcode = 'check_violation';
  end if;
  if v_tier = 'committee' and (a.admin_tier <> 'moderator' or a.committee is distinct from me.committee) then
    raise exception 'A Kagawad assigns a case to the staff of their own committee' using errcode = 'insufficient_privilege';
  end if;
  if r.assigned_to = p_to then return; end if;

  -- given to someone of another committee (a super admin's choice), the case is placed with that committee, as a forward
  v_com := public._case_committee(p_report);
  if v_tier = 'super' and a.committee is distinct from v_com then
    -- 0191 (3): forward_case already refuses a committee that is switched off; assigning to its staff places the case the same way, so it refuses too
    if not exists (select 1 from public.committees c where c.key = a.committee and c.active) then
      raise exception 'That committee is switched off; choose someone of an active committee' using errcode = 'check_violation';
    end if;
    perform set_config('smartsumbong.forwarding', 'on', true);
    update public.reports set committee = a.committee, awaiting_placement = false where reports.id = p_report;
    perform set_config('smartsumbong.forwarding', 'off', true);
    insert into public.case_forwards (report_id, kind, from_committee, to_committee, to_super, note, actor)
    values (p_report, 'forward', v_com, a.committee, false, left('Assigned to ' || public.display_name(a.full_name), 500), v_me);
  end if;

  perform set_config('smartsumbong.handler_change', 'on', true);
  perform set_config('smartsumbong.assignment', 'on', true);
  update public.reports
     set handler_id = v_me, handled_since = case when r.handler_id is null then now() else handled_since end,
         assigned_to = p_to, assigned_by = v_me, assigned_at = now(), assign_note = v_note
   where reports.id = p_report;
  perform set_config('smartsumbong.assignment', 'off', true);
  perform set_config('smartsumbong.handler_change', 'off', true);
  if r.handler_id is null then
    insert into public.case_handler_log (report_id, admin_id, action) values (p_report, v_me, 'take');
  end if;
  if r.assigned_to is not null then   -- it was waiting for someone else: they are told it moved on
    insert into public.notifications (user_id, kind, message)
    values (r.assigned_to, 'status_change', left(format('%s gave case %s to someone else; it is no longer waiting for you.', coalesce(v_by, 'An administrator'), r.tracking_id), 500));
  end if;
  insert into public.case_handler_log (report_id, admin_id, action, to_id, reason) values (p_report, v_me, 'assign', p_to, v_note);
  v_who := case a.admin_tier when 'committee' then 'Kagawad' else 'staff' end;
  insert into public.notifications (user_id, report_id, kind, message)
  values (p_to, p_report, 'case_assigned',
          left(format('%s assigned case %s to you%s Accept it, or decline it with a reason.', coalesce(v_by, 'An administrator'), r.tracking_id,
                      coalesce(': ' || v_note || '.', '.')), 500));
  perform public._smart_event('assign', p_report, format('%s assigned to %s (%s)', r.tracking_id, public.display_name(a.full_name), v_who),
          jsonb_build_object('to', p_to, 'tier', a.admin_tier, 'committee', a.committee));
end $function$;

-- UNDO SQL (not run; for the person applying this):
-- -- see supabase/drafts/0191_undo.sql
