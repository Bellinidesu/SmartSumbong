-- 0122: SMART triage, a rule-based prototype (10 Oct 2026).
--
-- The "smart" in SmartSumbong without a model: fixed, readable rules the
-- barangay can see and change, and every result says why. Four parts:
--
--   1. smart_triage   a 0-100 urgency score for every report, with its
--                     reasons, kept in report_triage and refreshed when the
--                     report or a report near it changes.
--   2. smart_duplicates  earlier open reports that are probably the same
--                     problem (same kind, close by, recent, similar words).
--   3. smart_tanod_ranking  who to send, best first, and why: distance,
--                     current load, and how many cases they closed nearby.
--   4. smart_eta      how long this kind of complaint actually takes here,
--                     from the barangay's own closed cases.
--
-- The rules live in smart_rules (one row). Admins read and change them;
-- nothing here learns or changes on its own.

set search_path = public, extensions;

create extension if not exists pg_trgm with schema extensions;

-- ---------- the rules -------------------------------------------------------

create table public.smart_rules (
  id                      smallint primary key default 1 check (id = 1),
  -- points for the kind of complaint
  category_points         jsonb not null default '{
    "public_safety_infrastructure": 35, "peace_order_nuisance": 30,
    "environmental_waste_hazard": 25, "traffic_violation": 20,
    "street_obstruction": 20, "animal_welfare": 15,
    "barangay_service": 10, "other": 10}',
  -- words in the subject or description; each group counts once.
  -- Patterns are PostgreSQL regular expressions over the lower-cased text
  -- (\m and \M mark the start and end of a word).
  keyword_groups          jsonb not null default '[
    {"label": "fire",        "points": 30, "pattern": "\\m(fire|sunog|nasunog|nasusunog|apoy|usok|smoke)\\M"},
    {"label": "weapon",      "points": 30, "pattern": "\\m(gun|baril|binaril|knife|kutsilyo|patalim|saksak|sinaksak|stabbed|shooting|holdap|hold-?up|robbery|nanakawan)\\M"},
    {"label": "injury",      "points": 30, "pattern": "\\m(injured|injury|bleeding|blood|sugat|sugatan|nasugatan|dugo|duguan|unconscious|walang malay)\\M"},
    {"label": "gas leak",    "points": 30, "pattern": "\\m(gas leak|tagas ng gas|amoy gas|lpg)\\M"},
    {"label": "live wire",   "points": 25, "pattern": "\\m(live wire|kuryente|nakuryente|sparking|spark|kawad|transformer)\\M"},
    {"label": "collapse",    "points": 25, "pattern": "\\m(collapsed?|gumuho|guho|bumagsak|natumba|nabuwal|fallen tree)\\M"},
    {"label": "accident",    "points": 25, "pattern": "\\m(accident|aksidente|bangga|nabangga|banggaan|collision|crash)\\M"},
    {"label": "fight",       "points": 20, "pattern": "\\m(fight|fighting|nag-?aaway|rambol|riot|suntukan|bugbog|binugbog|gulo)\\M"},
    {"label": "flooding",    "points": 15, "pattern": "\\m(flood|flooding|flooded|baha|binaha|bumaha|lubog|lumubog)\\M"},
    {"label": "vulnerable",  "points": 10, "pattern": "\\m(child|children|bata|mga bata|elderly|matanda|senior|lola|lolo|pwd|buntis|pregnant)\\M"}
  ]',
  keyword_cap             smallint not null default 45,
  -- inside a NOAH zone (0121), by level 1-3
  hazard_points           jsonb not null default '{"1": 5, "2": 10, "3": 15}',
  -- other residents reporting the same kind nearby
  corroboration_metres    integer  not null default 150,
  corroboration_hours     integer  not null default 48,
  corroboration_points    smallint not null default 8,
  corroboration_cap       smallint not null default 24,
  -- filed at night, for safety kinds
  night_points            smallint not null default 5,
  -- level cut-offs on the 0-100 score
  urgent_from             smallint not null default 70,
  high_from               smallint not null default 45,
  normal_from             smallint not null default 25,
  -- possible duplicates
  duplicate_metres        integer  not null default 100,
  duplicate_hours         integer  not null default 72,
  duplicate_similarity    real     not null default 0.3,
  updated_at              timestamptz not null default now(),
  updated_by              uuid references public.users (id) on delete set null,
  check (urgent_from > high_from and high_from > normal_from and normal_from > 0)
);
insert into public.smart_rules default values;

alter table public.smart_rules enable row level security;
create policy smart_rules_admin_read on public.smart_rules for select using ((select public.is_admin()));
create policy smart_rules_admin_write on public.smart_rules for update
  using ((select public.is_admin())) with check ((select public.is_admin()));
comment on table public.smart_rules is
  '0122: the rules SMART triage follows (points per kind, words, hazard zones, nearby reports, night, cut-offs, duplicates). One row; admins change it.';

-- ---------- results ---------------------------------------------------------

create table public.report_triage (
  report_id            uuid primary key references public.reports (id) on delete cascade,
  score                smallint not null check (score between 0 and 100),
  level                text not null check (level in ('low', 'normal', 'high', 'urgent')),
  reasons              jsonb not null,
  possible_duplicates  smallint not null default 0,
  computed_at          timestamptz not null default now()
);
create index report_triage_level_idx on public.report_triage (level, score desc);

alter table public.report_triage enable row level security;
create policy report_triage_admin_read on public.report_triage for select using ((select public.is_admin()));
comment on table public.report_triage is
  '0122: SMART triage of each report: score 0-100, level, and the reasons [{factor, detail, points}]. Written only by smart_triage().';

-- ---------- 1. triage -------------------------------------------------------

/** Scores one report and stores the result. Never raises: a failure here
    must not stop a complaint from being filed. */
create or replace function public.smart_triage(p_report uuid)
returns public.report_triage
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r       public.reports%rowtype;
  k       public.smart_rules%rowtype;
  v_text  text;
  v_pts   integer;
  v_kw    integer := 0;
  v_score integer := 0;
  v_why   jsonb := '[]';
  v_lvl   smallint;
  v_haz   text;
  v_n     integer;
  v_dups  integer;
  v_hour  integer;
  g       jsonb;
  v_out   public.report_triage;
begin
  select * into r from public.reports where id = p_report;
  if not found then return null; end if;
  select * into k from public.smart_rules where id = 1;

  -- the kind of complaint
  v_pts := coalesce((k.category_points ->> r.category::text)::integer, 0);
  v_score := v_pts;
  v_why := v_why || jsonb_build_object('factor', 'category', 'detail', r.category::text, 'points', v_pts);

  -- words
  v_text := lower(r.subject || ' ' || r.description);
  for g in select * from jsonb_array_elements(k.keyword_groups) loop
    if v_text ~ (g ->> 'pattern') then
      v_pts := least((g ->> 'points')::integer, k.keyword_cap - v_kw);
      if v_pts > 0 then
        v_kw := v_kw + v_pts;
        v_why := v_why || jsonb_build_object('factor', 'words', 'detail', g ->> 'label',
                                             'points', v_pts,
                                             'matched', substring(v_text from (g ->> 'pattern')));
      end if;
    end if;
  end loop;
  v_score := v_score + v_kw;

  -- hazard zone
  select z.level, z.hazard into v_lvl, v_haz
    from public.hazard_zones z
   where st_intersects(z.geom, r.geom::geometry)
   order by z.level desc, z.hazard
   limit 1;
  if v_lvl is not null then
    v_pts := coalesce((k.hazard_points ->> v_lvl::text)::integer, 0);
    v_score := v_score + v_pts;
    v_why := v_why || jsonb_build_object('factor', 'hazard zone',
      'detail', format('NOAH %s zone, %s', v_haz, (array['low', 'medium', 'high'])[v_lvl]), 'points', v_pts);
  end if;

  -- other residents, same kind, close in place and time
  select count(distinct o.resident_id) into v_n
    from public.reports o
   where o.id <> r.id
     and o.category = r.category
     and o.resident_id <> r.resident_id
     and o.deleted_at is null
     and o.status not in ('rejected', 'cancelled')
     and o.created_at between r.created_at - make_interval(hours => k.corroboration_hours)
                          and r.created_at + make_interval(hours => k.corroboration_hours)
     and st_dwithin(o.geom, r.geom, k.corroboration_metres);
  if v_n > 0 then
    v_pts := least(v_n * k.corroboration_points, k.corroboration_cap);
    v_score := v_score + v_pts;
    v_why := v_why || jsonb_build_object('factor', 'nearby reports',
      'detail', format('%s other resident%s reported this within %s m', v_n, case when v_n = 1 then '' else 's' end,
                       k.corroboration_metres),
      'points', v_pts);
  end if;

  -- night, for safety kinds
  v_hour := extract(hour from r.created_at at time zone 'Asia/Manila');
  if (v_hour >= 22 or v_hour < 5)
     and r.category in ('peace_order_nuisance', 'public_safety_infrastructure', 'traffic_violation') then
    v_score := v_score + k.night_points;
    v_why := v_why || jsonb_build_object('factor', 'night', 'detail', format('filed at %s:00', v_hour),
                                         'points', k.night_points);
  end if;

  select count(*) into v_dups from public.smart_duplicates_of(r.id);

  v_score := greatest(0, least(100, v_score));
  insert into public.report_triage as t (report_id, score, level, reasons, possible_duplicates, computed_at)
  values (r.id, v_score,
          case when v_score >= k.urgent_from then 'urgent'
               when v_score >= k.high_from   then 'high'
               when v_score >= k.normal_from then 'normal'
               else 'low' end,
          v_why, v_dups, now())
  on conflict (report_id) do update
     set score = excluded.score, level = excluded.level, reasons = excluded.reasons,
         possible_duplicates = excluded.possible_duplicates, computed_at = excluded.computed_at
  returning * into v_out;
  return v_out;
exception when others then
  raise warning 'smart_triage(%) failed: %', p_report, sqlerrm;
  return null;
end $$;

revoke all on function public.smart_triage(uuid) from public, anon, authenticated;
comment on function public.smart_triage(uuid) is
  '0122: scores one report from smart_rules and stores it in report_triage. Internal; called by triggers and smart_retriage().';

/** Admins: score again (after changing the rules, for example). Null = every open report. */
create or replace function public.smart_retriage(p_report uuid default null)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer := 0;
  v_id uuid;
begin
  if not public.is_admin() and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only an administrator can re-score reports.' using errcode = 'insufficient_privilege';
  end if;
  for v_id in
    select id from public.reports
     where (p_report is null and deleted_at is null
            and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled'))
        or id = p_report
  loop
    perform public.smart_triage(v_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

revoke all on function public.smart_retriage(uuid) from public, anon;
grant execute on function public.smart_retriage(uuid) to authenticated;

-- Score a new report, and the open reports near it that it now backs up.
create or replace function public._smart_triage_after_write()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  k public.smart_rules%rowtype;
  v_id uuid;
begin
  perform public.smart_triage(new.id);
  select * into k from public.smart_rules where id = 1;
  for v_id in
    select o.id from public.reports o
     where o.id <> new.id
       and o.category = new.category
       and o.deleted_at is null
       and o.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and o.created_at > new.created_at - make_interval(hours => k.corroboration_hours)
       and st_dwithin(o.geom, new.geom, greatest(k.corroboration_metres, k.duplicate_metres))
     limit 20
  loop
    perform public.smart_triage(v_id);
  end loop;
  return null;
exception when others then
  raise warning 'SMART triage after write failed: %', sqlerrm;
  return null;
end $$;

revoke all on function public._smart_triage_after_write() from public, anon, authenticated;

create trigger reports_smart_triage
  after insert or update of category, subject, description, latitude, longitude
  on public.reports
  for each row execute function public._smart_triage_after_write();

-- ---------- 2. possible duplicates -------------------------------------------

/** Earlier open reports that are probably the same problem: same kind,
    within duplicate_metres, filed within duplicate_hours before it, and
    either worded alike (trigram similarity) or within 25 m. */
create or replace function public.smart_duplicates_of(p_report uuid)
returns table (report_id uuid, tracking_id text, metres integer, hours_apart numeric,
               similarity real, status public.report_status)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select * from public.smart_rules where id = 1),
       r as (select * from public.reports where id = p_report)
  select o.id, o.tracking_id,
         round(st_distance(o.geom, r.geom))::integer,
         round(extract(epoch from (r.created_at - o.created_at)) / 3600.0, 1),
         extensions.similarity(lower(o.subject || ' ' || o.description), lower(r.subject || ' ' || r.description)),
         o.status
    from r, k, public.reports o
   where o.id <> r.id
     and o.category = r.category
     and o.deleted_at is null
     and o.status not in ('rejected', 'cancelled', 'closed', 'archived')
     and o.created_at <= r.created_at
     and o.created_at > r.created_at - make_interval(hours => k.duplicate_hours)
     and st_dwithin(o.geom, r.geom, k.duplicate_metres)
     and (extensions.similarity(lower(o.subject || ' ' || o.description), lower(r.subject || ' ' || r.description)) >= k.duplicate_similarity
          or st_dwithin(o.geom, r.geom, 25))
   order by 5 desc, 3
   limit 5
$$;

revoke all on function public.smart_duplicates_of(uuid) from public, anon, authenticated;

/** Admins: the possible duplicates of a report. */
create or replace function public.smart_duplicates(p_report uuid)
returns table (report_id uuid, tracking_id text, metres integer, hours_apart numeric,
               similarity real, status public.report_status)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see possible duplicates.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public.smart_duplicates_of(p_report);
end $$;

revoke all on function public.smart_duplicates(uuid) from public, anon;
grant execute on function public.smart_duplicates(uuid) to authenticated;

-- ---------- 3. who to send ---------------------------------------------------

/** Tanods who can take the report (nearest_available_tanod, 0067), scored:
    start at 100; minus 1 per 20 m (at most 50); minus 15 per job in hand;
    plus 5 per case they closed within 300 m in the last 90 days (at most
    20); minus 10 when their last location reading is older than
    operational_settings.location_freshness_minutes. The app sends one
    reading at a time (going on duty, opening the app, each dispatch step);
    there is no tracking. */
create or replace function public.smart_tanod_ranking(p_report uuid)
returns table (tanod_id uuid, full_name text, score integer, metres integer,
               active_jobs integer, closed_nearby integer, location_fresh boolean, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can rank tanods.' using errcode = 'insufficient_privilege';
  end if;
  return query
  with c as (
    select n.tanod_id, n.full_name, n.metres,
           (select count(*)::integer from public.dispatches d
             where d.tanod_id = n.tanod_id and d.state in ('assigned', 'accepted')) as active,
           (select count(*)::integer from public.dispatches d
              join public.reports o on o.id = d.report_id
             where d.tanod_id = n.tanod_id and d.state = 'resolved'
               and d.resolved_at > now() - interval '90 days'
               and st_dwithin(o.geom, (select geom from public.reports where id = p_report), 300)) as nearby,
           public.location_is_fresh(u.last_location_at) as fresh,
           u.last_location_at as fix_at
      from public.nearest_available_tanod(p_report) n
      join public.users u on u.id = n.tanod_id
  ), s as (
    select c.*,
           case when c.metres is null then 50 else least(round(c.metres / 20)::integer, 50) end as dist_pen,
           c.active * 15 as load_pen,
           least(c.nearby * 5, 20) as area_bonus,
           case when c.fresh then 0 else 10 end as stale_pen
      from c
  )
  select s.tanod_id, s.full_name,
         greatest(0, 100 - s.dist_pen - s.load_pen + s.area_bonus - s.stale_pen),
         round(s.metres)::integer, s.active, s.nearby, s.fresh,
         jsonb_build_array(
           jsonb_build_object('factor', 'distance',
             'detail', case when s.metres is null then 'no location yet' else round(s.metres) || ' m away' end,
             'points', -s.dist_pen),
           jsonb_build_object('factor', 'workload', 'detail', s.active || ' job(s) in hand', 'points', -s.load_pen),
           jsonb_build_object('factor', 'knows the area', 'detail', s.nearby || ' case(s) closed within 300 m, last 90 days',
             'points', s.area_bonus),
           -- One reading at a time, never tracking (live tracking was removed
           -- in 0072): the age of the tanod's last reading.
           jsonb_build_object('factor', 'location', 'detail', case
               when s.fix_at is null then 'no location yet'
               when s.fix_at > now() - interval '2 minutes' then 'last reading just now'
               when s.fix_at > now() - interval '2 hours'
                 then 'last reading ' || floor(extract(epoch from now() - s.fix_at) / 60) || ' min ago'
               else 'last reading over 2 hours ago' end,
             'points', -s.stale_pen))
    from s
   order by 3 desc, s.metres nulls last;
end $$;

revoke all on function public.smart_tanod_ranking(uuid) from public, anon;
grant execute on function public.smart_tanod_ranking(uuid) to authenticated;

-- ---------- 4. how long it usually takes --------------------------------------

/** From this barangay's own closed cases of the kind in the last 180 days:
    the median and the 80th percentile, in hours. Under 5 cases, it falls
    back to the SLA's target. Only totals leave the function, so residents
    may call it for their own report's kind. */
create or replace function public.smart_eta(p_category public.complaint_category)
returns table (median_hours numeric, p80_hours numeric, cases integer, sla_hours integer, basis text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with done as (
    select extract(epoch from (r.resolved_at - r.created_at)) / 3600.0 as h
      from public.reports r
     where r.category = p_category and r.resolved_at is not null and r.deleted_at is null
       and r.resolved_at > now() - interval '180 days'
  ), st as (
    select count(*)::integer as n,
           percentile_cont(0.5) within group (order by h) as med,
           percentile_cont(0.8) within group (order by h) as p80
      from done
  )
  select case when st.n >= 5 then round(st.med::numeric, 1) else p.resolution_hours::numeric end,
         case when st.n >= 5 then round(st.p80::numeric, 1) else p.resolution_hours::numeric end,
         st.n, p.resolution_hours,
         case when st.n >= 5 then 'past cases' else 'target' end
    from st left join public.sla_policies p on p.category = p_category
$$;

revoke all on function public.smart_eta(public.complaint_category) from public, anon;
grant execute on function public.smart_eta(public.complaint_category) to authenticated;

-- ---------- score what is open now ---------------------------------------------

select public.smart_triage(id)
  from public.reports
 where deleted_at is null and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled');
