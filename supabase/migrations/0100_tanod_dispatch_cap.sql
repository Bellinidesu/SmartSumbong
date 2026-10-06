-- 0100 — A tanod can hold up to 5 dispatches at once (Rose, 7 Oct 2026).
--
-- Until now a tanod with one active dispatch could not be given another.
-- The cap is a setting (operational_settings.max_active_dispatches, 5), and
-- every place that decided "busy" now compares against it: manual dispatch,
-- reroute to a named tanod, automatic dispatch, the assignable list and the
-- roster the portal shows. Generated from the live definitions; only the
-- busy rule changes.

alter table public.operational_settings
  add column if not exists max_active_dispatches int not null default 5
  check (max_active_dispatches between 1 and 20);

create or replace function public.tanod_dispatch_cap()
returns int language sql stable set search_path = public as $$
  select coalesce((select max_active_dispatches from public.operational_settings limit 1), 5)
$$;
grant execute on function public.tanod_dispatch_cap() to authenticated;

CREATE OR REPLACE FUNCTION public.admin_dispatch(p_report uuid, p_tanod uuid, p_instructions text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_report   public.reports%rowtype;
  v_tanod    public.users%rowtype;
  v_busy     text;
  v_dispatch uuid;
  v_metres   double precision;
  v_note     text := nullif(trim(coalesce(p_instructions, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may assign a dispatch manually';
  end if;

  select * into v_report from public.reports where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;

  -- Set, not necessarily future: a reroute of an overdue complaint comes
  -- through here too. The assign form itself only takes a future date.
  if v_report.due_at is null then
    raise exception 'Set a target resolution date before dispatching';
  end if;

  if v_note is null then
    raise exception 'Write instructions for the tanod before dispatching';
  end if;

  select * into v_tanod from public.users where id = p_tanod;
  if not found or v_tanod.role <> 'tanod' then
    raise exception 'That account is not a tanod';
  end if;

  if not v_tanod.is_dispatchable then
    raise exception '% is not available for dispatch (duty status: %)',
      v_tanod.full_name, coalesce(v_tanod.duty_status::text, 'not set');
  end if;

  select case when count(*) >= public.tanod_dispatch_cap() then max(r.subject) end into v_busy
    from public.dispatches d
    join public.reports r on r.id = d.report_id
   where d.tanod_id = p_tanod and d.state in ('assigned', 'accepted');

  if v_busy is not null then
    raise exception
      '% already has the most dispatches a tanod can hold at once. Choose another available tanod.',
      v_tanod.full_name;
  end if;

  select st_distance(v_tanod.last_geom, v_report.geom) into v_metres;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, p_tanod, auth.uid(), v_note)
  returning id into v_dispatch;

  update public.reports
     set status = 'assigned', awaiting_unit_since = null
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'assigned',
          case when v_metres is null
            then format('Manually assigned to %s by admin', v_tanod.full_name)
            else format('Manually assigned to %s by admin (%s m from the incident)',
                        v_tanod.full_name, round(v_metres))
          end);

  insert into public.notifications (user_id, report_id, kind, message)
  values (p_tanod, p_report, 'assignment',
          format('Assigned by the barangay admin: %s', v_report.subject));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $function$;

CREATE OR REPLACE FUNCTION public.reroute_dispatch(p_dispatch uuid, p_reason text, p_to uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_report   uuid;
  v_busy     text;
  v_resident uuid;
  v_tracking text;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A justification is required to reroute a dispatch';
  end if;

  -- Check the target before touching anything, so a refused hand-off
  -- leaves the original dispatch untouched rather than half-moved.
  if p_to is not null then
    select case when count(*) >= public.tanod_dispatch_cap() then max(r.subject) end into v_busy
      from public.dispatches d
      join public.reports r on r.id = d.report_id
     where d.tanod_id = p_to and d.state in ('assigned', 'accepted');

    if v_busy is not null then
      raise exception
        'That tanod already has the most dispatches a tanod can hold at once. Reroute to the queue instead.';
    end if;

    if not exists (select 1 from public.users
                    where id = p_to and is_dispatchable) then
      raise exception 'That tanod is not on duty and available';
    end if;
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = p_reason, rerouted_to = p_to
   where id = p_dispatch
     and tanod_id = auth.uid()
     and state in ('assigned', 'accepted')
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or already actioned';
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_report, auth.uid(), 'assigned', 'assigned', 'Rerouted: ' || p_reason);

  if p_to is not null then
    insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
    values (v_report, p_to, auth.uid(), 'Rerouted from a previous tanod.');

    insert into public.notifications (user_id, report_id, kind, message)
    values (p_to, v_report, 'reroute', 'A dispatch was rerouted to you.');

    -- NEW: a direct hand-off is a fresh dispatch for the resident too.
    select resident_id, tracking_id into v_resident, v_tracking
      from public.reports where id = v_report;

    insert into public.notifications (user_id, report_id, kind, message)
    values (v_resident, v_report, 'assignment',
            format('A tanod has been dispatched to your report %s.', v_tracking));
  else
    -- Back to the queue means back through proximity selection.
    -- redispatch_report -> auto_dispatch already notifies the resident
    -- once (and if) a new tanod is actually found, so nothing is added
    -- here â€” an intermediate "being rerouted" ping to the resident
    -- would be noise, not signal.
    perform public.redispatch_report(v_report, 'rerouted to queue: ' || p_reason);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select id, v_report, 'reroute', 'A dispatch was rerouted.'
    from public.users where role = 'admin';
end $function$;

CREATE OR REPLACE FUNCTION public.assignable_tanods(p_report uuid)
 RETURNS TABLE(tanod_id uuid, full_name text, metres double precision, location_fresh boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom),
         public.location_is_fresh(u.last_location_at)
    from public.reports r
    cross join public.users u
   where r.id = p_report
     and u.is_dispatchable
     and (select count(*) from public.dispatches d
           where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) < public.tanod_dispatch_cap()
   order by st_distance(u.last_geom, r.geom) nulls last, u.full_name
$function$;

CREATE OR REPLACE FUNCTION public.nearest_available_tanod(p_report uuid)
 RETURNS TABLE(tanod_id uuid, full_name text, metres double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom) as metres
    from public.reports r
    cross join lateral (
      select u.* from public.users u
       where u.is_dispatchable
         and (select count(*) from public.dispatches d
               where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) < public.tanod_dispatch_cap()
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.report_id = p_report)
    ) u
   where r.id = p_report
   order by public.location_is_fresh(u.last_location_at) desc,
            st_distance(u.last_geom, r.geom) nulls last,
            u.last_location_at desc nulls last
$function$;

CREATE OR REPLACE FUNCTION public.tanod_roster(p_report uuid)
 RETURNS TABLE(tanod_id uuid, full_name text, duty_status duty_state, assignable boolean, unavailable_why text, metres double precision, location_fresh boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select u.id,
         u.full_name,
         u.duty_status,
         u.is_dispatchable and coalesce(b.n, 0) < public.tanod_dispatch_cap(),
         case
           when coalesce(b.n, 0) >= public.tanod_dispatch_cap() then 'Has ' || b.n || ' dispatches (the most at once)'
           when u.is_suspended                then 'Suspended'
           when u.verification_status <> 'verified' then 'Not yet verified'
           when coalesce(u.duty_status, 'offline') <> 'on_duty'
             then initcap(replace(coalesce(u.duty_status, 'offline')::text, '_', ' '))
           else null
         end,
         st_distance(u.last_geom, r.geom),
         public.location_is_fresh(u.last_location_at)
    from public.users u
    cross join public.reports r
    left join lateral (
      select count(*)::int as n from public.dispatches d
       where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) b on true
   where r.id = p_report
     and u.role = 'tanod'
   order by (u.is_dispatchable and coalesce(b.n, 0) < public.tanod_dispatch_cap()) desc,
            coalesce(b.n, 0),
            st_distance(u.last_geom, r.geom) nulls last,
            u.full_name
$function$;
