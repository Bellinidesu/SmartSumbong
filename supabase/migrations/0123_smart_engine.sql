-- 0123: the SMART engine around the triage score (10 Oct 2026).
--
-- 0122 scores each report. This adds what turns scores into an engine,
-- still without a model; docs/SMART.md explains it in plain words:
--
--   1. overrides     an admin can raise or lower a report's level, with a
--                    reason; every override is kept, so the rules can be
--                    checked against people's judgement.
--   2. patterns      the same kind of problem at the same spot in two or
--                    more different weeks: a recurring problem, not an event.
--   3. the watcher   every 5 minutes: urgent or high reports that nobody
--                    has dispatched in time, and newly recurring problems,
--                    are told to the admins once.
--   4. calibration   per level, how often people overrode it and how fast
--                    those reports were dispatched and resolved; per
--                    factor, how often it was in an overridden report.

set search_path = public, extensions;

-- ---------- rules for the new parts ----------------------------------------

alter table public.smart_rules
  add column urgent_dispatch_minutes integer  not null default 15 check (urgent_dispatch_minutes > 0),
  add column high_dispatch_minutes   integer  not null default 60 check (high_dispatch_minutes > 0),
  add column pattern_metres          integer  not null default 60 check (pattern_metres between 10 and 500),
  add column pattern_min_reports     smallint not null default 3  check (pattern_min_reports >= 2),
  add column pattern_min_weeks       smallint not null default 2  check (pattern_min_weeks >= 1),
  add column pattern_days            integer  not null default 90 check (pattern_days between 7 and 730);

-- ---------- 1. overrides -----------------------------------------------------

alter table public.report_triage
  add column override_level  text check (override_level in ('low', 'normal', 'high', 'urgent')),
  add column override_reason text,
  add column override_by     uuid references public.users (id) on delete set null,
  add column override_at     timestamptz,
  add column effective_level text generated always as (coalesce(override_level, level)) stored,
  add column alerted_at      timestamptz;
create index report_triage_effective_idx on public.report_triage (effective_level, score desc);
create index report_triage_override_by_idx on public.report_triage (override_by);
comment on column public.report_triage.effective_level is
  '0123: the level that counts: an admin''s override if there is one, otherwise the computed level.';

create table public.smart_overrides (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  from_level  text not null,
  to_level    text,               -- null: override removed
  score       smallint not null,
  reasons     jsonb not null,     -- the computed reasons at the time
  reason      text not null check (char_length(reason) between 3 and 300),
  by_user     uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index smart_overrides_report_idx on public.smart_overrides (report_id, created_at desc);
create index smart_overrides_by_idx on public.smart_overrides (by_user);
alter table public.smart_overrides enable row level security;
create policy smart_overrides_admin_read on public.smart_overrides for select using ((select public.is_admin()));
comment on table public.smart_overrides is
  '0123: every time an admin raised, lowered or cleared a report''s SMART level, with the computed score and reasons of that moment.';

/** Admins: set a report's level by hand (p_level null clears it). */
create or replace function public.smart_override(p_report uuid, p_level text, p_reason text)
returns public.report_triage
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  t public.report_triage;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can change a report''s level.' using errcode = 'insufficient_privilege';
  end if;
  if p_level is not null and p_level not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'Level must be low, normal, high or urgent.' using errcode = 'check_violation';
  end if;
  if char_length(coalesce(trim(p_reason), '')) < 3 then
    raise exception 'Say why, in a few words.' using errcode = 'check_violation';
  end if;
  select * into t from public.report_triage where report_id = p_report for update;
  if not found then
    perform public.smart_triage(p_report);
    select * into t from public.report_triage where report_id = p_report for update;
    if not found then raise exception 'No such report.' using errcode = 'no_data_found'; end if;
  end if;

  insert into public.smart_overrides (report_id, from_level, to_level, score, reasons, reason, by_user)
  values (p_report, t.effective_level, p_level, t.score, t.reasons, left(trim(p_reason), 300), auth.uid());

  update public.report_triage
     set override_level = p_level,
         override_reason = case when p_level is null then null else left(trim(p_reason), 300) end,
         override_by = case when p_level is null then null else auth.uid() end,
         override_at = case when p_level is null then null else now() end
   where report_id = p_report
  returning * into t;
  return t;
end $$;

revoke all on function public.smart_override(uuid, text, text) from public, anon;
grant execute on function public.smart_override(uuid, text, text) to authenticated;

-- ---------- 2. recurring problems ---------------------------------------------

/** Places where the same kind of problem keeps coming back: reports of one
    kind within pattern_metres of each other (DBSCAN, as 0042's hotspots),
    at least pattern_min_reports of them, in at least pattern_min_weeks
    different weeks, over the last p_days (default: the rule). */
create or replace function public._smart_patterns(p_days integer default null)
returns table (pattern_key text, category public.complaint_category, lat double precision, lng double precision,
               reports integer, weeks integer, residents integer, still_open integer,
               first_at timestamptz, last_at timestamptz, hazard text, tracking_ids text[])
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  k public.smart_rules%rowtype;
begin
  select * into k from public.smart_rules where id = 1;
  return query
  with scoped as (
    select r.id, r.category, r.tracking_id, r.resident_id, r.status, r.created_at,
           st_transform(r.geom::geometry, 3857) as g
      from public.reports r
     where r.deleted_at is null
       and r.status not in ('rejected', 'cancelled')
       and r.created_at > now() - make_interval(days => coalesce(p_days, k.pattern_days))
  ), clustered as (
    select s.*, st_clusterdbscan(s.g, eps := k.pattern_metres, minpoints := k.pattern_min_reports)
                  over (partition by s.category) as cid
      from scoped s
  ), grouped as (
    select c.category as cat, c.cid,
           st_transform(st_centroid(st_collect(c.g)), 4326) as centre,
           count(*)::integer as n,
           count(distinct date_trunc('week', c.created_at at time zone 'Asia/Manila'))::integer as wk,
           count(distinct c.resident_id)::integer as who,
           count(*) filter (where c.status not in ('resolved', 'closed', 'archived'))::integer as open_n,
           min(c.created_at) as first_at, max(c.created_at) as last_at,
           array_agg(c.tracking_id order by c.created_at desc) as ids
      from clustered c
     where c.cid is not null
     group by c.category, c.cid
  )
  select g.cat::text || ':' || round(st_y(g.centre)::numeric, 3) || ',' || round(st_x(g.centre)::numeric, 3),
         g.cat, st_y(g.centre), st_x(g.centre), g.n, g.wk, g.who, g.open_n, g.first_at, g.last_at,
         (select format('NOAH %s zone, %s', z.hazard, (array['low', 'medium', 'high'])[z.level])
            from public.hazard_zones z where st_intersects(z.geom, g.centre)
           order by z.level desc limit 1),
         g.ids[1:10]
    from grouped g
   where g.wk >= k.pattern_min_weeks
   order by g.open_n desc, g.n desc, g.last_at desc;
end $$;

revoke all on function public._smart_patterns(integer) from public, anon, authenticated;

/** Admins: the recurring problems (see _smart_patterns). */
create or replace function public.smart_patterns(p_days integer default null)
returns table (pattern_key text, category public.complaint_category, lat double precision, lng double precision,
               reports integer, weeks integer, residents integer, still_open integer,
               first_at timestamptz, last_at timestamptz, hazard text, tracking_ids text[])
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see recurring problems.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_patterns(p_days);
end $$;

revoke all on function public.smart_patterns(integer) from public, anon;
grant execute on function public.smart_patterns(integer) to authenticated;

create table public.smart_patterns_seen (
  pattern_key   text primary key,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  reports       integer not null
);
alter table public.smart_patterns_seen enable row level security;
create policy smart_patterns_seen_admin_read on public.smart_patterns_seen for select using ((select public.is_admin()));
comment on table public.smart_patterns_seen is
  '0123: recurring problems the watcher has already told the admins about (pattern key: kind and centre to ~100 m).';

-- ---------- 3. the watcher -----------------------------------------------------

/** Every 5 minutes (pg_cron): tells admins, once each, about urgent or high
    reports still waiting for a tanod past their time, and about recurring
    problems not seen before. Returns how many messages it sent. */
create or replace function public.smart_watch()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  k public.smart_rules%rowtype;
  r record;
  v_sent integer := 0;
begin
  select * into k from public.smart_rules where id = 1;

  for r in
    select t.report_id, t.effective_level, t.score, rp.tracking_id, rp.created_at
      from public.report_triage t
      join public.reports rp on rp.id = t.report_id
     where t.alerted_at is null
       and t.effective_level in ('urgent', 'high')
       and rp.deleted_at is null
       and rp.status in ('pending_review', 'validated')
       and rp.created_at < now() - make_interval(mins => case t.effective_level
             when 'urgent' then k.urgent_dispatch_minutes else k.high_dispatch_minutes end)
       and not exists (select 1 from public.dispatches d
                        where d.report_id = rp.id and d.state in ('assigned', 'accepted'))
     order by t.score desc
     limit 50
  loop
    insert into public.notifications (user_id, kind, report_id, message)
    select a.id, 'sla_warning', r.report_id,
           format('SMART: %s report %s has waited %s min without a tanod.',
                  initcap(r.effective_level), r.tracking_id,
                  floor(extract(epoch from now() - r.created_at) / 60)::integer)
      from public.users a
     where a.role = 'admin' and not coalesce(a.is_suspended, false);
    update public.report_triage set alerted_at = now() where report_id = r.report_id;
    v_sent := v_sent + 1;
  end loop;

  for r in select p.* from public._smart_patterns(null) p loop
    if not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = r.pattern_key) then
      insert into public.smart_patterns_seen (pattern_key, reports) values (r.pattern_key, r.reports);
      perform public._notify_admins(format(
        'SMART: recurring problem. %s reports of %s near the same spot over %s weeks (%s still open). Latest: %s.',
        r.reports, replace(r.category::text, '_', ' '), r.weeks, r.still_open, r.tracking_ids[1]));
      v_sent := v_sent + 1;
    else
      update public.smart_patterns_seen set last_seen_at = now(), reports = r.reports where pattern_key = r.pattern_key;
    end if;
  end loop;
  return v_sent;
end $$;

revoke all on function public.smart_watch() from public, anon, authenticated;

select cron.schedule('smart-watch', '*/5 * * * *', $$ select public.smart_watch() $$);

-- ---------- 4. calibration -------------------------------------------------------

/** Admins: how the computed levels compare with what people did, over the
    last p_days. Per computed level: reports, how many were overridden up
    or down, and median minutes to the first dispatch and hours to resolve. */
create or replace function public.smart_calibration(p_days integer default 90)
returns table (level text, reports integer, raised integer, lowered integer,
               median_minutes_to_dispatch numeric, median_hours_to_resolve numeric)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see calibration.' using errcode = 'insufficient_privilege';
  end if;
  return query
  with base as (
    select t.level, t.override_level, rp.created_at, rp.resolved_at,
           (select min(d.assigned_at) from public.dispatches d where d.report_id = rp.id) as first_dispatch
      from public.report_triage t
      join public.reports rp on rp.id = t.report_id
     where rp.deleted_at is null and rp.created_at > now() - make_interval(days => p_days)
  ), ranked as (
    select b.*, array_position(array['low', 'normal', 'high', 'urgent'], b.level) as lv,
           array_position(array['low', 'normal', 'high', 'urgent'], b.override_level) as ov
      from base b
  )
  select x.level, count(*)::integer,
         count(*) filter (where x.ov > x.lv)::integer,
         count(*) filter (where x.ov < x.lv)::integer,
         round((percentile_cont(0.5) within group (order by extract(epoch from x.first_dispatch - x.created_at) / 60))::numeric, 1),
         round((percentile_cont(0.5) within group (order by extract(epoch from x.resolved_at - x.created_at) / 3600))::numeric, 1)
    from ranked x
   group by x.level, x.lv
   order by x.lv desc;
end $$;

revoke all on function public.smart_calibration(integer) from public, anon;
grant execute on function public.smart_calibration(integer) to authenticated;

/** Admins: per factor (kind, each word group, hazard zone, nearby reports,
    night), in how many scored reports it appeared and how many of those an
    admin raised or lowered. A factor often in lowered reports is worth too
    many points; one often in raised reports, too few. */
create or replace function public.smart_factor_stats(p_days integer default 90)
returns table (factor text, detail text, reports integer, raised integer, lowered integer)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see calibration.' using errcode = 'insufficient_privilege';
  end if;
  return query
  with base as (
    select t.reasons,
           array_position(array['low', 'normal', 'high', 'urgent'], t.level) as lv,
           array_position(array['low', 'normal', 'high', 'urgent'], t.override_level) as ov
      from public.report_triage t
      join public.reports rp on rp.id = t.report_id
     where rp.deleted_at is null and rp.created_at > now() - make_interval(days => p_days)
  )
  select x ->> 'factor',
         case when x ->> 'factor' in ('nearby reports', 'night') then null else x ->> 'detail' end,
         count(*)::integer,
         count(*) filter (where b.ov > b.lv)::integer,
         count(*) filter (where b.ov < b.lv)::integer
    from base b, jsonb_array_elements(b.reasons) x
   group by 1, 2
   order by count(*) filter (where b.ov is not null and b.ov <> b.lv) desc, count(*) desc;
end $$;

revoke all on function public.smart_factor_stats(integer) from public, anon;
grant execute on function public.smart_factor_stats(integer) to authenticated;
