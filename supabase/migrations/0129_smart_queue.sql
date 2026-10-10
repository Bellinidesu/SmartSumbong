-- 0129: the SMART queue (10 Oct 2026).
--
-- Every open case in one order, by what it needs and how badly, with the
-- reasons (docs/SMART.md, section 21). Until now the dispatch waiting line
-- was first come, first served (a fire filed after a clearance request
-- waited behind it for the next free tanod), and the case list was sorted
-- by date only.
--
-- Priority = urgency (the SMART score, or the admin's level)
--          + time waiting in the case's current stage (1 point an hour,
--            40 at most, so a low case never waits forever but a fresh
--            urgent one still comes first)
--          + 20 past its deadline, + 15 likely to miss it, + 10 quiet.
--
-- Each case is at one stage, its next action: decide an escalation
-- request, approve a resolution, review, assign a tanod, wait for the
-- tanod to accept, reply to the resident, or follow up.
--
-- The dispatch waiting line (sweep_awaiting_units) now takes the waiting
-- reports in this order. smart_rules.smart_queue switches it back to
-- first come, first served.

set search_path = public, extensions;

alter table public.smart_rules
  add column smart_queue          boolean  not null default true,
  add column queue_aging_minutes  smallint not null default 60 check (queue_aging_minutes between 5 and 1440),
  add column queue_aging_cap      smallint not null default 40 check (queue_aging_cap between 0 and 100),
  add column queue_overdue_points smallint not null default 20 check (queue_overdue_points between 0 and 100),
  add column queue_risk_points    smallint not null default 15 check (queue_risk_points between 0 and 100),
  add column queue_quiet_points   smallint not null default 10 check (queue_quiet_points between 0 and 100);

/** The queue: every open case, its stage and next action, since when it
    has waited at that stage, and its priority with the reasons. */
create or replace function public._smart_queue()
returns table (report_id uuid, tracking_id text, subject text, category public.complaint_category,
               stage text, next_action text, waiting_since timestamptz, level text,
               priority integer, reasons jsonb)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select * from public.smart_rules where id = 1),
  risky as (select dr.report_id from public._smart_deadline_risk() dr where dr.risk = 'high'),
  open_cases as (
    select r.* from public.reports r
     where r.deleted_at is null
       and r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
  ),
  facts as materialized (
    select o.id, o.tracking_id, o.subject, o.category, o.status, o.due_at, o.created_at,
           o.resolution_submitted_at, o.awaiting_unit_since, o.updated_at,
           (select min(e.created_at) from public.escalation_requests e where e.report_id = o.id and e.status = 'pending') as esc_at,
           (select min(d.assigned_at) from public.dispatches d where d.report_id = o.id and d.state = 'assigned') as unaccepted_at,
           exists (select 1 from public.dispatches d where d.report_id = o.id and d.state in ('assigned', 'accepted')) as live,
           (select m.created_at from public.report_messages m where m.report_id = o.id
             order by m.created_at desc limit 1) as last_msg_at,
           (select not m.from_barangay from public.report_messages m where m.report_id = o.id
             order by m.created_at desc limit 1) as last_msg_resident,
           (select l.created_at from public.status_logs l where l.report_id = o.id and l.new_status = o.status
             order by l.created_at desc limit 1) as status_at
      from open_cases o
  ),
  staged as (
    select f.*,
      case when f.esc_at is not null then 'escalation'
           when f.resolution_submitted_at is not null then 'approve'
           when f.status = 'pending_review' then 'review'
           when f.status = 'validated' and not f.live then 'dispatch'
           when f.unaccepted_at is not null then 'accept'
           when coalesce(f.last_msg_resident, false) then 'reply'
           else 'follow_up' end as stage
      from facts f
  ),
  timed as (
    select s.*,
      case s.stage
        when 'escalation' then s.esc_at
        when 'approve'    then s.resolution_submitted_at
        when 'review'     then s.created_at
        when 'dispatch'   then coalesce(s.awaiting_unit_since, s.status_at, s.created_at)
        when 'accept'     then s.unaccepted_at
        when 'reply'      then s.last_msg_at
        else greatest(s.status_at, s.last_msg_at, s.created_at) end as since
      from staged s
  ),
  scored as (
    select t.*,
           tr.effective_level,
           case when tr.override_level is not null
                then (array[10, 35, 55, 80])[array_position(array['low', 'normal', 'high', 'urgent'], tr.override_level)]
                else coalesce(tr.score, 0) end as base,
           least(k.queue_aging_cap, floor(extract(epoch from now() - t.since) / 60 / k.queue_aging_minutes))::integer as aging,
           (t.due_at is not null and t.due_at < now()) as overdue,
           (rk.report_id is not null) as at_risk,
           (t.stage = 'follow_up' and t.since < now() - make_interval(days => k.stuck_days)) as quiet,
           k.queue_overdue_points as p_over, k.queue_risk_points as p_risk, k.queue_quiet_points as p_quiet
      from timed t
      cross join k
      left join public.report_triage tr on tr.report_id = t.id
      left join risky rk on rk.report_id = t.id
  )
  select s.id, s.tracking_id, s.subject, s.category, s.stage,
         case s.stage
           when 'escalation' then 'Decide the escalation request'
           when 'approve'    then 'Approve or return the tanod''s resolution'
           when 'review'     then 'Review the complaint'
           when 'dispatch'   then 'Assign a tanod'
           when 'accept'     then 'Waiting for the tanod to accept'
           when 'reply'      then 'Reply to the resident'
           else 'Follow up' end,
         s.since, coalesce(s.effective_level, 'unscored'),
         (s.base + s.aging + case when s.overdue then s.p_over else 0 end
                 + case when s.at_risk then s.p_risk else 0 end
                 + case when s.quiet then s.p_quiet else 0 end)::integer,
         jsonb_build_array(
           jsonb_build_object('factor', 'urgency', 'points', s.base,
             'detail', coalesce(initcap(s.effective_level), 'Not scored')),
           jsonb_build_object('factor', 'waiting', 'points', s.aging,
             'detail', format('%s h at this stage', floor(extract(epoch from now() - s.since) / 3600)::integer)))
         || case when s.overdue then jsonb_build_array(jsonb_build_object('factor', 'overdue', 'points', s.p_over,
                    'detail', 'past its deadline')) else '[]'::jsonb end
         || case when s.at_risk then jsonb_build_array(jsonb_build_object('factor', 'deadline risk', 'points', s.p_risk,
                    'detail', 'likely to miss its deadline')) else '[]'::jsonb end
         || case when s.quiet then jsonb_build_array(jsonb_build_object('factor', 'quiet', 'points', s.p_quiet,
                    'detail', 'no update for days')) else '[]'::jsonb end
    from scored s
   order by 9 desc, s.since
$$;

revoke all on function public._smart_queue() from public, anon, authenticated;

/** Admins: the SMART queue, optionally one stage, top p_limit. */
create or replace function public.smart_queue(p_stage text default null, p_limit integer default 50)
returns table (report_id uuid, tracking_id text, subject text, category public.complaint_category,
               stage text, next_action text, waiting_since timestamptz, level text,
               priority integer, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the queue.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_queue() q
                where p_stage is null or q.stage = p_stage
                limit greatest(1, least(coalesce(p_limit, 50), 500));
end $$;

revoke all on function public.smart_queue(text, integer) from public, anon;
grant execute on function public.smart_queue(text, integer) to authenticated;

-- ---------- the dispatch waiting line, in queue order ----------------------------------------


create or replace function public.sweep_awaiting_units()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_hours smallint;
  v_smart boolean;
begin
  select awaiting_alert_hours into v_hours from public.operational_settings where id = 1;

  -- 0129: when a tanod frees up, the waiting report that needs them most
  -- goes first (SMART queue priority: urgency plus time waited, so nothing
  -- waits forever), not simply the one that has waited longest.
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

    perform public.auto_dispatch(r.id);
  end loop;
end $$;

-- ---------- no JIT (see 0127) ----------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and (p.proname in ('_smart_queue', 'smart_queue', 'sweep_awaiting_units'))
  loop
    execute format('alter function %s set jit = off', f);
  end loop;
end $$;
