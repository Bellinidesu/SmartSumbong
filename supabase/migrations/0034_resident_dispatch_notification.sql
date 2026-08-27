-- =============================================================
-- SmartSumbong — 0034 Resident notified on dispatch
--
-- A real gap found during Cowork QA, not from a submitted QA sheet: the
-- resident is never notified in-app when a tanod is actually dispatched
-- to their complaint. review_report (0011) tells them "accepted and now
-- with the barangay" at validation time, but nothing tells them "a tanod
-- is on the way" at the moment that becomes true. Every function that
-- creates a live dispatch row notifies the tanod (notifications.kind =
-- 'assignment') and stops there.
--
-- Three functions actually create a dispatch row for a report:
--   * auto_dispatch      (0005)  — proximity auto-routing at filing time
--   * admin_dispatch     (0009)  — admin manual assignment / reassignment
--   * reroute_dispatch   (0006, 0008) — the p_to branch, a direct
--     tanod-to-tanod hand-off, which is also a fresh dispatch
--
-- reroute_dispatch's p_to IS NULL branch (back to the queue) is NOT
-- touched here: it calls redispatch_report -> auto_dispatch, which
-- already notifies the resident once a new tanod is actually found. A
-- resident does not need "your case is being rerouted" as a separate
-- ping; they need "a tanod is coming," which fires exactly once a
-- dispatch row actually exists for them again.
--
-- No new notification_kind is introduced: 'assignment' already means
-- "a tanod has been tasked with this," and is reused for the resident's
-- own copy of that message. All three functions are recreated in full
-- with CREATE OR REPLACE, so this migration is safe to re-run.
--
-- Verified locally against a dependency-free scratch reproduction of
-- these tables/functions before being written here: auto_dispatch and
-- admin_dispatch each produce exactly one tanod + one resident
-- notification; reroute_dispatch's named hand-off produces one
-- reroute notification to the new tanod and one assignment notification
-- to the resident; reroute-to-queue produces neither by itself (the
-- resident ping happens later, when redispatch_report's call into
-- auto_dispatch actually lands a tanod).
-- =============================================================

set search_path = public, extensions;

-- ---------- auto_dispatch (0005) ------------------------------

create or replace function public.auto_dispatch(p_report uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    uuid;
  v_metres   double precision;
  v_dispatch uuid;
  v_system   uuid;
begin
  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  -- Out of jurisdiction: refer, do not dispatch.
  if not public.is_within_barangay(v_report.latitude, v_report.longitude) then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    values (p_report, v_report.resident_id, v_report.status, v_report.status,
            'Outside Barangay 183 — referred to city services', true);
    return null;
  end if;

  select t.tanod_id, t.metres into v_tanod, v_metres
    from public.nearest_available_tanod(p_report) t limit 1;

  if v_tanod is null then
    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    values (p_report, v_report.resident_id, v_report.status, v_report.status,
            'No tanod available for automatic dispatch — awaiting manual assignment', true);
    return null;
  end if;

  -- assigned_by records the system, using the report's own admin-less
  -- path: attributed to the nearest tanod's own id would be wrong, so
  -- the first admin on record stands as the dispatching authority.
  select id into v_system from public.users where role = 'admin' order by created_at limit 1;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, v_tanod, coalesce(v_system, v_tanod),
          format('Automatic dispatch — nearest available unit, %s m from the incident.',
                 round(v_metres)))
  returning id into v_dispatch;

  update public.reports set status = 'assigned' where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          format('Auto-dispatched to nearest unit (%s m)', round(v_metres)), true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment',
          format('New dispatch: %s', v_report.subject));

  -- NEW: the resident learns their complaint has actually been dispatched,
  -- not just accepted. This is the notification the app needs for
  -- "your complaint has been dispatched."
  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;

-- ---------- admin_dispatch (0009) ------------------------------

create or replace function public.admin_dispatch(
  p_report uuid, p_tanod uuid, p_instructions text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    public.users%rowtype;
  v_busy     text;
  v_dispatch uuid;
  v_metres   double precision;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may assign a dispatch manually';
  end if;

  select * into v_report from public.reports where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;

  select * into v_tanod from public.users where id = p_tanod;
  if not found or v_tanod.role <> 'tanod' then
    raise exception 'That account is not a tanod';
  end if;

  -- Available means on duty, verified and not suspended.
  if not v_tanod.is_dispatchable then
    raise exception '% is not available for dispatch (duty status: %)',
      v_tanod.full_name, coalesce(v_tanod.duty_status::text, 'not set');
  end if;

  select r.subject into v_busy
    from public.dispatches d
    join public.reports r on r.id = d.report_id
   where d.tanod_id = p_tanod and d.state in ('assigned', 'accepted')
   limit 1;

  if v_busy is not null then
    raise exception
      '% is already handling an active incident. Choose another available tanod.',
      v_tanod.full_name;
  end if;

  -- Distance is recorded for the trail, not used as a gate. The point
  -- of a manual assignment is that the admin has overruled proximity.
  select st_distance(v_tanod.last_geom, v_report.geom) into v_metres;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, p_tanod, auth.uid(),
          coalesce(nullif(trim(p_instructions), ''), 'Manually assigned by the barangay admin.'))
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

  -- NEW: matching auto_dispatch, the resident gets the same "a tanod has
  -- been dispatched" ping regardless of whether routing was automatic or
  -- an admin picked the unit by hand.
  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;

-- ---------- reroute_dispatch (0006, 0008) -----------------------
-- Reproduced from 0008, the last version that redefined it, plus the
-- one new resident notification in the named-hand-off branch.

create or replace function public.reroute_dispatch(
  p_dispatch uuid, p_reason text, p_to uuid default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
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
    select r.subject into v_busy
      from public.dispatches d
      join public.reports r on r.id = d.report_id
     where d.tanod_id = p_to and d.state in ('assigned', 'accepted')
     limit 1;

    if v_busy is not null then
      raise exception
        'That tanod is already handling an active incident. Reroute to the queue instead.';
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
    -- here — an intermediate "being rerouted" ping to the resident
    -- would be noise, not signal.
    perform public.redispatch_report(v_report, 'rerouted to queue: ' || p_reason);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select id, v_report, 'reroute', 'A dispatch was rerouted.'
    from public.users where role = 'admin';
end $$;
