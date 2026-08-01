-- =============================================================
-- SmartSumbong — 0012 Dashboard metrics
--
-- View Statistical Analytics Dashboard asks for six visuals off one
-- screen: reports per day, three counters, a resolution-status donut,
-- a category donut and a resolution-efficiency line. PostgREST can
-- filter and it can count, but it cannot group, so doing this over the
-- REST API means eight or nine round trips and the arithmetic done in
-- PHP — which is both slow over a barangay connection and a second
-- place for the definition of "overdue" to drift out of sync with the
-- sweeps that actually escalate things.
--
-- So: one call, one pass, one definition of each term.
--
-- Deliberately NOT security definer. It runs with the caller's rights,
-- so row level security still decides which reports are counted. An
-- admin sees the barangay; anyone else sees their own and learns
-- nothing they could not already read.
-- =============================================================

set search_path = public, extensions;

create or replace function public.dashboard_metrics(
  p_from timestamptz,
  p_to   timestamptz)
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
           -- "Finished" covers resolved and closed alike: a complaint
           -- the barangay has dealt with, whether or not the resident
           -- has since confirmed it.
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
             -- Finished after the deadline it was given.
             when s.is_done and s.due_at is not null
                  and s.finished_at > s.due_at              then 'late'
             -- Finished in time, or finished with no deadline set.
             when s.is_done                                then 'done'
             -- Still open and the deadline has passed.
             when s.due_at is not null and now() > s.due_at then 'overdue'
             -- Still open, still inside the window. Rejected complaints
             -- are not work in progress and are counted separately.
             when s.status = 'rejected'                    then 'rejected'
             else                                               'processing'
           end as bucket
      from scoped s
  )
  select json_build_object(

    'period', json_build_object('from', p_from, 'to', p_to),

    'total', (select count(*) from scoped),

    -- Reports filed per calendar day, Manila time, with empty days
    -- present as zeroes so the line does not lie by skipping them.
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

    -- The three counters. Resolved and escalated are counts; the third
    -- is every complaint whose deadline has passed with nobody having
    -- finished it, which is the number an admin actually needs to see.
    'tiles', (
      select json_build_object(
               'resolved',  count(*) filter (where bucket in ('done', 'late')),
               'escalated', count(*) filter (where escalation_level > 0),
               'overdue',   count(*) filter (where bucket = 'overdue'))
        from classified
    ),

    -- Resolution efficiency: for each day, the mean hours between filing
    -- and finishing for the complaints finished that day, against the
    -- policy window they were held to. Two lines, one chart — "we took
    -- 31 hours" means nothing without "we were allowed 48".
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
           group by 1) e on e.day = d.day::date
    )

  ) into v_out;

  return v_out;
end $$;

revoke execute on function public.dashboard_metrics(timestamptz, timestamptz) from public, anon;
grant  execute on function public.dashboard_metrics(timestamptz, timestamptz) to authenticated;

comment on function public.dashboard_metrics(timestamptz, timestamptz) is
  'Every figure on the analytics dashboard in one pass. Runs with the caller''s rights, so RLS decides what is counted.';
