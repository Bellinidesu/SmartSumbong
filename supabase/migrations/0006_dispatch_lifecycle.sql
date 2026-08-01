-- =============================================================
-- SmartSumbong — 0006 Closing the dispatch lifecycle
--
-- 0005 could start a dispatch but nothing finished one. Two dead ends
-- existed:
--
--   * sweep_unaccepted_dispatches marked a dispatch 'expired' and told
--     an admin, but left the report at status 'assigned' with no live
--     dispatch. To the resident it looked handled; nobody was coming.
--   * reroute_dispatch with no named target dropped the report back to
--     'validated' and stopped there.
--
-- It also had a loop: nearest_available_tanod only excluded tanods
-- holding a LIVE dispatch, so whoever had just timed out was the
-- nearest candidate again a moment later.
-- =============================================================

set search_path = public, extensions;

-- ---------- attempt tracking ---------------------------------
-- A report that cannot find a taker must stop trying and land on a
-- human, rather than cycling through the roster indefinitely.

alter table public.reports
  add column dispatch_attempts smallint not null default 0;

-- ---------- candidate selection ------------------------------
-- Now excludes anyone who has ALREADY held a dispatch for this report
-- in any state. A tanod who timed out or rerouted has effectively
-- declined it; offering it back to them is the loop.

create or replace function public.nearest_available_tanod(p_report uuid)
returns table (tanod_id uuid, full_name text, metres double precision)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom) as metres
    from public.reports r
    cross join lateral (
      select u.* from public.users u
       where u.is_dispatchable
         and u.last_geom is not null
         and public.location_is_fresh(u.last_location_at)
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.state in ('assigned', 'accepted'))
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.report_id = p_report)
    ) u
   where r.id = p_report
   order by st_distance(u.last_geom, r.geom)
$$;

-- ---------- re-dispatch --------------------------------------
-- Called when a dispatch dies without resolving: acceptance window
-- passed, or the tanod rerouted it back to the queue.

create or replace function public.redispatch_report(p_report uuid, p_why text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_attempts smallint;
  v_next     uuid;
begin
  update public.reports
     set dispatch_attempts = dispatch_attempts + 1,
         status = 'validated'
   where id = p_report
  returning dispatch_attempts into v_attempts;

  -- Three tries is enough to establish that automatic routing is not
  -- going to solve this one. Hand it to an admin rather than churn.
  if v_attempts > 3 then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    select p_report, r.resident_id, 'validated', 'validated',
           format('Automatic dispatch gave up after %s attempts (%s) — manual assignment required',
                  v_attempts, p_why), true
      from public.reports r where r.id = p_report;

    insert into public.notifications (user_id, report_id, kind, message)
    select id, p_report, 'escalation',
           'A report could not be dispatched automatically and needs manual assignment.'
      from public.users where role = 'admin';
    return null;
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  select p_report, r.resident_id, 'assigned', 'validated',
         format('Re-dispatching: %s (attempt %s)', p_why, v_attempts), true
    from public.reports r where r.id = p_report;

  select public.auto_dispatch(p_report) into v_next;
  return v_next;
end $$;

-- ---------- sweep now re-dispatches --------------------------

create or replace function public.sweep_unaccepted_dispatches()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  for r in
    update public.dispatches
       set state = 'expired'
     where state = 'assigned' and accept_due_at < now()
    returning id, report_id, tanod_id
  loop
    insert into public.notifications (user_id, report_id, kind, message)
    select u.id, r.report_id, 'sla_warning',
           'A tanod did not respond to a dispatch within the acceptance window.'
      from public.users u where u.role = 'admin';

    -- The report does not stay parked on a dispatch nobody accepted.
    perform public.redispatch_report(r.report_id, 'acceptance window elapsed');
  end loop;
end $$;

-- ---------- reroute to queue now re-dispatches ---------------

create or replace function public.reroute_dispatch(
  p_dispatch uuid, p_reason text, p_to uuid default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_report uuid;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A justification is required to reroute a dispatch';
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
    -- Named hand-off stays a deliberate act between two tanods.
    insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
    values (v_report, p_to, auth.uid(), 'Rerouted from a previous tanod.');

    insert into public.notifications (user_id, report_id, kind, message)
    values (p_to, v_report, 'reroute', 'A dispatch was rerouted to you.');
  else
    -- Back to the queue means back through proximity selection.
    perform public.redispatch_report(v_report, 'rerouted to queue: ' || p_reason);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select id, v_report, 'reroute', 'A dispatch was rerouted.'
    from public.users where role = 'admin';
end $$;

revoke execute on function public.redispatch_report(uuid, text) from public, anon, authenticated;
revoke execute on function public.sweep_unaccepted_dispatches() from public, anon, authenticated;
