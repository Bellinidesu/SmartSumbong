-- =============================================================
-- SmartSumbong — 0175 The case hierarchy (19 Nov 2026, Rose)
--
-- Rose's feedback on who holds a case, in plain terms:
--   super admin   accepts a case, assigns it to a councilor or a staff member, takes over from councilors and staff, dispatches
--   councilor     (Kagawad) accepts, assigns to their own staff, takes over from their staff, escalates to the super admins, dispatches
--   staff         is assigned a case by their councilor (accepts it or declines it), escalates to the councilor, dispatches
--
-- 1. Assigning a case. reports.assigned_to is the person a case was given to and who has not answered yet. The one who assigns
--    holds the case (its handler) until the assignee accepts: accepting makes them the handler, declining (with a reason) leaves
--    it with whoever assigned it, who is told. Nothing new owns a case: it is the handler of 0087 and its log (assign, accept,
--    decline and unassign join take, release, take over, escalate and return), so every page that reads the handler agrees.
--    A super admin assigns to any councilor or staff member; giving it to someone of another committee places the case with that
--    committee (a forward in the case's history). A councilor assigns to the staff of their own committee. Staff never assign.
-- 2. What staff see. A staff member (the moderator tier) reads a case once it is assigned to them, while they handle it, and,
--    to read only, the cases they handled before; no longer every case of their committee. It is one rule (_user_sees_case), so
--    the case pages, the list, notifications, the chats, the engine's lists and every table row level security guards agree.
--    Staff never claim a case by acting on it, and they no longer see their fellow staff's punch cards or the reroute questions.
-- 3. Taking over. A super admin takes over from anyone; a councilor only from the staff of their own committee; staff never.
--    A case changes hands only through these functions: a direct write to its handler or its assignment is refused.
-- 4. Forwarding. The forward notice names the committee it went to, and a committee with no Kagawad account yet has the super
--    admins told instead, so a forward is never silent. A notice about a case the person no longer sees (it was forwarded away,
--    or the account moved committee: the development team's test Kagawad does) is no longer shown to them. That was why
--    Environment looked notified of a case forwarded to Health and Sanitation: the test Kagawad kept, after moving, the notice
--    of an earlier forward, and Health and Sanitation, which had no Kagawad then, was told nothing.
-- =============================================================

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'case_assigned';

-- ---------- 1. the assignment, on the case itself ----------
alter table public.reports
  add column if not exists assigned_to uuid references public.users (id),
  add column if not exists assigned_by uuid references public.users (id),
  add column if not exists assigned_at timestamptz,
  add column if not exists assign_note text;
alter table public.reports drop constraint if exists reports_assign_note_check;
alter table public.reports add constraint reports_assign_note_check check (assign_note is null or char_length(assign_note) <= 300);
-- the one who assigned it holds the case until the assignee answers
alter table public.reports drop constraint if exists reports_assignment_held;
alter table public.reports add constraint reports_assignment_held check (assigned_to is null or handler_id is not null);
create index if not exists reports_assigned_to_fk_idx on public.reports (assigned_to) where assigned_to is not null;
create index if not exists reports_assigned_by_fk_idx on public.reports (assigned_by) where assigned_by is not null;
comment on column public.reports.assigned_to is '0175: the councilor or staff member this case was assigned to, who has not accepted or declined yet. The handler (who assigned it) holds it meanwhile.';
comment on column public.reports.assigned_by is '0175: who assigned the case (its handler while the assignment waits).';
comment on column public.reports.assigned_at is '0175: when the case was assigned.';
comment on column public.reports.assign_note is '0175: the note the assignee reads with the assignment.';

alter table public.case_handler_log drop constraint if exists case_handler_log_action_check;
alter table public.case_handler_log add constraint case_handler_log_action_check
  check (action = any (array['take', 'release', 'take_over', 'escalate', 'return', 'assign', 'accept', 'decline', 'unassign']));
alter table public.case_handler_log add column if not exists to_id uuid references public.users (id);
create index if not exists case_handler_log_to_id_fk_idx on public.case_handler_log (to_id) where to_id is not null;
comment on column public.case_handler_log.to_id is '0175: for assign and unassign, the person the case was (or is no longer) assigned to.';

-- A case changes hands only through the functions (take, take over, assign, accept, escalate, forward ...), which say so with
-- smartsumbong.handler_change; the one change allowed without it is an administrator claiming a case nobody holds by acting on
-- it (_case_guard_report). The assignment moves only through assign_case and answer_case_assignment. Any change of hands ends
-- an assignment that is still waiting: the case is no longer with the one who gave it.
create or replace function public._guard_case_hands()
returns trigger language plpgsql set search_path = public as $$
declare v_uid uuid := auth.uid(); v_fn boolean := coalesce(current_setting('smartsumbong.handler_change', true), '') = 'on';
begin
  if v_uid is not null and not v_fn and new.handler_id is distinct from old.handler_id
     and not (old.handler_id is null and new.handler_id = v_uid) then
    raise exception 'A case changes hands only by taking it, assigning it, taking it over or escalating it' using errcode = 'insufficient_privilege';
  end if;
  if (new.assigned_to is distinct from old.assigned_to or new.assigned_by is distinct from old.assigned_by
      or new.assigned_at is distinct from old.assigned_at or new.assign_note is distinct from old.assign_note)
     and v_uid is not null and coalesce(current_setting('smartsumbong.assignment', true), '') <> 'on' then
    raise exception 'A case is assigned only with Assign, and accepted or declined by the one it was assigned to' using errcode = 'insufficient_privilege';
  end if;
  if old.assigned_to is not null and coalesce(current_setting('smartsumbong.assignment', true), '') <> 'on'
     and (new.handler_id is distinct from old.handler_id or new.committee is distinct from old.committee
          or new.awaiting_placement is distinct from old.awaiting_placement or new.referred_to is not null
          or new.deleted_at is not null or new.status in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')) then
    new.assigned_to := null; new.assigned_by := null; new.assigned_at := null; new.assign_note := null;
  end if;
  return new;
end $$;
revoke all on function public._guard_case_hands() from public, anon, authenticated;
drop trigger if exists reports_hands_guard on public.reports;
create trigger reports_hands_guard before update on public.reports for each row execute function public._guard_case_hands();

-- ---------- 2. what staff see: one rule for every page ----------
/**
 * Does this person see this case? (0145, 0151, 0152; 0175 for staff.) A staff member (moderator) sees a case assigned to them,
 * one they handle, and, to read, one they handled before; a Kagawad their committee's cases (the one a case was forwarded to,
 * else its category's) and any they handle; a case waiting for the super admins to place is no committee's.
 */
create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    -- 19 Nov 2026 (Rose): staff see a complaint only once their councilor (or a super admin) has assigned it to them
    when r.tier = 'moderator' then
         (p_handler is not null and p_handler = p_user)
      or (r.assigned_to is not null and r.assigned_to = p_user)
      or exists (select 1 from public.case_handler_log l
                  where l.report_id = p_report and l.admin_id = p_user and l.action in ('take', 'take_over', 'accept'))
    when r.awaiting_placement then false
    when r.committee is not null then
         coalesce((select u.committee = r.committee and u.role = 'admin' and not coalesce(u.is_suspended, false) from public.users u where u.id = p_user), false)
      or (p_handler is not null and p_handler = p_user)
    else coalesce(public._user_sees_category(p_user, p_cat), false)
      or (p_handler is not null and p_handler = p_user)
      or exists (select 1 from public.report_concerns rc where rc.report_id = p_report and public._user_sees_category(p_user, rc.category))
  end
    from (select x.committee, coalesce(x.awaiting_placement, false) as awaiting_placement, x.assigned_to,
                 (select u.admin_tier from public.users u where u.id = p_user and u.role = 'admin' and not coalesce(u.is_suspended, false)) as tier
            from (select 1) one left join public.reports x on x.id = p_report) r
$$;
revoke all on function public._user_sees_case(uuid, uuid, public.complaint_category, uuid) from public, anon, authenticated;

-- a refusal that says why, to staff: the case is not theirs yet, rather than "outside your committee"
create or replace function public._scope_guard(p_report uuid, p_write boolean)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin() then return; end if;
  if public.is_super_admin() then return; end if;
  if p_write and not public.admin_can_write() then
    raise exception 'This account can look at cases but not change them.' using errcode = 'insufficient_privilege';
  end if;
  if p_report is not null and not public.admin_sees_report(p_report) then
    if public.admin_tier() = 'moderator' then
      raise exception 'This case has not been assigned to you. Your Kagawad assigns cases to staff.' using errcode = 'insufficient_privilege';
    end if;
    raise exception 'This case is outside your committee.' using errcode = 'insufficient_privilege';
  end if;
end $$;
revoke all on function public._scope_guard(uuid, boolean) from public, anon, authenticated;

-- Staff never take a case by acting on it; an assignee accepts first. (The rest is 0087 as it stands.)
create or replace function public._case_guard(p_report uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_h   uuid;
  v_to  uuid;
  v_name text;
begin
  perform public._scope_guard(p_report, true);
  if p_report is null or v_uid is null or not public.is_admin() then
    return;
  end if;
  if current_setting('smartsumbong.handler_change', true) = 'on' then
    return;
  end if;
  select handler_id, assigned_to into v_h, v_to from public.reports where id = p_report;
  if v_to = v_uid and v_h is distinct from v_uid then
    raise exception 'This case was assigned to you: accept it first.' using errcode = 'insufficient_privilege';
  end if;
  if v_h is null then
    if public.admin_tier() = 'moderator' then
      raise exception 'Staff work a case once their Kagawad assigns it to them and they accept it.' using errcode = 'insufficient_privilege';
    end if;
    perform set_config('smartsumbong.handler_change', 'on', true);
    update public.reports set handler_id = v_uid, handled_since = now()
     where id = p_report and handler_id is null;
    insert into public.case_handler_log (report_id, admin_id, action) values (p_report, v_uid, 'take');
    perform set_config('smartsumbong.handler_change', 'off', true);
  elsif v_h <> v_uid then
    select public.display_name(full_name) into v_name from public.users where id = v_h;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
end $$;
revoke all on function public._case_guard(uuid) from public, anon, authenticated;

create or replace function public._case_guard_report()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
begin
  new.version := coalesce(old.version, 0) + 1;
  if v_uid is null or current_setting('smartsumbong.handler_change', true) = 'on' or not public.is_admin() then
    return new;
  end if;
  if old.assigned_to = v_uid and old.handler_id is distinct from v_uid
     and coalesce(current_setting('smartsumbong.assignment', true), '') <> 'on' then
    raise exception 'This case was assigned to you: accept it first.' using errcode = 'insufficient_privilege';
  end if;
  if old.handler_id is null then
    if public.admin_tier() = 'moderator' then
      raise exception 'Staff work a case once their Kagawad assigns it to them and they accept it.' using errcode = 'insufficient_privilege';
    end if;
    new.handler_id := v_uid;
    new.handled_since := now();
    insert into public.case_handler_log (report_id, admin_id, action) values (new.id, v_uid, 'take');
  elsif old.handler_id <> v_uid then
    select public.display_name(full_name) into v_name from public.users where id = old.handler_id;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
  return new;
end $$;

-- staff no longer read their fellow staff's punch cards (Rose: they do not need to watch them); a Kagawad still reads their staff's
create or replace function public._sees_punch_card(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
      or coalesce(public.is_full_viewer(), false)
      or (public.admin_tier() = 'committee' and exists (
            select 1 from public.users t, public.users me
             where t.id = p_user and me.id = auth.uid() and t.role = 'admin' and me.committee is not null and t.committee = me.committee
               and t.admin_tier = 'moderator'))
$$;
revoke all on function public._sees_punch_card(uuid) from public, anon;
grant execute on function public._sees_punch_card(uuid) to authenticated;

-- a reroute question asks the Kagawad, not their staff; a forward out of a committee is the Kagawad's to read, not every staff member's
alter policy reroute_questions_read on public.reroute_questions using (
  (select public.is_full_viewer())
  or ((select public.admin_tier()) = 'committee' and committee = (select u.committee from public.users u where u.id = (select auth.uid()))));
alter policy case_forwards_read on public.case_forwards using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and public.admin_sees_report(report_id))
  or ((select public.admin_tier()) = 'committee' and from_committee = (select u.committee from public.users u where u.id = (select auth.uid()))));

-- A Kagawad's or staff member's notice about a case is shown while the case is theirs to see: forwarded away, or after the account
-- moved committee, it stops showing (and counting) for them. Residents, tanods and the super admins read theirs as before.
alter policy notifications_read on public.notifications using (
  user_id = (select auth.uid())
  and (report_id is null or not (select public.admin_scoped()) or public.admin_sees_report(report_id)));

-- the queue (Notifications > Next up): the cases the person may open, by the same rule as everything else (staff: their own)
create or replace function public.smart_queue(p_stage text default null, p_limit integer default 50)
returns table (report_id uuid, tracking_id text, subject text, category public.complaint_category, stage text, next_action text,
               waiting_since timestamptz, level text, priority integer, reasons jsonb)
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
declare v_tier text := public.admin_tier();
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the queue.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_queue() q
                where (p_stage is null or q.stage = p_stage)
                  and case when v_tier = 'moderator' then public.admin_sees_report(q.report_id) else public.admin_sees_category(q.category) end
                limit greatest(1, least(coalesce(p_limit, 50), 500));
end $$;

-- ---------- 3. taking a case, and taking it over ----------
create or replace function public.take_case(p_report uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_h uuid; v_name text;
begin
  if public.admin_tier() = 'moderator' then
    raise exception 'Staff are assigned cases by their Kagawad; they do not take them.' using errcode = 'insufficient_privilege';
  end if;
  perform public._scope_guard(p_report, true);
  if not public.admin_can_write() then raise exception 'Only an administrator may take a case'; end if;
  select handler_id into v_h from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h = auth.uid() then return; end if;
  if v_h is not null then
    select public.display_name(full_name) into v_name from public.users where id = v_h;
    raise exception '% is already handling this case. Use Take over.', coalesce(v_name, 'Another administrator');
  end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = auth.uid(), handled_since = now() where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action) values (p_report, auth.uid(), 'take');
end $$;

/**
 * Who may take a case over from its handler (19 Nov 2026, Rose): a super admin from anyone; a Kagawad only from the staff of
 * their own committee; staff never. The case page shows Take over by the same rule (case.php).
 */
create or replace function public._may_take_over(p_me uuid, p_handler uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_handler is null or p_handler = p_me then true
    else coalesce((
      select case coalesce(me.admin_tier, 'super')
               when 'super' then true
               when 'committee' then coalesce(h.admin_tier, 'super') = 'moderator' and h.committee is not null and h.committee = me.committee
               else false end
        from public.users me, public.users h
       where me.id = p_me and h.id = p_handler and me.role = 'admin'), false)
  end
$$;
revoke all on function public._may_take_over(uuid, uuid) from public, anon, authenticated;

create or replace function public.take_over_case(p_report uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_h      uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_me     text;
  v_track  text;
begin
  if public.admin_tier() = 'moderator' then
    raise exception 'Staff cannot take over a case. Ask your Kagawad.' using errcode = 'insufficient_privilege';
  end if;
  perform public._scope_guard(p_report, true);
  if not public.admin_can_write() then raise exception 'Only an administrator may take over a case'; end if;
  if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Give a reason for taking over (the current handler sees it)';
  end if;
  select handler_id, tracking_id into v_h, v_track from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h = auth.uid() then return; end if;
  if not public._may_take_over(auth.uid(), v_h) then
    raise exception 'A Kagawad takes over only from the staff of their own committee. Ask a super admin.' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = auth.uid(), handled_since = now() where id = p_report;   -- a waiting assignment ends (_guard_case_hands)
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
  values (p_report, auth.uid(), case when v_h is null then 'take' else 'take_over' end, v_h, v_reason);
  if v_h is not null then
    select public.display_name(full_name) into v_me from public.users where id = auth.uid();
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_h, p_report, 'status_change', coalesce(v_me, 'Another administrator') || ' took over ' || v_track || ' from you: ' || v_reason);
  end if;
end $$;

-- ---------- 4. assigning, accepting, declining ----------
/**
 * Who this administrator may assign a case to: a super admin, the councilors and staff of every committee (the case's own committee
 * first); a Kagawad, the staff of their committee. Never themselves or the case's handler; test accounts only to the development team.
 */
create or replace function public.case_assignees(p_report uuid)
returns table (id uuid, full_name text, tier text, committee text, official_role text, in_committee boolean, is_test boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  v_tier text := public.admin_tier();
  me public.users%rowtype;
  v_com text;
  v_h uuid;
begin
  if v_tier is null or v_tier not in ('super', 'committee') then return; end if;
  if not public.admin_sees_report(p_report) then return; end if;
  select * into me from public.users where users.id = auth.uid();
  v_com := public._case_committee(p_report);
  select r.handler_id into v_h from public.reports r where r.id = p_report;
  return query
    select u.id, u.full_name, coalesce(u.admin_tier, 'super'), u.committee, u.official_role,
           (v_com is not null and u.committee is not distinct from v_com), coalesce(u.is_test, false)
      from public.users u
     where u.role = 'admin' and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
       and u.id <> me.id and u.id is distinct from v_h
       and (not coalesce(u.is_test, false) or coalesce(me.is_dev, false) or coalesce(me.is_test, false))
       and case when v_tier = 'super' then u.admin_tier in ('committee', 'moderator') and u.committee is not null
                else u.admin_tier = 'moderator' and u.committee = me.committee end
     order by (v_com is not null and u.committee is not distinct from v_com) desc, u.committee,
              case u.admin_tier when 'committee' then 0 else 1 end, u.full_name;
end $$;
revoke all on function public.case_assignees(uuid) from public, anon;
grant execute on function public.case_assignees(uuid) to authenticated;

/**
 * Assign a case (19 Nov 2026, Rose). A super admin to a councilor or a staff member, a Kagawad to a staff member of their committee.
 * The one assigning must hold the case or nobody may: they hold it until the assignee accepts. p_to null withdraws a waiting
 * assignment. The assignee is told; giving it to someone of another committee places the case there (written as a forward).
 */
create or replace function public.assign_case(p_report uuid, p_to uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
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
end $$;
revoke all on function public.assign_case(uuid, uuid, text) from public, anon;
grant execute on function public.assign_case(uuid, uuid, text) to authenticated;

/** The assignee answers: accept (they hold the case from now) or decline with a reason (it stays with whoever assigned it, who is told). */
create or replace function public.answer_case_assignment(p_report uuid, p_accept boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me uuid := auth.uid();
  r public.reports%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_by text;
begin
  if public.admin_tier() is null or not public.admin_can_write() then
    raise exception 'Only an administrator answers an assignment' using errcode = 'insufficient_privilege';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such case' using errcode = 'check_violation'; end if;
  if r.assigned_to is distinct from v_me then
    raise exception 'This case is not waiting for you to accept it.' using errcode = 'check_violation';
  end if;
  select public.display_name(full_name) into v_by from public.users where id = v_me;
  if coalesce(p_accept, false) then
    perform set_config('smartsumbong.handler_change', 'on', true);
    perform set_config('smartsumbong.assignment', 'on', true);
    update public.reports set handler_id = v_me, handled_since = now(),
           assigned_to = null, assigned_by = null, assigned_at = null, assign_note = null
     where id = p_report;
    perform set_config('smartsumbong.assignment', 'off', true);
    perform set_config('smartsumbong.handler_change', 'off', true);
    insert into public.case_handler_log (report_id, admin_id, action, previous_id) values (p_report, v_me, 'accept', r.handler_id);
    if r.assigned_by is not null and r.assigned_by <> v_me then
      insert into public.notifications (user_id, report_id, kind, message)
      values (r.assigned_by, p_report, 'status_change', left(format('%s accepted case %s and is handling it now.', coalesce(v_by, 'The staff member'), r.tracking_id), 500));
    end if;
  else
    if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300 then
      raise exception 'Say why you are declining it (3 to 300 characters); whoever assigned it reads it.' using errcode = 'check_violation';
    end if;
    perform set_config('smartsumbong.handler_change', 'on', true);
    perform set_config('smartsumbong.assignment', 'on', true);
    update public.reports set assigned_to = null, assigned_by = null, assigned_at = null, assign_note = null where id = p_report;
    perform set_config('smartsumbong.assignment', 'off', true);
    perform set_config('smartsumbong.handler_change', 'off', true);
    insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason) values (p_report, v_me, 'decline', r.assigned_by, v_reason);
    if r.assigned_by is not null then
      insert into public.notifications (user_id, report_id, kind, message)
      values (r.assigned_by, p_report, 'status_change', left(format('%s declined case %s; it is back with you: %s', coalesce(v_by, 'The staff member'), r.tracking_id, v_reason), 500));
    end if;
  end if;
  perform public._smart_event(case when coalesce(p_accept, false) then 'assign_accept' else 'assign_decline' end, p_report,
          format('%s %s by %s', r.tracking_id, case when coalesce(p_accept, false) then 'accepted' else 'declined' end, coalesce(v_by, 'the assignee')),
          jsonb_build_object('by', v_me, 'reason', v_reason));
end $$;
revoke all on function public.answer_case_assignment(uuid, boolean, text) from public, anon;
grant execute on function public.answer_case_assignment(uuid, boolean, text) to authenticated;

-- ---------- 5. forwarding tells the committee it went to, by name; nobody there, the super admins ----------
create or replace function public._notify_committee_heads(p_committee text, p_report uuid, p_kind text, p_message text)
returns void language plpgsql security definer set search_path = public as $$
declare v_subject text := case p_kind when 'case_forwarded' then 'A case was forwarded' when 'forward_flag' then 'Staff flagged a case for forwarding' else 'About a case' end;
  v_none boolean;
begin
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, p_report, p_kind::public.notification_kind, left(p_message, 500)
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_committee is null then coalesce(u.admin_tier, 'super') = 'super'
              else u.admin_tier = 'committee' and u.committee = p_committee end;
  insert into public.inbox_messages (recipient, kind, subject, body, report_id)
  select u.id, 'system', v_subject, left(p_message, 4000), p_report
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_committee is null then coalesce(u.admin_tier, 'super') = 'super'
              else u.admin_tier = 'committee' and u.committee = p_committee end;
  -- 19 Nov 2026 (Rose): a case forwarded to a committee with no Kagawad account (a test account aside) is not left unseen
  if p_kind = 'case_forwarded' and p_committee is not null then
    select not exists (select 1 from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = p_committee
                          and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false) and not coalesce(u.is_test, false))
      into v_none;
    if v_none then
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, p_report, 'case_forwarded', left(p_message || ' ' || public._committee_label(p_committee) || ' has no Kagawad account yet, so the super admins are told.', 500)
        from public.users u
       where u.role = 'admin' and coalesce(u.admin_tier, 'super') = 'super' and not coalesce(u.is_suspended, false)
         and not coalesce(u.is_test, false) and u.id is distinct from auth.uid();
    end if;
  end if;
end $$;
revoke all on function public._notify_committee_heads(text, uuid, text, text) from public, anon;
grant execute on function public._notify_committee_heads(text, uuid, text, text) to authenticated;

-- the forward notice names the committee (a notice still reads right after the person moves committee); the rest is 0152 as it stands
do $$
declare d text; o text := 'format(''Case %s was forwarded to %s by %s%s'', r.tracking_id, case when p_to is null then ''the super admins to place'' else ''your committee'' end,';
  n text := 'format(''Case %s was forwarded to %s by %s%s'', r.tracking_id, case when p_to is null then ''the super admins to place'' else public._committee_label(p_to) end,';
begin
  d := replace(pg_get_functiondef('public.forward_case(uuid, text, text, bigint)'::regprocedure), E'\r', '');
  if position(o in d) = 0 then raise exception '0175: forward_case does not word its notice as expected'; end if;
  execute replace(d, o, n);
end $$;

-- ---------- 6. the staff module: its lists name only the cases they may open, and what waits for them to accept ----------
do $$
declare d text;
  o1 text := E'''mine'',           (select count(*) from open_cases where handler_id = v_me)),';
  n1 text := E'''mine'',           (select count(*) from open_cases where handler_id = v_me),\n      ''to_accept'',      (select count(*) from public.reports r where r.assigned_to = v_me and r.deleted_at is null)),';
  o2 text := 'p.last_at, p.tracking_ids[1:3] as tracking_ids';
  n2 text := 'p.last_at, case when v_tier = ''moderator'' then array(select r.tracking_id from public.reports r where r.tracking_id = any (p.tracking_ids[1:3]) and public._user_sees_case(v_me, r.id, r.category, r.handler_id)) else p.tracking_ids[1:3] end as tracking_ids';
begin
  d := replace(pg_get_functiondef('public.smart_module()'::regprocedure), E'\r', '');
  if position(o1 in d) = 0 or position(o2 in d) = 0 then raise exception '0175: smart_module is not as expected'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $$;

comment on column public.users.admin_tier is
  '0145/0151/0175: super (everything), committee (a Kagawad: their committee), moderator (staff: the cases assigned to them, without taking or taking over), captain (sees all, changes nothing). Null reads as super.';
