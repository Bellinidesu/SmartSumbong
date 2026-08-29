-- =============================================================
-- SmartSumbong — 0042 Hotspot cluster analytics
--
-- spatial.php already draws a heatmap (leaflet-heat) and clusters raw pin
-- markers above a count threshold (leaflet.markercluster) — both are
-- rendering aids, not analysis. Neither tells an admin "there have been 8
-- reports within a block of each other this quarter, mostly street
-- obstruction" without them squinting at the blur and eyeballing it
-- themselves. This migration does the actual spatial clustering in the
-- database, once, so the admin gets a ranked list instead of a vibe.
--
-- Approach: PostGIS's ST_ClusterDBSCAN, a real density-based clustering
-- algorithm — points within `eps` of each other (transitively) join the
-- same cluster; anything with fewer than `minpoints` neighbours within
-- that radius is noise and gets no cluster id at all. That "noise" half
-- is doing real work here: a single stray complaint two streets from
-- everything else is not a hotspot, and DBSCAN drops it rather than
-- forcing it into the nearest group the way k-means would.
--
-- eps = 45 metres, minpoints = 3, chosen for barangay scale: roughly a
-- short block/corner's worth of grouping distance, and three separate
-- filings before it is called a pattern rather than a coincidence. Both
-- are literal constants here, not settings — same call this codebase
-- already made for the 3-strike abuse threshold in 0040, for the same
-- reason: nobody asked for these to be barangay-tunable, and a constant
-- in a migration is easier to reason about than a settings row.
--
-- ST_ClusterDBSCAN needs a planar geometry with distances in real units,
-- not lat/lng degrees — reports.geom is geography(Point, 4326), so this
-- transforms to EPSG:3857 (Web Mercator, metres) first. Mercator distorts
-- distance with latitude, but Barangay 183 spans a few hundred metres at
-- ~14.5°N, where that distortion is negligible — nothing here needs
-- survey-grade accuracy, just "these points are close together."
--
-- Deliberately NOT security definer, matching dashboard_metrics (0012):
-- it runs with the caller's rights, so row level security still decides
-- which reports are ever visible to cluster. An admin gets barangay-wide
-- hotspots; a resident or tanod calling the same function only ever
-- clusters the reports reports_resident_read already lets them see —
-- harmless, not a new surface, no separate admin-only grant needed.
-- =============================================================

set search_path = public, extensions;

create or replace function public.report_hotspots(
  p_from     timestamptz,
  p_to       timestamptz,
  p_category complaint_category default null)
returns table (
  cluster_id   integer,
  centroid_lat double precision,
  centroid_lng double precision,
  report_count integer,
  top_category complaint_category,
  first_at     timestamptz,
  last_at      timestamptz)
language sql stable set search_path = public, extensions as $$
  with scoped as (
    select r.category, r.created_at,
           st_transform(r.geom::geometry, 3857) as g3857
      from public.reports r
     where r.deleted_at is null
       and r.created_at >= p_from
       and r.created_at <  p_to
       and (p_category is null or r.category = p_category)
  ),
  clustered as (
    select *,
           st_clusterdbscan(g3857, eps := 45, minpoints := 3) over () as cid
      from scoped
  )
  select
    cid,
    st_y(st_transform(st_centroid(st_collect(g3857)), 4326)),
    st_x(st_transform(st_centroid(st_collect(g3857)), 4326)),
    count(*)::integer,
    mode() within group (order by category),
    min(created_at),
    max(created_at)
    from clustered
   where cid is not null   -- DBSCAN "noise": no cluster, not a hotspot
   group by cid
   order by count(*) desc
$$;

revoke execute on function public.report_hotspots(timestamptz, timestamptz, complaint_category) from public, anon;
grant  execute on function public.report_hotspots(timestamptz, timestamptz, complaint_category) to authenticated;

comment on function public.report_hotspots(timestamptz, timestamptz, complaint_category) is
  'Real spatial clustering (PostGIS ST_ClusterDBSCAN, 45m/3pts) over reports '
  'in a window, ranked by size. RLS-scoped like dashboard_metrics -- an '
  'admin sees barangay-wide hotspots, anyone else only ever clusters what '
  'reports_resident_read already lets them see.';

-- Verification. Run separately.
--
--   select * from public.report_hotspots(now() - interval '1 year', now(), null);
