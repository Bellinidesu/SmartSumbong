-- =============================================================
-- SmartSumbong — 0139 The reroute queue cannot log without end
--
-- Ace (22 Oct 2026): "the auto reroute and the reroute queue system, so
-- it won't log infinitely". What the live data showed:
--   - Two test reports logged "No tanod available for automatic
--     dispatch" 13,349 and 9,555 times (27 Aug to 14 Sep): the waiting
--     line retried every two minutes. 0064 stopped it (a repeat of the
--     newest line is not written again); nothing repeated in the last
--     seven days.
--   - Since auto_dispatch was rewritten (0047 on) a reroute that finds
--     no one no longer joins the waiting line at all, so nothing retries
--     it: not a loop, but a case left to sit.
--   - The give-up line and its notice to every administrator were not
--     deduplicated: if the line were ever restored, each cycle would
--     write both again.
-- This restores the line, with limits:
--   - a reroute that finds no one waits in line; a first filing does not
--     (every first dispatch is the admin's, 0070);
--   - the line retries at most 24 hours, and not past the cap on offers
--     (operational_settings.max_dispatch_attempts), then lets go;
--   - past the cap auto_dispatch does nothing and logs nothing;
--   - "gave up" and its notice are written once, when the cap is passed;
--   - an administrator's reroute back to the system starts a fresh run;
--   - one more guard under all of it (below): a system line identical to
--     one written on the same report in the last ten minutes is not
--     written again, whoever tries.
-- =============================================================

set search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.auto_dispatch(p_report uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $$
declare
  v_report     public.reports%rowtype;
  v_tanod      uuid;
  v_tanod_name text;
  v_metres     double precision;
  v_dispatch   uuid;
  v_system     uuid;
  v_last       text;
  v_smart      boolean;
  v_pick       record;
begin
  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  -- 0139: past the cap the case is the barangay's: no further automatic offers, and nothing logged.
  if v_report.dispatch_attempts > (select max_dispatch_attempts from public.operational_settings where id = 1) then
    return null;
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

  -- 0128: the same tanods as before (nearest_available_tanod decides who
  -- can take it); SMART only decides the order, by distance, jobs in hand,
  -- cases closed nearby and location age, when smart_rules.smart_routing
  -- is on. Off: the nearest, as before.
  select coalesce((select smart_routing from public.smart_rules where id = 1), false) into v_smart;
  if v_smart then
    select t.tanod_id, t.full_name, t.metres, t.score, t.active_jobs, t.closed_nearby into v_pick
      from public._smart_tanod_ranking(p_report) t limit 1;
    v_tanod := v_pick.tanod_id; v_tanod_name := v_pick.full_name; v_metres := v_pick.metres;
  else
    select t.tanod_id, t.full_name, t.metres into v_tanod, v_tanod_name, v_metres
      from public.nearest_available_tanod(p_report) t limit 1;
  end if;

  if v_tanod is null then
    -- 0139: a reroute that found no one waits in line (sweep_awaiting_units retries it, within its limits). A
    -- first filing does not: every first dispatch is the admin's (0070).
    if v_report.dispatch_attempts > 0 and v_report.awaiting_unit_since is null then
      update public.reports set awaiting_unit_since = now() where id = p_report;
    end if;
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
          case when v_smart then
                 format('Automatic dispatch — SMART pick: %s, %s job(s) in hand, %s case(s) closed nearby.',
                        coalesce(round(v_metres) || ' m from the incident', 'no location shared yet'),
                        v_pick.active_jobs, v_pick.closed_nearby)
               when v_metres is null
               then 'Automatic dispatch — on-duty unit; no location shared yet.'
               else format('Automatic dispatch — nearest available unit, %s m from the incident.',
                           round(v_metres)) end)
  returning id into v_dispatch;

  update public.reports set status = 'assigned', awaiting_unit_since = null where id = p_report;

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

CREATE OR REPLACE FUNCTION public.redispatch_report(p_report uuid, p_why text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $$
declare
  v_attempts smallint;
  v_max      smallint;
  v_next     uuid;
begin
  select max_dispatch_attempts into v_max from public.operational_settings where id = 1;

  update public.reports
     set dispatch_attempts = dispatch_attempts + 1,
         status = 'validated'
   where id = p_report
  returning dispatch_attempts into v_attempts;

  if v_attempts > v_max then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now()),
           awaiting_unit_since = null   -- 0139: the waiting line lets go
     where id = p_report;

    -- 0139: said once, when the cap is first passed; later calls only return
    if v_attempts > v_max + 1 then
      return null;
    end if;

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
         format('Re-dispatching: %s (offer %s of %s)', p_why, v_attempts, v_max), true
    from public.reports r where r.id = p_report;

  select public.auto_dispatch(p_report) into v_next;
  return v_next;
end $$;

CREATE OR REPLACE FUNCTION public.sweep_awaiting_units()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $$
declare
  r      record;
  v_hours smallint;
  v_max   smallint;
  v_smart boolean;
begin
  select awaiting_alert_hours, max_dispatch_attempts into v_hours, v_max from public.operational_settings where id = 1;

  -- 0139: the line is bounded. A case leaves it past the cap on offers, after a day, or once it is no longer
  -- waiting; from then on it is the barangay's (the waiting-hours notice below has gone out once by then).
  update public.reports
     set awaiting_unit_since = null
   where awaiting_unit_since is not null
     and (awaiting_unit_since < now() - interval '24 hours'
          or dispatch_attempts > v_max
          or deleted_at is not null
          or status not in ('pending_review', 'validated'));

  select coalesce((select smart_queue from public.smart_rules where id = 1), false) into v_smart;

  for r in
    select rp.id, rp.awaiting_unit_since
      from public.reports rp
      left join (select q.report_id, q.priority from public._smart_queue() q) q
        on v_smart and q.report_id = rp.id
     where rp.awaiting_unit_since is not null
       and rp.deleted_at is null
       and rp.status in ('pending_review', 'validated')
     order by q.priority desc nulls last, rp.awaiting_unit_since
  loop
    if r.awaiting_unit_since < now() - make_interval(hours => v_hours)
       and not exists (
         select 1 from public.notifications n
          where n.report_id = r.id and n.kind = 'escalation') then
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, r.id, 'escalation',
             format('A report has been waiting over %s hours with no tanod on duty in range.', v_hours)
        from public.users u where u.role = 'admin';
    end if;

    -- 0130: a sensitive case (VAWC and the like) is never sent to a tanod by the waiting line: a person decides
    if not exists (select 1 from public.reports s where s.id = r.id and s.is_sensitive) then
      perform public.auto_dispatch(r.id);
    end if;
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.admin_reroute_dispatch(p_dispatch uuid, p_reason text, p_to uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $$
declare
  v_d      public.dispatches%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_tick   text;
  v_next   uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reroute a dispatch';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to reroute a dispatch';
  end if;

  select * into v_d from public.dispatches
   where id = p_dispatch and state in ('assigned', 'accepted')
   for update;
  if not found then
    raise exception 'That dispatch is no longer active';
  end if;
  if p_to is not null and p_to = v_d.tanod_id then
    raise exception 'That tanod already has this dispatch';
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = 'By the barangay: ' || v_reason, rerouted_to = p_to
   where id = p_dispatch;

  select tracking_id into v_tick from public.reports where id = v_d.report_id;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_d.report_id, auth.uid(), 'assigned', 'assigned',
          'Rerouted by the barangay: ' || v_reason);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_d.tanod_id, v_d.report_id, 'reroute',
          format('The barangay moved %s to another tanod: %s', v_tick, v_reason));

  if p_to is not null then
    -- admin_dispatch checks the new tanod (on duty, not busy), sets the
    -- report to assigned, and notifies them and the resident. Any
    -- refusal there rolls this whole call back.
    v_next := public.admin_dispatch(v_d.report_id, p_to,
                                    'Rerouted by the barangay: ' || v_reason);
  else
    -- 0139: the barangay's own call gets a fresh run of offers
    update public.reports set dispatch_attempts = 0, awaiting_unit_since = null where id = v_d.report_id;
    v_next := public.redispatch_report(v_d.report_id,
                                       'rerouted by the barangay: ' || v_reason);
  end if;

  return v_next;
end $$;

-- ---------- one more guard, under every system line ---------------------------

create or replace function public._status_log_no_repeat()
returns trigger
language plpgsql
as $$
begin
  if new.is_system and exists (
       select 1 from public.status_logs s
        where s.report_id = new.report_id
          and s.is_system
          and s.remark is not distinct from new.remark
          and s.old_status is not distinct from new.old_status
          and s.new_status is not distinct from new.new_status
          and s.created_at > now() - interval '10 minutes') then
    return null;
  end if;
  return new;
end $$;

drop trigger if exists status_logs_no_repeat on public.status_logs;
create trigger status_logs_no_repeat before insert on public.status_logs
  for each row execute function public._status_log_no_repeat();

comment on function public._status_log_no_repeat() is
  '0139: a system line identical to one on the same report in the last ten minutes is not written again, so no sweep can log without end.';
