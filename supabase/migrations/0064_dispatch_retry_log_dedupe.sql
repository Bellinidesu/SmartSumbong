-- 0064: a dispatch retry that changes nothing no longer logs again.
--
-- sweep_awaiting_units (0007/0010) calls auto_dispatch every two minutes
-- for each report still waiting for a unit. When no tanod is in range,
-- auto_dispatch wrote "No tanod available for automatic dispatch —
-- awaiting manual assignment" to status_logs on every call: thirty rows
-- an hour, per waiting report. BRG-2026-0056 collected over a thousand,
-- enough that the resident's timeline (oldest-first) hit the API's row
-- cap before its own resolution. The out-of-jurisdiction branch repeats
-- the same way.
--
-- The body is 0047's; the only change is that each of those two system
-- rows is written only when the report's newest status_logs remark isn't
-- already that same line. The retries themselves, the escalation
-- notification and the dispatch path are unchanged, and a fresh "No
-- tanod available" is still logged after anything else happens (a
-- dispatch that expires, a reroute), so the trail still shows each new
-- wait. Rows already written stay — status_logs is append-only (0015).

set search_path = public, extensions;

create or replace function public.auto_dispatch(p_report uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report     public.reports%rowtype;
  v_tanod      uuid;
  v_tanod_name text;
  v_metres     double precision;
  v_dispatch   uuid;
  v_system     uuid;
  v_last       text;
begin
  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  -- NEW (0064): the newest remark on this report's trail, so a retry
  -- that changes nothing doesn't log the same line again.
  select remark into v_last
    from public.status_logs
   where report_id = p_report
   order by created_at desc
   limit 1;

  -- Out of jurisdiction: refer, do not dispatch.
  if not public.is_within_barangay(v_report.latitude, v_report.longitude) then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    if v_last is distinct from 'Outside Barangay 183 — referred to city services' then
      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'Outside Barangay 183 — referred to city services', true);
    end if;
    return null;
  end if;

  select t.tanod_id, t.full_name, t.metres into v_tanod, v_tanod_name, v_metres
    from public.nearest_available_tanod(p_report) t limit 1;

  if v_tanod is null then
    if v_last is distinct from
         'No tanod available for automatic dispatch — awaiting manual assignment' then
      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'No tanod available for automatic dispatch — awaiting manual assignment', true);
    end if;
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

  -- NEW (0047): names the tanod, same pattern admin_dispatch already
  -- uses ("Manually assigned to %s by admin ...") -- the resident's
  -- timeline now answers "who is coming", not just "how far".
  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          format('Auto-dispatched to %s (%s m away)', v_tanod_name, round(v_metres)), true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment',
          format('New dispatch: %s', v_report.subject));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;
