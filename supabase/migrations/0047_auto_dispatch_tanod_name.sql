-- =============================================================
-- SmartSumbong — 0047 Name the tanod in the auto-dispatch remark
--
-- User request, off a live screenshot of the resident timeline: the
-- "Auto-dispatched to nearest unit (16423 m)" row on a resident's own
-- report reads like a system log line, not something answering "who is
-- coming?" — the one piece of information a resident actually wants at
-- that step. admin_dispatch (0009) already does this right --
-- "Manually assigned to %s by admin (%s m from the incident)" -- only
-- auto_dispatch (0005, last redefined in 0034) never picked up the
-- pattern, even though nearest_available_tanod (0006) already returns
-- full_name alongside tanod_id and metres; auto_dispatch just never
-- selected it.
--
-- WHY THIS NEEDS NO RLS CHANGE, NO NEW TABLE ACCESS, NO QUERY CHANGE IN
-- THE APP. status_logs.remark is already resident-readable for their
-- own report (0001's status_logs_read policy) -- the resident client
-- already fetches and renders `remark` as-is (report_view_screen.dart's
-- `_TimelineRow`, reports_screen.dart's `_MiniTimelineRow`). The gap was
-- never access, it was that the stored *text* never said who. Widening
-- an RLS policy or a new SECURITY DEFINER lookup so the resident client
-- could join dispatches -> users and read the tanod's name directly was
-- the other way to solve this, and was considered and rejected: it
-- would let a resident's own client read another user's row (even if
-- scoped to just full_name), a real new surface, for a problem this
-- migration solves without touching access at all. Baking the name into
-- the remark at write time, the same way admin_dispatch already does,
-- keeps the "resident reads their own status_logs" policy exactly as
-- narrow as it always was.
--
-- Reproduced from 0034 (the last version), CREATE OR REPLACE only, safe
-- to re-run. The other two dispatch-creating functions are untouched:
-- admin_dispatch already names the tanod; reroute_dispatch's p_to
-- hand-off branch writes its "Rerouted: <reason>" status_logs row
-- before a fresh dispatch exists to name, and is not extended here --
-- flagged as a deliberate scope decision, not a miss, since a resident
-- reroute-notification already exists via the same function
-- (0034's "A tanod has been dispatched to your report" ping) and this
-- migration is scoped to the one example actually reported.
-- =============================================================

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

  select t.tanod_id, t.full_name, t.metres into v_tanod, v_tanod_name, v_metres
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
