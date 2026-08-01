-- =============================================================
-- SmartSumbong — 0007 Waiting for a unit is not a failed attempt
--
-- 0006 counted every unsuccessful auto_dispatch the same way. That is
-- wrong in the case that actually happens most: a report filed at 2am
-- when no tanod has gone on duty yet. There is nobody to decline it,
-- so nothing was attempted — but the counter still climbed, and three
-- sweeps later (fifteen minutes) the report had permanently given up
-- on automatic routing. A tanod coming on duty at 02:30 would never
-- have been offered it.
--
-- Declining and waiting are now separate:
--   * dispatch_attempts  — offers actually made to a tanod and refused
--   * awaiting_unit_since — no candidate existed; keep watching
--
-- Manual assignment by an admin remains available throughout. It is
-- the intended path when the barangay knows who to send.
-- =============================================================

set search_path = public, extensions;

alter table public.reports
  add column awaiting_unit_since timestamptz;

comment on column public.reports.awaiting_unit_since is
  'Set when automatic dispatch found no available tanod. Cleared once a dispatch is created. Not a failure — the sweep keeps retrying while this is set.';

create index reports_awaiting_idx on public.reports (awaiting_unit_since)
  where awaiting_unit_since is not null;

-- ---------- auto_dispatch distinguishes the two cases ---------

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
    -- Nobody to offer it to. Mark the report as waiting and log once,
    -- rather than repeating the same line every sweep.
    if v_report.awaiting_unit_since is null then
      update public.reports set awaiting_unit_since = now() where id = p_report;

      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'No tanod on duty within range — waiting for an available unit', true);
    end if;
    return null;
  end if;

  select id into v_system from public.users where role = 'admin' order by created_at limit 1;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, v_tanod, coalesce(v_system, v_tanod),
          format('Automatic dispatch — nearest available unit, %s m from the incident.',
                 round(v_metres)))
  returning id into v_dispatch;

  update public.reports
     set status = 'assigned', awaiting_unit_since = null
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          format('Auto-dispatched to nearest unit (%s m)', round(v_metres)), true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment', format('New dispatch: %s', v_report.subject));

  return v_dispatch;
end $$;

-- ---------- only count offers that were actually made ---------

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

  -- Three refusals is enough to say automatic routing is not solving
  -- this one. Waiting for a unit does not reach here at all.
  if v_attempts > 3 then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    select p_report, r.resident_id, 'validated', 'validated',
           format('Automatic dispatch gave up after %s offers (%s) — manual assignment required',
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
         format('Re-dispatching: %s (offer %s)', p_why, v_attempts), true
    from public.reports r where r.id = p_report;

  select public.auto_dispatch(p_report) into v_next;
  return v_next;
end $$;

-- ---------- the waiting sweep --------------------------------
-- This is what makes a tanod coming on duty at 02:30 pick up the 02:00
-- report. Without it, a report that found nobody would sit forever.

create or replace function public.sweep_awaiting_units()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  for r in
    select id, awaiting_unit_since
      from public.reports
     where awaiting_unit_since is not null
       and deleted_at is null
       and status in ('pending_review', 'validated')
     order by awaiting_unit_since
  loop
    -- Waiting is not indefinite. Past the SLA for the report itself the
    -- existing escalation sweep takes over, but four hours with nobody
    -- on duty is a staffing fact an admin should be told about once.
    if r.awaiting_unit_since < now() - interval '4 hours'
       and not exists (
         select 1 from public.notifications n
          where n.report_id = r.id and n.kind = 'escalation') then
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, r.id, 'escalation',
             'A report has been waiting over four hours with no tanod on duty in range.'
        from public.users u where u.role = 'admin';
    end if;

    perform public.auto_dispatch(r.id);
  end loop;
end $$;

revoke execute on function public.sweep_awaiting_units() from public, anon, authenticated;

select cron.schedule('sweep-awaiting-units', '*/2 * * * *',
                     $$select public.sweep_awaiting_units()$$);
