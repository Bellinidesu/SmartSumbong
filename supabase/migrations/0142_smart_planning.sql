-- =============================================================
-- SmartSumbong — 0142 SMART plans ahead (Iteration 3)
--
-- Four read-only views of the barangay's own history, for administrators,
-- and the one table that keeps what an administrator decides from them:
--
--   1. smart_roster_suggestion(): for each weekday and 3-hour block, the
--      reports usually expected, the tanods that would cover them, and the
--      number usually on duty. A suggestion; nothing is enforced.
--   2. Hotspot work orders: a problem that keeps coming back
--      (smart_patterns) becomes one "permanent fix" item for the council,
--      with its reports as evidence (smart_work_orders).
--   3. smart_forecast(): the open cases a week from now at the current pace,
--      and what each kind of report is expected this week. The seasonal
--      forecast (this month last year) says plainly that it needs a year of
--      history rather than guessing.
--   4. smart_fairness(): how the work was shared among tanods and among
--      administrators. A warning to look, never a verdict on a person.
-- Everything here reads our own counts. Nothing predicts a person, and
-- nothing writes except the work orders.
-- =============================================================

set search_path = public, extensions;

-- ---------- 1. the duty roster, suggested -------------------------------

create or replace function public.smart_roster_suggestion(p_days integer default 90)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
declare
  v_days  integer := greatest(7, least(coalesce(p_days, 90), 365));
  v_since timestamptz := now() - make_interval(days => v_days);
  v_weeks numeric;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  -- weeks of real history inside the window (the system is young: do not divide by weeks that never happened)
  select greatest(1, extract(epoch from now() - greatest(v_since, coalesce(min(created_at), now()))) / 604800.0)
    into v_weeks from public.reports where deleted_at is null and created_at > v_since;
  return jsonb_build_object(
    'days', v_days,
    'weeks', round(v_weeks, 1),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dow', x.dow, 'block', x.blk, 'from_hour', x.blk * 3,
               'reports', x.n, 'expected', round(x.n / v_weeks, 1),
               'suggested', case when x.n > 0 then greatest(1, ceil(x.n / v_weeks / 2.0))::int else 0 end,
               'usual', x.usual,
               'gap', (case when x.n > 0 then greatest(1, ceil(x.n / v_weeks / 2.0))::int else 0 end) - x.usual)
             order by x.dow, x.blk)
      from (
        select coalesce(r.dow, d.dow) as dow, coalesce(r.blk, d.blk) as blk, coalesce(r.n, 0) as n, coalesce(d.usual, 0)::numeric(6,1) as usual
          from (select extract(dow from created_at at time zone 'Asia/Manila')::int dow,
                       (extract(hour from created_at at time zone 'Asia/Manila')::int / 3) blk, count(*) n
                  from public.reports where deleted_at is null and created_at > v_since group by 1, 2) r
          full join (
            -- the tanods usually on duty in that block: distinct tanods on each such day, averaged over those days
            select a.dow, a.blk, round(avg(a.tanods), 1) as usual
              from (select extract(dow from logged_at at time zone 'Asia/Manila')::int dow,
                           (extract(hour from logged_at at time zone 'Asia/Manila')::int / 3) blk,
                           (logged_at at time zone 'Asia/Manila')::date as day, count(distinct tanod_id) as tanods
                      from public.attendance where duty_status = 'on_duty' and logged_at > v_since group by 1, 2, 3) a
             group by a.dow, a.blk) d on d.dow = r.dow and d.blk = r.blk) x), '[]'));
end $$;

-- ---------- 2. hotspot work orders ---------------------------------------

create table public.smart_work_orders (
  id          uuid primary key default gen_random_uuid(),
  pattern_key text not null,
  title       text not null check (char_length(title) between 3 and 140),
  category    public.complaint_category not null,
  status      text not null default 'open' check (status in ('open', 'planned', 'done', 'dropped')),
  note        text check (char_length(note) <= 500),
  evidence    jsonb not null,
  created_by  uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_by  uuid references public.users (id) on delete set null,
  updated_at  timestamptz not null default now()
);
create unique index smart_work_orders_one_open on public.smart_work_orders (pattern_key) where status in ('open', 'planned');
create index smart_work_orders_status_idx on public.smart_work_orders (status, created_at desc);
alter table public.smart_work_orders enable row level security;
create policy smart_work_orders_admin_read on public.smart_work_orders for select using ((select public.is_admin()));
comment on table public.smart_work_orders is
  '0142: a recurring problem (smart_patterns) kept as one permanent-fix item for the council, with its reports as evidence. Written only by smart_workorder_create() and _set().';

create or replace function public.smart_workorder_create(p_pattern_key text, p_title text, p_note text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  p record;
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if v_title is null or char_length(v_title) < 3 then raise exception 'Give the work order a title' using errcode = 'check_violation'; end if;
  select * into p from public.smart_patterns(90) where pattern_key = p_pattern_key;
  if not found then raise exception 'That recurring problem is no longer in the last 90 days' using errcode = 'check_violation'; end if;
  insert into public.smart_work_orders (pattern_key, title, category, note, evidence, created_by, updated_by)
  values (p.pattern_key, left(v_title, 140), p.category, left(nullif(trim(coalesce(p_note, '')), ''), 500),
          jsonb_build_object('reports', p.reports, 'weeks', p.weeks, 'residents', p.residents, 'still_open', p.still_open,
                             'first_at', p.first_at, 'last_at', p.last_at, 'lat', p.lat, 'lng', p.lng, 'hazard', p.hazard,
                             'tracking_ids', to_jsonb(p.tracking_ids)),
          auth.uid(), auth.uid())
  returning id into v_id;
  perform public._smart_event('work_order', null, format('Work order opened: %s', left(v_title, 120)), jsonb_build_object('id', v_id, 'pattern', p.pattern_key));
  return v_id;
exception when unique_violation then
  raise exception 'There is already an open work order for that problem' using errcode = 'check_violation';
end $$;

create or replace function public.smart_workorder_set(p_id uuid, p_status text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if p_status not in ('open', 'planned', 'done', 'dropped') then raise exception 'Status is open, planned, done or dropped' using errcode = 'check_violation'; end if;
  update public.smart_work_orders
     set status = p_status, note = coalesce(left(nullif(trim(coalesce(p_note, '')), ''), 500), note), updated_by = auth.uid(), updated_at = now()
   where id = p_id;
  if not found then raise exception 'No such work order' using errcode = 'check_violation'; end if;
  perform public._smart_event('work_order', null, format('Work order set to %s', p_status), jsonb_build_object('id', p_id));
exception when unique_violation then
  raise exception 'There is already an open work order for that problem' using errcode = 'check_violation';
end $$;

-- ---------- 3. the forecast ----------------------------------------------

create or replace function public.smart_forecast(p_days integer default 28)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 28), 120));
  v_first timestamptz;
  v_open integer; v_in numeric; v_out numeric;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  select min(created_at) into v_first from public.reports where deleted_at is null;
  select count(*) into v_open from public.reports
   where deleted_at is null and status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation');
  -- per day, over the window or the real history, whichever is shorter
  select (count(*) filter (where created_at > now() - make_interval(days => v_days)))::numeric
         / greatest(1, least(v_days, extract(epoch from now() - coalesce(v_first, now())) / 86400.0)),
         (count(*) filter (where status in ('resolved', 'closed') and coalesce(resolved_at, closed_at, updated_at) > now() - make_interval(days => v_days)))::numeric
         / greatest(1, least(v_days, extract(epoch from now() - coalesce(v_first, now())) / 86400.0))
    into v_in, v_out from public.reports where deleted_at is null;
  return jsonb_build_object(
    'days', v_days,
    'open_now', v_open,
    'arrive_per_day', round(coalesce(v_in, 0), 2),
    'close_per_day', round(coalesce(v_out, 0), 2),
    'open_in_7_days', greatest(0, round(v_open + 7 * (coalesce(v_in, 0) - coalesce(v_out, 0)))::int),
    'this_week', coalesce((select jsonb_agg(jsonb_build_object('category', k.category, 'expected', k.e) order by k.e desc)
                             from (select r.category, round(7 * count(*)::numeric
                                          / greatest(1, least(v_days, extract(epoch from now() - coalesce(v_first, now())) / 86400.0)), 1) as e
                                     from public.reports r where r.deleted_at is null and r.created_at > now() - make_interval(days => v_days)
                                    group by r.category) k), '[]'),
    'history_days', case when v_first is null then 0 else floor(extract(epoch from now() - v_first) / 86400)::int end,
    -- this month last year needs a year of history; say so instead of guessing from less
    'seasonal_ready', v_first is not null and v_first < now() - interval '365 days',
    'seasonal', case when v_first is not null and v_first < now() - interval '365 days'
      then coalesce((select jsonb_agg(jsonb_build_object('category', k.category, 'last_year', k.n) order by k.n desc)
                       from (select r.category, count(*) n from public.reports r
                              where r.deleted_at is null
                                and date_trunc('month', r.created_at at time zone 'Asia/Manila') = date_trunc('month', (now() - interval '1 year') at time zone 'Asia/Manila')
                              group by r.category) k), '[]') else null end);
end $$;

-- ---------- 4. fairness ----------------------------------------------------

create or replace function public.smart_fairness(p_days integer default 14)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 14), 90));
  v_total integer; v_tanods integer; v_top numeric;
  v_open integer; v_top_admin numeric; v_admins integer;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  select count(*) into v_total from public.dispatches where assigned_at > now() - make_interval(days => v_days);
  select count(distinct tanod_id) into v_tanods from public.dispatches where assigned_at > now() - make_interval(days => v_days);
  select coalesce(max(c), 0) into v_top from (select count(*)::numeric c from public.dispatches
    where assigned_at > now() - make_interval(days => v_days) group by tanod_id) z;
  select count(*) into v_open from public.reports
   where deleted_at is null and handler_id is not null and status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation');
  select count(distinct handler_id) into v_admins from public.reports
   where deleted_at is null and handler_id is not null and status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation');
  select coalesce(max(c), 0) into v_top_admin from (select count(*)::numeric c from public.reports
    where deleted_at is null and handler_id is not null and status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
    group by handler_id) z;
  return jsonb_build_object(
    'days', v_days,
    'dispatches', v_total,
    'tanods', coalesce((select jsonb_agg(jsonb_build_object(
                'tanod_id', t.tanod_id, 'name', u.full_name, 'assigned', t.n,
                'share_pct', round(100.0 * t.n / nullif(v_total, 0), 0),
                'resolved', t.res, 'median_accept_minutes', t.med) order by t.n desc)
              from (select d.tanod_id, count(*) n, count(*) filter (where d.state = 'resolved') res,
                           round((percentile_cont(0.5) within group (order by extract(epoch from d.accepted_at - d.assigned_at) / 60.0)
                                   filter (where d.accepted_at is not null))::numeric, 1) as med
                      from public.dispatches d where d.assigned_at > now() - make_interval(days => v_days) group by d.tanod_id) t
              join public.users u on u.id = t.tanod_id), '[]'),
    -- one tanod with most of the work, when several share it: a reason to look, not a verdict
    'tanod_note', case when v_tanods >= 3 and v_total >= 6 and v_top / v_total > 0.5 then 'one_tanod_most' else null end,
    'admins', coalesce((select jsonb_agg(jsonb_build_object('admin_id', a.handler_id, 'name', u.full_name, 'open', a.n,
                'share_pct', round(100.0 * a.n / nullif(v_open, 0), 0)) order by a.n desc)
              from (select handler_id, count(*) n from public.reports
                     where deleted_at is null and handler_id is not null and status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
                     group by handler_id) a join public.users u on u.id = a.handler_id), '[]'),
    'admin_note', case when v_admins >= 2 and v_open >= 6 and v_top_admin / v_open > 0.7 then 'one_admin_most' else null end);
end $$;

revoke all on function public.smart_roster_suggestion(integer), public.smart_workorder_create(text, text, text),
  public.smart_workorder_set(uuid, text, text), public.smart_forecast(integer), public.smart_fairness(integer) from public, anon;
grant execute on function public.smart_roster_suggestion(integer), public.smart_workorder_create(text, text, text),
  public.smart_workorder_set(uuid, text, text), public.smart_forecast(integer), public.smart_fairness(integer) to authenticated;
