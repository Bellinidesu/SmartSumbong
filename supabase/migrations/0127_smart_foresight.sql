-- 0127: SMART foresight: looking ahead, and remembering (10 Oct 2026).
--
-- Still rules and plain statistics, every result with its reasons
-- (docs/SMART.md, sections 11-15):
--
--   storm mode        one switch for a typhoon or heavy-rain warning: hazard
--                     zones and flood, live-wire and collapse words count
--                     double until it ends (by hand or after its hours).
--   deadline risk     an assigned case that will probably miss its deadline,
--                     from how long this kind of case takes here and how
--                     busy its tanod is; the admins hear it before, not after.
--   spikes            a kind of complaint at well above its usual weekly
--                     count (this week against the 8 weeks before).
--   similar cases     closed cases most like this one, and how they were
--                     resolved; and the outside office this kind of case
--                     usually goes to.
--   morning digest    one message to the admins at 07:00: what is open,
--                     urgent, overdue, at risk, spiking and recurring.

set search_path = public, extensions;

-- ---------- storm mode ------------------------------------------------------------

alter table public.smart_rules
  add column storm_mode       boolean     not null default false,
  add column storm_until      timestamptz,
  add column storm_reason     text,
  add column storm_multiplier numeric(3, 1) not null default 2 check (storm_multiplier between 1 and 3),
  add column storm_labels     text[]      not null default '{flooding,"live wire",collapse}',
  add column spike_min_reports smallint   not null default 4 check (spike_min_reports >= 2),
  add column digest_enabled   boolean     not null default true;

create or replace function public._smart_score(
  p_category    public.complaint_category,
  p_subject     text,
  p_description text,
  p_geom        geography,
  p_at          timestamptz,
  p_resident    uuid,
  p_exclude     uuid default null)
returns table (score smallint, level text, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  k       public.smart_rules%rowtype;
  v_text  text := coalesce(p_subject, '') || ' ' || coalesce(p_description, '');
  v_read  jsonb;
  v_hit   jsonb;
  v_pts   integer;
  v_kw    integer := 0;
  v_score integer := 0;
  v_why   jsonb := '[]';
  v_lvl   smallint;
  v_haz   text;
  v_n     integer;
  v_hour  integer;
  g       jsonb;
  v_boost boolean;
  v_stormed boolean := false;
begin
  select * into k from public.smart_rules where id = 1;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.pos), '[]') into v_read from public._smart_read(v_text) r;

  -- the kind of complaint
  v_pts := coalesce((k.category_points ->> p_category::text)::integer, 0);
  v_score := v_pts;
  v_why := v_why || jsonb_build_object('factor', 'category', 'detail', p_category::text, 'points', v_pts);

  -- words, each group once, read as Taglish
  for g in select * from jsonb_array_elements(k.keyword_groups) loop
    v_hit := public._smart_words_hit(g -> 'words', v_text, v_read);
    if v_hit is null then continue; end if;
    if coalesce((v_hit ->> 'negated')::boolean, false) then
      v_why := v_why || jsonb_build_object('factor', 'not counted', 'detail', g ->> 'label',
                                           'points', 0, 'matched', v_hit ->> 'matched', 'how', 'negated');
      continue;
    end if;
    v_pts := (g ->> 'points')::integer;
    v_boost := k.storm_mode and (g ->> 'label') = any (k.storm_labels);
    if v_boost then v_pts := round(v_pts * k.storm_multiplier); v_stormed := true; end if;
    v_pts := least(v_pts, round(k.keyword_cap * case when k.storm_mode then k.storm_multiplier else 1 end)::integer - v_kw);
    if v_pts > 0 then
      v_kw := v_kw + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'words', 'detail', g ->> 'label', 'points', v_pts,
                                           'matched', v_hit ->> 'matched', 'how', v_hit ->> 'how')
                     || case when v_boost then jsonb_build_object('storm', true) else '{}'::jsonb end;
    end if;
  end loop;
  v_score := v_score + v_kw;

  if p_geom is not null then
    -- hazard zone
    select z.level, z.hazard into v_lvl, v_haz
      from public.hazard_zones z
     where st_intersects(z.geom, p_geom::geometry)
     order by z.level desc, z.hazard
     limit 1;
    if v_lvl is not null then
      v_pts := coalesce((k.hazard_points ->> v_lvl::text)::integer, 0);
      if k.storm_mode then v_pts := round(v_pts * k.storm_multiplier); v_stormed := true; end if;
      v_score := v_score + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'hazard zone',
        'detail', format('NOAH %s zone, %s', v_haz, (array['low', 'medium', 'high'])[v_lvl]), 'points', v_pts)
                     || case when k.storm_mode then jsonb_build_object('storm', true) else '{}'::jsonb end;
    end if;

    -- other residents, same kind, close in place and time
    select count(distinct o.resident_id) into v_n
      from public.reports o
     where o.id is distinct from p_exclude
       and o.category = p_category
       and o.resident_id is distinct from p_resident
       and o.deleted_at is null
       and o.status not in ('rejected', 'cancelled')
       and o.created_at between p_at - make_interval(hours => k.corroboration_hours)
                            and p_at + make_interval(hours => k.corroboration_hours)
       and st_dwithin(o.geom, p_geom, k.corroboration_metres);
    if v_n > 0 then
      v_pts := least(v_n * k.corroboration_points, k.corroboration_cap);
      v_score := v_score + v_pts;
      v_why := v_why || jsonb_build_object('factor', 'nearby reports',
        'detail', format('%s other resident%s reported this within %s m', v_n, case when v_n = 1 then '' else 's' end,
                         k.corroboration_metres),
        'points', v_pts);
    end if;
  end if;

  -- night, for safety kinds
  v_hour := extract(hour from p_at at time zone 'Asia/Manila');
  if (v_hour >= 22 or v_hour < 5)
     and p_category in ('peace_order_nuisance', 'public_safety_infrastructure', 'traffic_violation') then
    v_score := v_score + k.night_points;
    v_why := v_why || jsonb_build_object('factor', 'night', 'detail', format('filed at %s:00', v_hour),
                                         'points', k.night_points);
  end if;

  if v_stormed then
    v_why := v_why || jsonb_build_object('factor', 'storm mode', 'points', 0,
      'detail', format('Storm mode is on: hazard zones and %s words count x%s.',
                       array_to_string(k.storm_labels, ', '), k.storm_multiplier));
  end if;

  v_score := greatest(0, least(100, v_score));
  return query select v_score::smallint,
         case when v_score >= k.urgent_from then 'urgent'
              when v_score >= k.high_from   then 'high'
              when v_score >= k.normal_from then 'normal'
              else 'low' end,
         v_why;
end $$;

/** Admins: storm mode on (for p_hours, default 24) or off, with a reason.
    Re-scores every open report and tells the admins. */
create or replace function public.smart_storm_mode(p_on boolean, p_reason text default null, p_hours integer default 24)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer;
begin
  if not public.is_admin() and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only an administrator can switch storm mode.' using errcode = 'insufficient_privilege';
  end if;
  if p_on and char_length(coalesce(trim(p_reason), '')) < 3 then
    raise exception 'Say why, for example the PAGASA signal or rainfall warning.' using errcode = 'check_violation';
  end if;
  update public.smart_rules
     set storm_mode = p_on,
         storm_until = case when p_on then now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 168))) end,
         storm_reason = case when p_on then left(trim(p_reason), 200) end,
         updated_at = now(), updated_by = auth.uid()
   where id = 1;
  select count(*) into v_n from (
    select public.smart_triage(id) from public.reports
     where deleted_at is null and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')) x;
  perform public._notify_admins(case when p_on
    then format('SMART: storm mode is on until %s (%s). Flood-zone and flood, live-wire and collapse reports count double; %s open reports re-scored.',
                to_char((select storm_until from public.smart_rules where id = 1) at time zone 'Asia/Manila', 'Mon DD HH24:MI'),
                left(trim(p_reason), 200), v_n)
    else format('SMART: storm mode is off; %s open reports re-scored.', v_n) end);
  return v_n;
end $$;

revoke all on function public.smart_storm_mode(boolean, text, integer) from public, anon;
grant execute on function public.smart_storm_mode(boolean, text, integer) to authenticated;

-- ---------- deadline risk -------------------------------------------------------------

/** Open cases with a deadline that will probably miss it. high: even a
    typical case of this kind would not finish in the time left. medium: a
    slow one would not (the 80th percentile), or the tanod has 3 or more
    jobs in hand. Times from smart_eta (past cases, or the SLA target). */
create or replace function public._smart_deadline_risk()
returns table (report_id uuid, tracking_id text, due_at timestamptz, hours_left numeric,
               typical_hours numeric, slow_hours numeric, tanod_jobs integer, risk text, reasons jsonb)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with open_cases as (
    select r.id, r.tracking_id, r.category, r.created_at, r.due_at,
           extract(epoch from r.due_at - now()) / 3600.0 as left_h,
           extract(epoch from now() - r.created_at) / 3600.0 as elapsed_h,
           (select max((select count(*) from public.dispatches d2
                         where d2.tanod_id = d.tanod_id and d2.state in ('assigned', 'accepted')))
              from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'))::integer as jobs
      from public.reports r
     where r.deleted_at is null and r.due_at is not null and r.due_at > now()
       and r.resolved_at is null
       and r.status in ('validated', 'assigned', 'in_progress', 'offline_investigation')
  ), est as (
    select o.*, e.median_hours as typ, e.p80_hours as slow, e.basis
      from open_cases o cross join lateral public.smart_eta(o.category) e
  ), judged as (
    select e.*,
           case when e.typ is not null and e.left_h < e.typ - e.elapsed_h then 'high'
                when (e.slow is not null and e.left_h < e.slow - e.elapsed_h) or coalesce(e.jobs, 0) >= 3 then 'medium'
           end as risk
      from est e
  )
  select j.id, j.tracking_id, j.due_at, round(j.left_h::numeric, 1), j.typ, j.slow, coalesce(j.jobs, 0), j.risk,
         jsonb_build_array(
           jsonb_build_object('factor', 'time left', 'detail', round(j.left_h::numeric, 1) || ' h to the deadline'),
           jsonb_build_object('factor', 'usual time',
             'detail', format('%s cases here usually take %s h (slow ones %s h); %s h have passed',
                              case when j.basis = 'past cases' then 'Such' else 'The target for such' end,
                              j.typ, j.slow, round(j.elapsed_h::numeric, 1))))
         || case when coalesce(j.jobs, 0) >= 3
              then jsonb_build_array(jsonb_build_object('factor', 'tanod load', 'detail', j.jobs || ' jobs in hand'))
              else '[]'::jsonb end
    from judged j
   where j.risk is not null
   order by j.risk = 'high' desc, j.left_h
$$;

revoke all on function public._smart_deadline_risk() from public, anon, authenticated;

create or replace function public.smart_deadline_risk()
returns table (report_id uuid, tracking_id text, due_at timestamptz, hours_left numeric,
               typical_hours numeric, slow_hours numeric, tanod_jobs integer, risk text, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see deadline risk.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_deadline_risk();
end $$;

revoke all on function public.smart_deadline_risk() from public, anon;
grant execute on function public.smart_deadline_risk() to authenticated;

-- ---------- spikes ------------------------------------------------------------------------

/** Kinds of complaint well above their usual week: at least
    spike_min_reports in the last 7 days, at least double the weekly average
    of the 8 weeks before, and at least 3 standard deviations above it
    (Poisson). The most common place label this week is given for context. */
create or replace function public._smart_spikes()
returns table (category public.complaint_category, this_week integer, usual numeric,
               times_usual numeric, place text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select * from public.smart_rules where id = 1),
       counts as (
         select r.category,
                count(*) filter (where r.created_at > now() - interval '7 days')::integer as wk,
                (count(*) filter (where r.created_at <= now() - interval '7 days'
                                    and r.created_at > now() - interval '63 days'))::numeric / 8 as base,
                mode() within group (order by r.location_label) filter (where r.created_at > now() - interval '7 days') as place
           from public.reports r
          where r.deleted_at is null and r.status not in ('rejected', 'cancelled')
            and r.created_at > now() - interval '63 days'
          group by r.category
       )
  select c.category, c.wk, round(c.base, 1),
         round(c.wk / greatest(c.base, 0.5), 1), c.place
    from counts c, k
   where c.wk >= k.spike_min_reports
     and c.wk >= 2 * c.base
     and (c.wk - c.base) / sqrt(greatest(c.base, 0.5)) >= 3
   order by c.wk / greatest(c.base, 0.5) desc
$$;

revoke all on function public._smart_spikes() from public, anon, authenticated;

create or replace function public.smart_spikes()
returns table (category public.complaint_category, this_week integer, usual numeric,
               times_usual numeric, place text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see spikes.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_spikes();
end $$;

revoke all on function public.smart_spikes() from public, anon;
grant execute on function public.smart_spikes() to authenticated;

-- ---------- similar past cases, and where such cases go ------------------------------------

/** Up to 3 finished cases of the same kind from the last year most like
    this one (same words as SMART reads them, or close by), with how each
    ended: the outside office it went to, the closing remark, the tanod's
    field report, and how many days it took. */
create or replace function public._smart_similar_cases(p_report uuid)
returns table (report_id uuid, tracking_id text, similarity real, metres integer, days_to_resolve numeric,
               referred_to text, closing_remark text, field_report text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with r as (select rp.*, public._smart_concepts(rp.subject || ' ' || rp.description) as concepts
               from public.reports rp where rp.id = p_report),
       pool as (
         select o.*, st_distance(o.geom, r.geom) as d,
                extensions.similarity(lower(o.subject || ' ' || o.description), lower(r.subject || ' ' || r.description)) as raw_sim
           from r, public.reports o
          where o.id <> r.id and o.category = r.category and o.deleted_at is null
            and (o.resolved_at is not null or o.referred_at is not null or o.status in ('resolved', 'closed'))
            and o.created_at > now() - interval '365 days'
          order by extensions.similarity(lower(o.subject || ' ' || o.description), lower(r.subject || ' ' || r.description))
                   + case when st_dwithin(o.geom, r.geom, 300) then 0.2 else 0 end desc
          limit 15
       ),
       scored as (
         select p.*, greatest(p.raw_sim,
                  case when r.concepts <> '' then extensions.similarity(public._smart_concepts(p.subject || ' ' || p.description), r.concepts) else 0 end
                ) + case when p.d <= 300 then 0.1 else 0 end as sim
           from pool p, r
       )
  select s.id, s.tracking_id, least(s.sim, 1)::real, round(s.d)::integer,
         round((extract(epoch from coalesce(s.resolved_at, s.referred_at) - s.created_at) / 86400.0)::numeric, 1),
         s.referred_to,
         (select l.remark from public.status_logs l
           where l.report_id = s.id and l.new_status in ('resolved', 'closed') and l.remark is not null
           order by l.created_at desc limit 1),
         (select d.field_report_text from public.dispatches d
           where d.report_id = s.id and d.field_report_text is not null order by d.created_at desc limit 1)
    from scored s
   where s.sim >= 0.25 or s.d <= 100
   order by s.sim desc, s.d
   limit 3
$$;

revoke all on function public._smart_similar_cases(uuid) from public, anon, authenticated;

/** The outside office this kind of case usually goes to: the most common
    referred_to in the last year, if it took at least 3 cases and at least
    40% of those referred. */
create or replace function public._smart_referral(p_category public.complaint_category)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  with refs as (
    select trim(r.referred_to) as office, count(*) as n
      from public.reports r
     where r.category = p_category and r.deleted_at is null and r.referred_to is not null
       and r.created_at > now() - interval '365 days'
     group by lower(trim(r.referred_to)), trim(r.referred_to)
  ), tot as (select coalesce(sum(n), 0) as all_refs from refs)
  select jsonb_build_object('office', f.office, 'cases', f.n, 'of_referred', t.all_refs,
                            'detail', format('Usually referred to %s (%s of %s referred cases this year).', f.office, f.n, t.all_refs))
    from refs f, tot t
   where f.n >= 3 and f.n >= 0.4 * t.all_refs
   order by f.n desc
   limit 1
$$;

revoke all on function public._smart_referral(public.complaint_category) from public, anon, authenticated;

/** Admins: similar past cases of a report. */
create or replace function public.smart_similar_cases(p_report uuid)
returns table (report_id uuid, tracking_id text, similarity real, metres integer, days_to_resolve numeric,
               referred_to text, closing_remark text, field_report text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see similar cases.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_similar_cases(p_report);
end $$;

revoke all on function public.smart_similar_cases(uuid) from public, anon;
grant execute on function public.smart_similar_cases(uuid) to authenticated;

-- ---------- the case card, with memory and deadline risk ------------------------------------

create or replace function public.smart_case_card(p_report uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  r public.reports%rowtype;
  t public.report_triage%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see SMART results.' using errcode = 'insufficient_privilege';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then return null; end if;
  select * into t from public.report_triage where report_id = p_report;

  return jsonb_build_object(
    'score', t.score,
    'level', t.level,
    'effective_level', t.effective_level,
    'reasons', coalesce(t.reasons, '[]'),
    'computed_at', t.computed_at,
    'override', case when t.override_level is null then null else jsonb_build_object(
        'level', t.override_level, 'reason', t.override_reason, 'at', t.override_at,
        'by', (select public.display_name(u.full_name) from public.users u where u.id = t.override_by)) end,
    'duplicates', coalesce((select jsonb_agg(to_jsonb(d)) from public.smart_duplicates_of(p_report) d), '[]'),
    'eta', (select to_jsonb(e) from public.smart_eta(r.category) e),
    'category_hint', public._smart_category_hint(r.category, r.subject, r.description),
    'tanods', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select * from public.smart_tanod_ranking(p_report) limit 3) x), '[]'),
    'similar', coalesce((select jsonb_agg(to_jsonb(s)) from public._smart_similar_cases(p_report) s), '[]'),
    'referral', public._smart_referral(r.category),
    'deadline_risk', (select to_jsonb(d) from public._smart_deadline_risk() d where d.report_id = p_report),
    'storm_mode', (select storm_mode from public.smart_rules where id = 1));
end $$;

-- ---------- the morning digest ---------------------------------------------------------------

/** The text of the morning message: what needs the barangay today. */
create or replace function public._smart_digest_text()
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_open integer; v_urgent integer; v_high integer; v_overdue integer; v_today integer;
  v_risk integer; v_new integer; v_rec integer; v_storm boolean;
  v_spike record;
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v text;
begin
  select count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
         count(*) filter (where r.due_at < now() and r.resolved_at is null
                            and r.status in ('validated', 'assigned', 'in_progress', 'offline_investigation')),
         count(*) filter (where (r.due_at at time zone 'Asia/Manila')::date = v_day and r.resolved_at is null),
         count(*) filter (where (r.created_at at time zone 'Asia/Manila')::date = v_day - 1)
    into v_open, v_overdue, v_today, v_new
    from public.reports r where r.deleted_at is null;
  select count(*) filter (where t.effective_level = 'urgent'), count(*) filter (where t.effective_level = 'high')
    into v_urgent, v_high
    from public.report_triage t join public.reports r on r.id = t.report_id
   where r.deleted_at is null and r.status in ('pending_review', 'validated')
     and not exists (select 1 from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'));
  select count(*) into v_risk from public._smart_deadline_risk() where risk = 'high';
  select count(*) into v_rec from public._smart_patterns(null) where still_open > 0;
  select * into v_spike from public._smart_spikes() limit 1;
  select storm_mode into v_storm from public.smart_rules where id = 1;

  v := format('SMART morning digest, %s. Open: %s. Waiting for a tanod: %s urgent, %s high. Overdue: %s. Due today: %s. '
              || 'Likely to miss the deadline: %s. Filed yesterday: %s. Recurring problems still open: %s.',
              to_char(v_day, 'Mon DD'), v_open, v_urgent, v_high, v_overdue, v_today, v_risk, v_new, v_rec);
  if v_spike.category is not null then
    v := v || format(' Spike: %s, %s this week (usually %s)%s.', replace(v_spike.category::text, '_', ' '),
                     v_spike.this_week, v_spike.usual, coalesce(', mostly ' || v_spike.place, ''));
  end if;
  if v_storm then v := v || ' Storm mode is on.'; end if;
  return v;
end $$;

revoke all on function public._smart_digest_text() from public, anon, authenticated;

/** Admins: the digest as it would read now (Settings, or to check it). */
create or replace function public.smart_digest_preview()
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the digest.' using errcode = 'insufficient_privilege';
  end if;
  return public._smart_digest_text();
end $$;

revoke all on function public.smart_digest_preview() from public, anon;
grant execute on function public.smart_digest_preview() to authenticated;

create or replace function public.smart_morning_digest()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if (select digest_enabled from public.smart_rules where id = 1) then
    perform public._notify_admins(public._smart_digest_text());
  end if;
end $$;

revoke all on function public.smart_morning_digest() from public, anon, authenticated;

-- 07:00 in Manila is 23:00 UTC the day before.
select cron.schedule('smart-morning-digest', '0 23 * * *', $$ select public.smart_morning_digest() $$);

-- ---------- the watcher, looking ahead ---------------------------------------------------------

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
  v_key text;
begin
  select * into k from public.smart_rules where id = 1;

  -- storm mode ends on its own
  if k.storm_mode and k.storm_until is not null and k.storm_until < now() then
    update public.smart_rules set storm_mode = false, storm_until = null, storm_reason = null where id = 1;
    perform public.smart_triage(id) from public.reports
     where deleted_at is null and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled');
    perform public._notify_admins('SMART: storm mode has ended; open reports re-scored.');
    v_sent := v_sent + 1;
    select * into k from public.smart_rules where id = 1;
  end if;

  -- urgent and high reports waiting for a tanod
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

  -- cases likely to miss their deadline (high risk), told once
  for r in
    select d.* from public._smart_deadline_risk() d
     where d.risk = 'high'
       and not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = 'deadline:' || d.report_id)
     limit 50
  loop
    insert into public.notifications (user_id, kind, report_id, message)
    select a.id, 'sla_warning', r.report_id,
           format('SMART: %s will probably miss its deadline (%s h left; such cases usually take %s h).',
                  r.tracking_id, r.hours_left, r.typical_hours)
      from public.users a
     where a.role = 'admin' and not coalesce(a.is_suspended, false);
    insert into public.smart_patterns_seen (pattern_key, reports) values ('deadline:' || r.report_id, 1);
    v_sent := v_sent + 1;
  end loop;

  -- recurring problems not seen before
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

  -- spikes, once per kind per week
  for r in select s.* from public._smart_spikes() s loop
    v_key := 'spike:' || r.category || ':' || to_char(now() at time zone 'Asia/Manila', 'IYYY-IW');
    if not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = v_key) then
      insert into public.smart_patterns_seen (pattern_key, reports) values (v_key, r.this_week);
      perform public._notify_admins(format(
        'SMART: spike. %s %s reports in the last 7 days, %s times the usual week (%s)%s.',
        r.this_week, replace(r.category::text, '_', ' '), r.times_usual, r.usual,
        coalesce('; mostly ' || r.place, '')));
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_sent;
end $$;

comment on table public.smart_patterns_seen is
  '0123: what the watcher has already told the admins: recurring problems (kind and centre to ~100 m); since 0127 also spikes (spike:<kind>:<week>) and deadline risks (deadline:<report id>).';

-- ---------- speed: no JIT for SMART's short queries -------------------------------------
-- nearest_available_tanod returns a handful of rows, but the planner
-- assumed 1,000, which pushed the tanod ranking past jit_above_cost: each
-- call then spent ~55 ms compiling a query that runs in 2 ms. The real
-- estimate, and JIT off for every SMART function (all short, small
-- queries), keep the case card around 70 ms on 50,000 reports.
alter function public.nearest_available_tanod(uuid) rows 10;

do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname ~ '^_?smart_'
  loop
    execute format('alter function %s set jit = off', f);
  end loop;
end $$;
