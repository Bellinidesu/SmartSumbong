-- 0169: the engine's snapshot (7 Nov 2026, after the move to Singapore).
--
-- Measured on the live database, each on a fresh connection (cold) and again on the same one (warm):
--   smart_module()        530 ms cold, 13 ms warm     (the brain button's module, read by nearly every page)
--   _smart_patterns(null) 138 ms cold,  2 ms warm
--   the other analyses      5-7 ms cold
-- The parts add up to far less than the whole: most of the cold cost is planning one very large statement, with four
-- barangay-wide analyses folded into it. The API keeps a small pool of connections and lets idle ones go, so at a human pace
-- most pages met a cold one (the portal now keeps each person's answer for a minute, but the first page after a pause paid it).
--
-- The four analyses (deadline risk, quiet cases, spikes, recurring problems) are the same for everyone who may see them, so
-- they are now worked out once by a scheduled job and kept as ready lists in smart_snapshot; smart_module() and the public
-- engine functions read the lists and keep only the person's own part live (what they may see, their counts, their tanods).
--   - The job runs every minute and does the work only when something could have changed it: a report filed or changed, a
--     status change, a dispatch, or five minutes passed (deadline risk moves with the clock).
--   - A list older than ten minutes, or missing (a new database, a restore), is never used: the analysis runs live, as before.
--   - Hours left on a deadline are counted from now, not from when the list was made.
--   - A case that is resolved or closed drops out at once: the module still joins the lists to the person's open cases.
-- What each function returns is unchanged.

-- ---------- 1. the snapshot ----------
create table public.smart_snapshot (
  key  text primary key check (key in ('deadline_risk', 'stuck', 'spikes', 'patterns')),
  data jsonb not null,
  at   timestamptz not null default now()
);
alter table public.smart_snapshot enable row level security;
revoke all on public.smart_snapshot from public, anon, authenticated;
comment on table public.smart_snapshot is 'The engine''s barangay-wide analyses, worked out once a minute when anything changed (0169). Read only through the engine''s functions.';

create or replace function public._smart_snapshot_refresh(p_force boolean default false)
returns boolean
language plpgsql volatile security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_at timestamptz;
  v_n  integer;
begin
  select min(s.at), count(*) into v_at, v_n from public.smart_snapshot s;
  if not p_force and v_n = 4 and v_at > now() - interval '5 minutes'
     and coalesce((select max(greatest(rp.created_at, coalesce(rp.updated_at, rp.created_at))) from public.reports rp), 'epoch'::timestamptz) < v_at
     and coalesce((select max(sl.created_at) from public.status_logs sl), 'epoch'::timestamptz) < v_at
     and coalesce((select max(greatest(d.assigned_at, coalesce(d.accepted_at, d.assigned_at), coalesce(d.resolved_at, d.assigned_at))) from public.dispatches d), 'epoch'::timestamptz) < v_at then
    return false;   -- nothing that could change an analysis happened since the lists were made
  end if;
  insert into public.smart_snapshot (key, data, at) values
    ('deadline_risk', coalesce((select jsonb_agg(to_jsonb(x)) from public._smart_deadline_risk() x), '[]'::jsonb), now()),
    ('stuck',         coalesce((select jsonb_agg(to_jsonb(x)) from public._smart_stuck() x), '[]'::jsonb), now()),
    ('spikes',        coalesce((select jsonb_agg(to_jsonb(x)) from public._smart_spikes() x), '[]'::jsonb), now()),
    ('patterns',      coalesce((select jsonb_agg(to_jsonb(x)) from public._smart_patterns(null) x), '[]'::jsonb), now())
  on conflict (key) do update set data = excluded.data, at = excluded.at;
  return true;
end $$;
revoke all on function public._smart_snapshot_refresh(boolean) from public, anon, authenticated;
comment on function public._smart_snapshot_refresh(boolean) is '0169: works out the engine''s four analyses into smart_snapshot when anything could have changed them (or every five minutes). Run by the smart-snapshot job.';

-- ---------- 2. reading the lists (a list older than ten minutes, or missing, means the analysis runs live) ----------
create or replace function public._snap_deadline_risk()
returns table (report_id uuid, tracking_id text, due_at timestamptz, hours_left numeric, typical_hours numeric, slow_hours numeric,
               tanod_jobs integer, risk text, reasons jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
declare d jsonb;
begin
  select s.data into d from public.smart_snapshot s where s.key = 'deadline_risk' and s.at > now() - interval '10 minutes';
  if d is null then return query select * from public._smart_deadline_risk(); return; end if;
  return query
    select x.report_id, x.tracking_id, x.due_at,
           (extract(epoch from (x.due_at - now())) / 3600)::numeric,   -- from now, not from when the list was made
           x.typical_hours, x.slow_hours, x.tanod_jobs, x.risk, x.reasons
      from jsonb_to_recordset(d) as x(report_id uuid, tracking_id text, due_at timestamptz, hours_left numeric, typical_hours numeric,
                                      slow_hours numeric, tanod_jobs integer, risk text, reasons jsonb);
end $$;

create or replace function public._snap_stuck()
returns table (report_id uuid, tracking_id text, status public.report_status, days_quiet integer, last_activity text, last_activity_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
declare d jsonb;
begin
  select s.data into d from public.smart_snapshot s where s.key = 'stuck' and s.at > now() - interval '10 minutes';
  if d is null then return query select * from public._smart_stuck(); return; end if;
  return query
    select x.report_id, x.tracking_id, x.status, x.days_quiet, x.last_activity, x.last_activity_at
      from jsonb_to_recordset(d) as x(report_id uuid, tracking_id text, status public.report_status, days_quiet integer,
                                      last_activity text, last_activity_at timestamptz);
end $$;

create or replace function public._snap_spikes()
returns table (category public.complaint_category, this_week integer, usual numeric, times_usual numeric, place text)
language plpgsql stable security definer set search_path = public, extensions as $$
declare d jsonb;
begin
  select s.data into d from public.smart_snapshot s where s.key = 'spikes' and s.at > now() - interval '10 minutes';
  if d is null then return query select * from public._smart_spikes(); return; end if;
  return query
    select x.category, x.this_week, x.usual, x.times_usual, x.place
      from jsonb_to_recordset(d) as x(category public.complaint_category, this_week integer, usual numeric, times_usual numeric, place text);
end $$;

create or replace function public._snap_patterns()
returns table (pattern_key text, category public.complaint_category, lat double precision, lng double precision, reports integer, weeks integer,
               residents integer, still_open integer, first_at timestamptz, last_at timestamptz, hazard text, tracking_ids text[])
language plpgsql stable security definer set search_path = public, extensions as $$
declare d jsonb;
begin
  select s.data into d from public.smart_snapshot s where s.key = 'patterns' and s.at > now() - interval '10 minutes';
  if d is null then return query select * from public._smart_patterns(null); return; end if;
  return query
    select x.pattern_key, x.category, x.lat, x.lng, x.reports, x.weeks, x.residents, x.still_open, x.first_at, x.last_at, x.hazard, x.tracking_ids
      from jsonb_to_recordset(d) as x(pattern_key text, category public.complaint_category, lat double precision, lng double precision,
                                      reports integer, weeks integer, residents integer, still_open integer, first_at timestamptz,
                                      last_at timestamptz, hazard text, tracking_ids text[]);
end $$;

-- internal: only the engine's own functions read them (each checks who is asking first)
revoke all on function public._snap_deadline_risk() from public, anon, authenticated;
revoke all on function public._snap_stuck() from public, anon, authenticated;
revoke all on function public._snap_spikes() from public, anon, authenticated;
revoke all on function public._snap_patterns() from public, anon, authenticated;

-- ---------- 3. the public engine functions read the lists ----------
create or replace function public.smart_deadline_risk()
returns table (report_id uuid, tracking_id text, due_at timestamptz, hours_left numeric, typical_hours numeric, slow_hours numeric,
               tanod_jobs integer, risk text, reasons jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_full_viewer() then raise exception 'Only an administrator can see deadline risk.' using errcode = 'insufficient_privilege'; end if;
  return query select * from public._snap_deadline_risk();
end $$;

create or replace function public.smart_stuck_cases()
returns table (report_id uuid, tracking_id text, status public.report_status, days_quiet integer, last_activity text, last_activity_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_full_viewer() then raise exception 'Only an administrator can see quiet cases.' using errcode = 'insufficient_privilege'; end if;
  return query select * from public._snap_stuck();
end $$;

create or replace function public.smart_spikes()
returns table (category public.complaint_category, this_week integer, usual numeric, times_usual numeric, place text)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_full_viewer() then raise exception 'Only an administrator can see spikes.' using errcode = 'insufficient_privilege'; end if;
  return query select * from public._snap_spikes();
end $$;

-- the default window (p_days null) comes from the list; another window (Settings' 90 days) is worked out live, as before
create or replace function public.smart_patterns(p_days integer default null)
returns table (pattern_key text, category public.complaint_category, lat double precision, lng double precision, reports integer, weeks integer,
               residents integer, still_open integer, first_at timestamptz, last_at timestamptz, hazard text, tracking_ids text[])
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_full_viewer() then raise exception 'Only an administrator can see recurring problems.' using errcode = 'insufficient_privilege'; end if;
  if p_days is null then return query select * from public._snap_patterns(); return; end if;
  return query select * from public._smart_patterns(p_days);
end $$;

create or replace function public.smart_summary()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v jsonb;
begin
  if not public.is_full_viewer() then raise exception 'Only an administrator can see SMART results.' using errcode = 'insufficient_privilege'; end if;
  select jsonb_build_object(
           'urgent_waiting', count(*) filter (where t.effective_level = 'urgent'),
           'high_waiting',   count(*) filter (where t.effective_level = 'high'))
    into v
    from public.report_triage t join public.reports r on r.id = t.report_id
   where r.deleted_at is null and r.status in ('pending_review', 'validated') and t.effective_level in ('urgent', 'high')
     and not exists (select 1 from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'));
  return v || (select jsonb_build_object('recurring', count(*), 'recurring_open', count(*) filter (where p.still_open > 0))
                 from public._snap_patterns() p);
end $$;

-- ---------- 4. the module: the person's own part live, the analyses from the lists ----------
create or replace function public.smart_module()
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_me   uuid := auth.uid();
  v_tier text := public.admin_tier();
  v_full boolean := coalesce(public.is_full_viewer(), false);
  v_com  text;
  v_mod  text;
  v_cats text[];
  v jsonb;
begin
  if v_tier is null then raise exception 'Only an administrator has a SMART module.' using errcode = 'insufficient_privilege'; end if;
  select u.committee into v_com from public.users u where u.id = v_me;
  v_mod := case when v_full then 'barangay' when v_tier = 'committee' then 'committee' else 'staff' end;
  if not v_full then
    select coalesce(array_agg(cc.category::text order by cc.category), '{}') into v_cats
      from public.committee_categories cc join public.committees c on c.key = cc.committee and c.active
     where cc.committee = v_com;
  end if;

  with open_cases as (
    select r.id, r.tracking_id, r.category, r.status, r.due_at, r.handler_id, r.awaiting_placement, r.subject
      from public.reports r
     where r.deleted_at is null and r.referred_to is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and (v_full or public._user_sees_case(v_me, r.id, r.category, r.handler_id))
  ),
  waiting as (   -- validated or still in review, and no tanod on it: what the triage level is for
    select o.id, t.effective_level as lvl from open_cases o join public.report_triage t on t.report_id = o.id
     where o.status in ('pending_review', 'validated')
       and not exists (select 1 from public.dispatches d where d.report_id = o.id and d.state in ('assigned', 'accepted'))
  ),
  members as (   -- the tanods this module watches: every active tanod, or the committee's approved ones
    select u.id, u.duty_status,
           exists (select 1 from public.dispatches d where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) as busy
      from public.users u
     where u.role = 'tanod' and u.removed_at is null and u.verification_status = 'verified'
       and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
       and (v_full or exists (select 1 from public.tanod_committees tc where tc.tanod_id = u.id and tc.committee = v_com and tc.status = 'approved'))
  )
  select jsonb_build_object(
    'module', v_mod,
    'committee', case when v_full then null else v_com end,
    'categories', case when v_full then null else to_jsonb(v_cats) end,
    'counts', jsonb_build_object(
      'open',           (select count(*) from open_cases),
      'urgent_waiting', (select count(*) from waiting where lvl = 'urgent'),
      'high_waiting',   (select count(*) from waiting where lvl = 'high'),
      'overdue',        (select count(*) from open_cases where due_at < now()),
      'due_24h',        (select count(*) from open_cases where due_at >= now() and due_at < now() + interval '24 hours'),
      'untaken',        (select count(*) from open_cases where handler_id is null and not awaiting_placement),
      'mine',           (select count(*) from open_cases where handler_id = v_me)),
    'decisions', case
      when v_mod = 'staff' or v_tier = 'captain' then null
      else jsonb_build_object(
        'escalations', (select count(*) from public.escalation_requests e join open_cases o on o.id = e.report_id where e.status = 'pending'),
        'reroute',     (select count(*) from public.reroute_questions q where q.state = 'open' and (v_full or q.committee = v_com)),
        'forwarded',   (select count(*) from public.notifications n where n.user_id = v_me and n.kind = 'case_forwarded' and not n.is_read),
        'flags',       (select count(*) from public.case_forward_flags f where (v_full and f.to_super) or (not v_full and f.from_committee = v_com)),
        'to_place',    case when v_full then (select count(*) from public.reports r where r.awaiting_placement and r.deleted_at is null) end,
        'tanods_proposed', case when v_full then (select count(*) from public.tanod_committees where status = 'proposed') end)
    end,
    'deadline_risk', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.hours_left) from (
        select d.report_id, d.tracking_id, d.due_at, round(d.hours_left, 1) as hours_left, d.risk, d.reasons
          from public._snap_deadline_risk() d join open_cases o on o.id = d.report_id
         order by d.hours_left limit 8) x), '[]'::jsonb),
    'quiet', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.days_quiet desc) from (
        select s.report_id, s.tracking_id, s.status, s.days_quiet, s.last_activity
          from public._snap_stuck() s join open_cases o on o.id = s.report_id
         order by s.days_quiet desc limit 8) x), '[]'::jsonb),
    'spikes', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.times_usual desc) from (
        select s.category, s.this_week, s.usual, s.times_usual, s.place
          from public._snap_spikes() s where v_full or s.category::text = any (v_cats)) x), '[]'::jsonb),
    'patterns', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.still_open desc, x.reports desc) from (
        select p.pattern_key, p.category, p.reports, p.weeks, p.residents, p.still_open, p.hazard, p.last_at, p.tracking_ids[1:3] as tracking_ids
          from public._snap_patterns() p where v_full or p.category::text = any (v_cats)
         order by p.still_open desc, p.reports desc limit 6) x), '[]'::jsonb),
    'tanods', jsonb_build_object(
      'total',    (select count(*) from members),
      'on_duty',  (select count(*) from members where duty_status = 'on_duty' and not busy),
      'busy',     (select count(*) from members where busy),
      'lunch',    (select count(*) from members where duty_status = 'lunch'),
      'break',    (select count(*) from members where duty_status = 'break'),
      'offline',  (select count(*) from members where coalesce(duty_status, 'offline') = 'offline' and not busy)),
    'at', now())
  into v;
  return v;
end $$;

revoke all on function public.smart_module() from public, anon;
grant execute on function public.smart_module() to authenticated;

-- ---------- 5. the job, and the first lists ----------
select cron.unschedule('smart-snapshot') where exists (select 1 from cron.job where jobname = 'smart-snapshot');
select cron.schedule('smart-snapshot', '* * * * *', $$select public._smart_snapshot_refresh()$$);
select public._smart_snapshot_refresh(true);
