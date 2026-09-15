-- =============================================================
-- SmartSumbong — 0059 Live tanod position tracking + pathing heatmap
--
-- Ace (15 Sep 2026): "i want something riskier and fantastic to finally
-- implement / live barangay tanod position tracking and status / and
-- pathing heatmap of all tanods."
--
-- Four decisions locked in before writing this (AskUserQuestion):
--   1. Tracking runs only while a tanod is On Duty — no background
--      permission tier, reuses duty_status exactly as 0005 already gates
--      update_my_location() on it.
--   2. Location updates every 30 seconds while tracked (mobile-side
--      timer change; see tanod_home_screen.dart).
--   3. The admin "tanod paths" heatmap uses an admin-picked date range,
--      mirroring the existing hotspot month-picker in spatial.php.
--   4. Raw pings are kept 30 days, then purged by a cron job.
--
-- This does NOT reinvent live position. 0005 already gave every tanod a
-- single current fix (users.last_geom / last_location_at, updated by
-- update_my_location(), on-duty-gated, 15-minute freshness window via
-- location_is_fresh()) — that is exactly what nearest_available_tanod()
-- already trusts for dispatch. What's missing for this feature is:
--   (a) a way for an admin to actually SEE those current fixes on the
--       map (there is no admin-facing read of last_geom at all today —
--       it is dispatch-internal), and
--   (b) a HISTORY of positions, since last_geom is overwritten in place
--       on every update and cannot answer "where has this tanod been."
--
-- So: update_my_location() is extended (create or replace, same
-- signature — no caller elsewhere needs to change) to also append a row
-- to a new tanod_locations history table, on the same on-duty gate it
-- already enforces. Two new admin-only reads are added on top of that:
-- tanod_live_positions() (current fix per tanod, for the live map layer)
-- and tanod_path_heatmap() (raw points over an admin-chosen range, for
-- the pathing heatmap). Both are SECURITY DEFINER with an explicit
-- is_admin() guard, because tanod_locations itself carries RLS with no
-- policies at all (deny-by-default, same idiom as other tables gated
-- purely through functions) — a security-invoker function here would
-- just see zero rows for everyone, admin included.
--
-- PRIVACY: this is precise, admin-visible movement history of an
-- employee while on shift — a step up from 0005's single-current-fix
-- dispatch use. Deliberately NOT grid-suppressed or minimum-count-gated
-- the way the (now-removed, 0058) public transparency heat was: that
-- suppression existed to protect resident anonymity in a page anyone
-- could load with no login. This is the opposite audience — admin-only,
-- authenticated, precise-by-design, because the whole point is seeing
-- an individual tanod's actual path. Retention is capped at 30 days raw
-- via the purge job below, the more privacy-defensible of the two
-- options put to Ace, rather than an unbounded history.
-- =============================================================

set search_path = public, extensions;

-- ---------- history table -------------------------------------

create table public.tanod_locations (
  id          bigint generated always as identity primary key,
  tanod_id    uuid not null references public.users(id) on delete cascade,
  geom        geography(Point, 4326) not null,
  recorded_at timestamptz not null default now()
);

create index tanod_locations_tanod_time_idx
  on public.tanod_locations (tanod_id, recorded_at desc);
create index tanod_locations_recorded_at_idx
  on public.tanod_locations (recorded_at);

-- Deny-by-default: no select/insert/update/delete policy at all. Every
-- read and the one write both go through SECURITY DEFINER functions
-- below, same as barangay-scoped tables elsewhere in this schema.
alter table public.tanod_locations enable row level security;

-- ---------- write: extend the existing location update ---------
-- Same signature as 0005 -- the tanod app calls this exact RPC already
-- (tanod_home_screen.dart _pushLocation()), now on a 30-second timer
-- instead of 10 minutes while on duty. Nothing else changes about how
-- it is gated or called.

create or replace function public.update_my_location(p_lat double precision,
                                                     p_lon double precision)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_geom geography(Point, 4326) :=
    st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  update public.users
     set last_geom = v_geom,
         last_location_at = now()
   where id = auth.uid()
     and role = 'tanod'
     and duty_status = 'on_duty';

  if not found then
    raise exception 'Location is only recorded for a tanod who is on duty';
  end if;

  -- History for the admin pathing heatmap. Reaching here means the
  -- update above matched -- same on-duty gate, no separate check needed.
  insert into public.tanod_locations (tanod_id, geom)
  values (auth.uid(), v_geom);
end $$;

-- ---------- read: live positions for the admin map --------------

create or replace function public.tanod_live_positions()
returns table (
  tanod_id         uuid,
  full_name        text,
  lat              double precision,
  lng              double precision,
  duty_status      duty_state,
  last_location_at timestamptz,
  is_fresh         boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may view tanod positions';
  end if;

  return query
    select u.id, u.full_name,
           st_y(u.last_geom::geometry), st_x(u.last_geom::geometry),
           u.duty_status, u.last_location_at,
           public.location_is_fresh(u.last_location_at)
      from public.users u
     where u.role = 'tanod'
       and u.last_geom is not null
     order by u.full_name;
end $$;

-- ---------- read: path history for the admin heatmap -------------
-- p_tanod = null means every tanod in range, for the "all tanods"
-- pathing heatmap; a specific id narrows to one unit's trail, since the
-- same admin map is a reasonable place to also ask "where was Cruz on
-- the 12th" one tanod at a time.

create or replace function public.tanod_path_heatmap(
  p_from  timestamptz,
  p_to    timestamptz,
  p_tanod uuid default null)
returns table (
  tanod_id    uuid,
  full_name   text,
  lat         double precision,
  lng         double precision,
  recorded_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may view tanod path history';
  end if;

  return query
    select t.tanod_id, u.full_name,
           st_y(t.geom::geometry), st_x(t.geom::geometry),
           t.recorded_at
      from public.tanod_locations t
      join public.users u on u.id = t.tanod_id
     where t.recorded_at >= p_from
       and t.recorded_at <  p_to
       and (p_tanod is null or t.tanod_id = p_tanod)
     order by t.recorded_at;
end $$;

revoke execute on function public.tanod_live_positions() from public, anon;
grant  execute on function public.tanod_live_positions() to authenticated;
revoke execute on function public.tanod_path_heatmap(timestamptz, timestamptz, uuid) from public, anon;
grant  execute on function public.tanod_path_heatmap(timestamptz, timestamptz, uuid) to authenticated;

-- ---------- retention: 30 days raw, then purge --------------------
-- Same cron.schedule convention as sweep-overdue-reports etc. (0002).
-- Once daily is plenty for a 30-day-grained retention window.

select cron.schedule('purge-old-tanod-locations', '0 3 * * *',
  $$delete from public.tanod_locations where recorded_at < now() - interval '30 days'$$);

-- Verification. Run separately.
--
--   select proname from pg_proc where pronamespace = 'public'::regnamespace
--    and proname in ('tanod_live_positions', 'tanod_path_heatmap');
--   -- expect: 2 rows
--
--   select jobname, schedule from cron.job where jobname = 'purge-old-tanod-locations';
--   -- expect: 1 row, '0 3 * * *'
