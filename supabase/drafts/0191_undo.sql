-- UNDO of 0191_case_rule_consistency: the definitions as they were after 0190 (word for word); no data changes. Tested: applying this after 0191 restores every function body and the policy text.
set search_path = public, extensions;
set local lock_timeout = '5s';

create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat complaint_category, p_handler uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public._my_committee()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.committee from public.users u
   where u.id = auth.uid() and public.admin_tier() = 'committee'
$function$;

create or replace function public._my_concern_case_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 200
 SET search_path TO 'public'
AS $function$
  select distinct rc.report_id
    from public.report_concerns rc
    join public.reports r on r.id = rc.report_id
   where rc.category = any (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.category <> all (coalesce((select public._my_categories()), '{}'::public.complaint_category[]))
     and r.committee is null and not coalesce(r.awaiting_placement, false)
$function$;

create or replace function public._my_handled_case_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 100
 SET search_path TO 'public'
AS $function$
  select l.report_id from public.case_handler_log l
   where l.admin_id = (select auth.uid()) and l.action in ('take', 'take_over', 'accept')
     and (select public.admin_tier()) = 'moderator'
$function$;

create or replace function public._my_scoped_case_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

alter policy reports_resident_read on public.reports using (((deleted_at IS NULL) AND ((resident_id = ( SELECT auth.uid() AS uid)) OR ( SELECT is_full_viewer() AS is_full_viewer) OR ((( SELECT admin_tier() AS admin_tier) = 'moderator'::text) AND ((handler_id = ( SELECT auth.uid() AS uid)) OR (assigned_to = ( SELECT auth.uid() AS uid)) OR (id IN ( SELECT s.id
   FROM _my_handled_case_ids() s(id))))) OR ((( SELECT admin_tier() AS admin_tier) = 'committee'::text) AND (NOT COALESCE(awaiting_placement, false)) AND ((handler_id = ( SELECT auth.uid() AS uid)) OR (committee = ( SELECT _my_committee() AS _my_committee)) OR ((committee IS NULL) AND ((category = ANY (COALESCE(( SELECT _my_categories() AS _my_categories), '{}'::complaint_category[]))) OR (id IN ( SELECT s.id
   FROM _my_concern_case_ids() s(id))))))) OR (EXISTS ( SELECT 1
   FROM dispatches d
  WHERE ((d.report_id = reports.id) AND (d.tanod_id = ( SELECT auth.uid() AS uid))))))));

create or replace function public._notifications_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text; v_tier text;
begin
  begin
    -- what would make the INSERT itself fail (foreign keys, NOT NULLs) is repaired or the notice dropped, so a press never aborts on a notice
    if new.user_id is null or not exists (select 1 from public.users where id = new.user_id) then return null; end if;       -- the person is gone
    if new.report_id is not null and not exists (select 1 from public.reports where id = new.report_id) then return null; end if;   -- the case is gone
    if new.subject_user_id is not null and not exists (select 1 from public.users where id = new.subject_user_id) then new.subject_user_id := null; end if;
    new.message := coalesce(nullif(new.message, ''), '(no text)');
    -- the scope rule (unchanged from 0175/0185)
    select role::text, coalesce(admin_tier, 'super') into v_role, v_tier from public.users where id = new.user_id;
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
