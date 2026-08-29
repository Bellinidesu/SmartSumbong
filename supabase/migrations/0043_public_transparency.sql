-- =============================================================
-- SmartSumbong — 0043 Public transparency dashboard
--
-- Everything the admin portal shows is behind require_admin() — for good
-- reason, most of it is a specific resident's ID photo, phone number, or
-- complaint text. But two things dashboard_metrics() and spatial.php
-- already compute are genuinely public-safe: how the barangay as a whole
-- is doing (counts, categories, resolution time vs. SLA) and where
-- problems recur in general terms. Nothing in this migration is new
-- analysis — it is a second, deliberately narrower surface for numbers
-- the admin dashboard already trusts, reachable with no login at all.
--
-- Two functions, two different privacy postures:
--
--   public_transparency_stats() is dashboard_metrics()'s shape (total,
--   daily, resolution_status, categories, tiles, efficiency) with the
--   report text and photos never having been in that shape to begin
--   with — it was already aggregate-only. Duplicated as its own function
--   rather than reusing dashboard_metrics() directly so that a future
--   admin-only field added to the authenticated dashboard can never leak
--   to anon just by forgetting this second consumer exists.
--
--   public_report_heat() is the genuinely sensitive one: a location is
--   frequently near the complainant's own home, and an anonymous
--   complaint's anonymity is worth nothing if the public map can still
--   point at the one house it came from. So this never returns a report's
--   real coordinates, an id, a tracking number, or anything else tied to
--   one filing. It snaps every point onto a fixed ~44m grid (a value
--   nobody chose, not derived from the data) and then throws away any
--   cell with fewer than 3 reports in it — decided with the user
--   (29 Aug 2026): "aggregated heat only," no individual pins, low-count
--   cells suppressed so a single complaint can never be the thing the
--   public map is pointing at.
--
-- Both are SECURITY DEFINER and granted to anon — the one deliberate use
-- of that pattern for an unauthenticated caller in this schema. Every
-- other security definer function in this codebase gates on is_admin()
-- or auth.uid() internally; these two gate on privacy-by-aggregation
-- instead, since there is no caller identity to check RLS against at all.
-- =============================================================

set search_path = public, extensions;

-- ---------- aggregate counts, categories, efficiency -------------

create or replace function public.public_transparency_stats(
  p_from timestamptz,
  p_to   timestamptz)
returns json
language plpgsql security definer set search_path = public, extensions as $$
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
               'overdue',   count(*) filter (where bucket = 'overdue'))
        from classified
    ),

    -- Same efficiency shape as dashboard_metrics -- "we took 31 hours"
    -- means nothing without "we were allowed 48", and that comparison is
    -- exactly the kind of thing a transparency page exists to show.
    'efficiency', (
      select json_build_object(
               'avg_hours',  round(avg(extract(epoch from (c.finished_at - c.created_at)) / 3600)::numeric, 1),
               'avg_target', round(avg(p.resolution_hours)::numeric, 1),
               'n',          count(*))
        from classified c
        join public.sla_policies p on p.category = c.category
       where c.finished_at is not null
    )

  ) into v_out;

  return v_out;
end $$;

revoke execute on function public.public_transparency_stats(timestamptz, timestamptz) from public;
grant  execute on function public.public_transparency_stats(timestamptz, timestamptz) to anon, authenticated;

comment on function public.public_transparency_stats(timestamptz, timestamptz) is
  'Public, no-login barangay-wide totals for the transparency page. Same '
  'aggregate shape as dashboard_metrics, deliberately duplicated rather '
  'than shared so an admin-only field added there can never leak here by '
  'accident. Never touches report text, photos, or resident identity -- '
  'none of that was in this shape to begin with.';

-- ---------- suppressed grid heat, never individual pins -----------

create or replace function public.public_report_heat(
  p_from     timestamptz,
  p_to       timestamptz,
  p_category complaint_category default null)
returns table (
  cell_lat double precision,
  cell_lng double precision,
  n        integer)
language sql stable security definer set search_path = public, extensions as $$
  select cell_lat, cell_lng, count(*)::integer as n
    from (
      select
        -- Fixed ~44m grid, snapped from the real coordinate and then
        -- discarded -- the returned point is the grid cell's own centre,
        -- never a location derived from where any actual report sat.
        round(r.latitude  / 0.0004) * 0.0004 as cell_lat,
        round(r.longitude / 0.0004) * 0.0004 as cell_lng
        from public.reports r
       where r.deleted_at is null
         and r.created_at >= p_from
         and r.created_at <  p_to
         and (p_category is null or r.category = p_category)
    ) gridded
   group by cell_lat, cell_lng
  -- The suppression. A cell with 1 or 2 reports in it is still, in
  -- practice, one or two specific complaints -- exactly what "no
  -- individual pins" was meant to prevent. Below this line the cell is
  -- simply absent from the result, not shown faintly or rounded to zero.
  having count(*) >= 3
$$;

revoke execute on function public.public_report_heat(timestamptz, timestamptz, complaint_category) from public;
grant  execute on function public.public_report_heat(timestamptz, timestamptz, complaint_category) to anon, authenticated;

comment on function public.public_report_heat(timestamptz, timestamptz, complaint_category) is
  'Public, no-login heat data. Never a real report coordinate, id, or '
  'tracking number -- every point is a fixed ~44m grid cell centre, and '
  'any cell with fewer than 3 reports is dropped entirely so a single '
  'complaint (often near its filer''s own home) can never be pinpointed '
  'from this page. Decided with the user 29 Aug 2026: aggregated heat '
  'only, no exception for "just this once."';

-- Verification. Run separately.
--
--   select public.public_transparency_stats(now() - interval '30 days', now());
--   select * from public.public_report_heat(now() - interval '1 year', now(), null);
--   -- confirm no cell below the threshold ever appears:
--   select min(n) from public.public_report_heat(now() - interval '5 years', now(), null);
