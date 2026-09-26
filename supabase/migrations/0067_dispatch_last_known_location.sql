-- 0067 — dispatch on the last known location (branch B, 26 Sep 2026).
--
-- The tanod app no longer streams a location every 30 seconds for a whole
-- shift: that foreground service ate the phone's battery. It now sends
-- one fix at the moments that matter — going On Duty, returning to the
-- app while on duty, and each dispatch step (accept, reroute, field
-- report).
--
-- nearest_available_tanod() (0005, 0006) only considered a tanod whose
-- fix was younger than operational_settings.location_freshness_minutes.
-- On occasional fixes most on-duty tanods would be "stale", and
-- automatic dispatch would fall through to "no tanod available" with
-- tanods standing by. So freshness now ranks instead of filtering: a
-- fresh fix wins, then the nearest last known position, then an on-duty
-- tanod who has never sent one — nobody on duty is skipped for want of
-- a recent fix. Everything else (dispatchable, not holding another
-- incident, not already tried on this report) is unchanged.

create or replace function public.nearest_available_tanod(p_report uuid)
returns table (tanod_id uuid, full_name text, metres double precision)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom) as metres
    from public.reports r
    cross join lateral (
      select u.* from public.users u
       where u.is_dispatchable
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.state in ('assigned', 'accepted'))
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.report_id = p_report)
    ) u
   where r.id = p_report
   order by public.location_is_fresh(u.last_location_at) desc,
            st_distance(u.last_geom, r.geom) nulls last,
            u.last_location_at desc nulls last
$$;

revoke execute on function public.nearest_available_tanod(uuid) from public, anon;
grant  execute on function public.nearest_available_tanod(uuid) to authenticated;

comment on function public.nearest_available_tanod(uuid) is
  'Tanods who can take this report, best first: a fresh location, then the '
  'nearest last known one, then on-duty tanods with none yet (0067).';

-- auto_dispatch() as in 0064, with one change: its two notes quote the
-- distance, and a tanod chosen with no location yet has none — the notes
-- now say so instead of printing "( m away)".
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
          case when v_metres is null
               then 'Automatic dispatch — on-duty unit; no location shared yet.'
               else format('Automatic dispatch — nearest available unit, %s m from the incident.',
                           round(v_metres)) end)
  returning id into v_dispatch;

  update public.reports set status = 'assigned' where id = p_report;

  -- NEW (0047): names the tanod, same pattern admin_dispatch already
  -- uses ("Manually assigned to %s by admin ...") -- the resident's
  -- timeline now answers "who is coming", not just "how far".
  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          case when v_metres is null
               then format('Auto-dispatched to %s', v_tanod_name)
               else format('Auto-dispatched to %s (%s m away)', v_tanod_name, round(v_metres)) end, true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment',
          format('New dispatch: %s', v_report.subject));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;

