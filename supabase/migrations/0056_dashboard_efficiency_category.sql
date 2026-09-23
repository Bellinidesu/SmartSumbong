-- =============================================================
-- SmartSumbong — 0056 Resolution Efficiency category filter
--
-- Rose's feedback: "for resolution efficiency, include the category
-- filter para makita ng admin kung gaano kabilis maresolve yung complaint
-- depending sa category" -- the dashboard should be able to show how fast
-- one category resolves, not only the whole barangay's blended average.
--
-- dashboard.php has carried the filter UI (the eff_category select, the
-- "Showing X only" note, the realtime EFF_CATEGORY variable) since it was
-- first built, always calling dashboard_metrics() with a p_category
-- argument -- referencing this migration by number in its own comment
-- ("0056") before it existed. Only the Resolution Efficiency line is
-- scoped by it; every other visual on the dashboard (the daily chart, the
-- three tiles, both donuts) stays computed over the whole month exactly as
-- 0012 left it, which is also what dashboard.php's own comment already
-- promises callers.
--
-- New overload, not a compatible in-place change: adding a third parameter
-- changes dashboard_metrics()'s signature, so the old 2-arg version is
-- dropped first -- otherwise PostgREST would have two candidate functions
-- for a 2-arg call (dashboard.php's own previous-month comparison, which
-- never passes p_category) and refuse to pick one, the same ambiguity
-- 0055 avoids for promote_to_admin().
-- =============================================================

set search_path = public, extensions;

drop function if exists public.dashboard_metrics(timestamptz, timestamptz);

create or replace function public.dashboard_metrics(
  p_from     timestamptz,
  p_to       timestamptz,
  p_category text default null)
returns json
language plpgsql stable set search_path = public, extensions as $$
declare
  v_out json;
begin
  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'Invalid reporting period';
  end if;

  with scoped as (
    select r.*,
           (r.status in ('resolved', 'closed', 'archived'))         as is_done,
           coalesce(r.resolved_at, r.closed_at)                     as finished_at
      from public.reports r
     where r.deleted_at is null
       and r.created_at >= p_from
       and r.created_at <  p_to
  ),
  classified as (
    select s.*,
           case
             when s.is_done and s.due_at is not null
                  and s.finished_at > s.due_at              then 'late'
             when s.is_done                                then 'done'
             when s.due_at is not null and now() > s.due_at then 'overdue'
             when s.status = 'rejected'                    then 'rejected'
             else                                               'processing'
           end as bucket
      from scoped s
  )
  select json_build_object(

    'period', json_build_object('from', p_from, 'to', p_to),

    'total', (select count(*) from scoped),

    'daily', (
      select coalesce(json_agg(json_build_object(
               'day',   to_char(d.day, 'YYYY-MM-DD'),
               'label', to_char(d.day, 'FMDD'),
               'filed', coalesce(c.n, 0)) order by d.day), '[]'::json)
        from generate_series(
               (p_from at time zone 'Asia/Manila')::date,
               (p_to   at time zone 'Asia/Manila')::date - 1,
               interval '1 day') as d(day)
        left join (
          select (created_at at time zone 'Asia/Manila')::date as day, count(*) as n
            from scoped group by 1) c on c.day = d.day::date
    ),

    'resolution_status', (
      select json_build_object(
               'done',       count(*) filter (where bucket = 'done'),
               'overdue',    count(*) filter (where bucket = 'overdue'),
               'late',       count(*) filter (where bucket = 'late'),
               'processing', count(*) filter (where bucket = 'processing'),
               'rejected',   count(*) filter (where bucket = 'rejected'))
        from classified
    ),

    'categories', (
      select coalesce(json_agg(json_build_object(
               'category', category, 'n', n) order by n desc, category), '[]'::json)
        from (select category::text as category, count(*) as n
                from scoped group by 1) t
    ),

    'tiles', (
      select json_build_object(
               'resolved',  count(*) filter (where bucket in ('done', 'late')),
               'escalated', count(*) filter (where escalation_level > 0),
               'overdue',   count(*) filter (where bucket = 'overdue'))
        from classified
    ),

    -- The only section p_category scopes. Every other key above is
    -- computed over the whole month regardless of it, matching
    -- dashboard.php's own stated behaviour.
    'efficiency', (
      select coalesce(json_agg(json_build_object(
               'day',     to_char(d.day, 'YYYY-MM-DD'),
               'label',   to_char(d.day, 'FMDD'),
               'actual',  e.avg_hours,
               'allowed', e.avg_target,
               'n',       coalesce(e.n, 0)) order by d.day), '[]'::json)
        from generate_series(
               (p_from at time zone 'Asia/Manila')::date,
               (p_to   at time zone 'Asia/Manila')::date - 1,
               interval '1 day') as d(day)
        left join (
          select (c.finished_at at time zone 'Asia/Manila')::date as day,
                 count(*) as n,
                 round(avg(extract(epoch from (c.finished_at - c.created_at)) / 3600)::numeric, 1)
                   as avg_hours,
                 round(avg(p.resolution_hours)::numeric, 1) as avg_target
            from classified c
            join public.sla_policies p on p.category = c.category
           where c.finished_at is not null
             and (p_category is null or c.category::text = p_category)
           group by 1) e on e.day = d.day::date
    )

  ) into v_out;

  return v_out;
end $$;

revoke execute on function public.dashboard_metrics(timestamptz, timestamptz, text) from public, anon;
grant  execute on function public.dashboard_metrics(timestamptz, timestamptz, text) to authenticated;

comment on function public.dashboard_metrics(timestamptz, timestamptz, text) is
  'Every figure on the analytics dashboard in one pass. p_category scopes only the resolution-efficiency line; everything else stays whole-month. Runs with the caller''s rights, so RLS decides what is counted.';
