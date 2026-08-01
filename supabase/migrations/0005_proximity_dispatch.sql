-- =============================================================
-- SmartSumbong — 0005 Jurisdiction and proximity dispatch
--
-- Implements the panel revision: barangay-first dispatch decided by
-- PostGIS proximity rather than by hand. Before this, dispatch was
-- entirely manual (dispatches.assigned_by) and no distance or
-- jurisdiction logic existed anywhere in the schema.
--
-- Three pieces:
--   1. The barangay boundary stored server-side, so jurisdiction is
--      decided in the database and not in browser JavaScript.
--   2. Live tanod position, so "nearest" means something.
--   3. Proximity selection over dispatchable tanods only.
-- =============================================================

set search_path = public, extensions;

-- ---------- jurisdiction -------------------------------------
-- Source: OpenStreetMap relation 2988704, admin_level 10,
-- border_type barangay, PSGC ref 1381100183. Area 6.27 km².
-- Stored as a row rather than hardcoded in a function so the
-- barangay can correct it without a schema migration.

create table public.barangay_boundary (
  id          smallint primary key default 1 check (id = 1),
  name        text not null,
  psgc_ref    text,
  source      text not null,
  geom        geography(MultiPolygon, 4326) not null,
  updated_at  timestamptz not null default now()
);

insert into public.barangay_boundary (name, psgc_ref, source, geom)
values ('Barangay 183', '1381100183',
        'OpenStreetMap relation 2988704',
        st_geomfromtext('MULTIPOLYGON(((121.0070454 14.5168392,121.0062389 14.5170095,121.0058411 14.5166250,121.0056614 14.5168808,121.0055691 14.5168992,121.0054361 14.5168912,121.0053006 14.5168755,121.0051974 14.5168301,121.0041057 14.5160310,121.0040829 14.5159824,121.0040585 14.5159396,121.0039478 14.5157451,121.0031555 14.5175704,121.0029107 14.5228763,121.0031184 14.5228856,121.0030810 14.5236441,121.0006541 14.5260284,121.0000017 14.5263040,120.9997461 14.5269394,120.9997045 14.5270632,120.9996706 14.5272067,120.9997994 14.5273055,120.9999788 14.5273742,121.0002581 14.5274357,121.0004530 14.5274929,121.0006861 14.5276226,121.0012497 14.5280099,121.0014933 14.5281716,121.0017159 14.5282642,121.0019647 14.5283164,121.0022535 14.5283114,121.0025770 14.5282777,121.0048576 14.5278764,121.0082501 14.5273342,121.0094761 14.5271309,121.0099377 14.5270164,121.0103382 14.5268306,121.0105873 14.5266438,121.0108926 14.5263081,121.0110807 14.5260221,121.0113819 14.5255165,121.0114480 14.5257545,121.0115452 14.5261939,121.0116409 14.5266118,121.0120551 14.5288110,121.0121385 14.5291683,121.0121407 14.5291777,121.0121682 14.5293083,121.0122221 14.5295913,121.0122603 14.5296409,121.0123156 14.5297554,121.0123788 14.5299114,121.0124818 14.5301274,121.0125848 14.5303102,121.0127393 14.5304016,121.0128938 14.5304514,121.0130655 14.5304514,121.0132543 14.5303933,121.0134345 14.5303268,121.0136655 14.5302237,121.0138289 14.5302264,121.0157353 14.5309442,121.0158673 14.5308676,121.0159494 14.5306093,121.0161554 14.5297784,121.0162155 14.5297037,121.0168275 14.5296505,121.0169206 14.5297335,121.0171596 14.5300775,121.0172883 14.5301855,121.0174772 14.5302188,121.0176917 14.5301772,121.0179860 14.5301085,121.0181922 14.5303120,121.0183392 14.5304696,121.0184974 14.5305652,121.0189732 14.5305612,121.0191331 14.5305537,121.0193747 14.5303343,121.0199860 14.5300295,121.0202693 14.5298633,121.0203672 14.5298517,121.0205653 14.5299074,121.0207830 14.5300236,121.0209336 14.5300827,121.0211905 14.5301805,121.0216820 14.5302987,121.0217677 14.5303046,121.0218367 14.5303218,121.0219239 14.5303659,121.0220337 14.5304353,121.0222048 14.5305370,121.0225805 14.5298321,121.0229245 14.5291517,121.0232637 14.5285303,121.0236484 14.5277451,121.0238660 14.5274192,121.0241032 14.5270193,121.0242258 14.5267558,121.0246645 14.5261375,121.0247434 14.5259074,121.0258539 14.5244955,121.0260861 14.5240210,121.0277369 14.5207653,121.0292178 14.5178912,121.0312311 14.5142183,121.0326622 14.5114923,121.0327546 14.5110088,121.0322789 14.5107661,121.0318413 14.5105543,121.0314270 14.5103011,121.0310262 14.5100589,121.0299540 14.5093859,121.0285617 14.5085159,121.0271495 14.5076184,121.0266893 14.5073242,121.0260007 14.5069066,121.0241102 14.5057364,121.0239392 14.5056484,121.0219088 14.5045944,121.0216945 14.5044300,121.0203189 14.5029500,121.0204131 14.5027784,121.0203195 14.5026767,121.0203258 14.5025004,121.0203001 14.5023259,121.0201799 14.5022262,121.0199095 14.5021618,121.0197604 14.5021158,121.0194755 14.5020273,121.0193720 14.5020221,121.0191277 14.5020444,121.0190247 14.5021275,121.0188294 14.5022488,121.0183681 14.5022895,121.0182479 14.5022865,121.0180988 14.5022524,121.0179950 14.5022614,121.0179208 14.5023392,121.0178769 14.5023853,121.0177544 14.5025138,121.0175657 14.5026124,121.0175016 14.5026033,121.0174231 14.5025591,121.0172353 14.5024660,121.0171489 14.5023955,121.0170934 14.5023802,121.0168679 14.5024774,121.0167979 14.5024377,121.0166679 14.5023823,121.0165753 14.5022764,121.0164551 14.5020281,121.0163697 14.5020060,121.0157257 14.5019841,121.0111362 14.5088933,121.0112605 14.5089251,121.0113637 14.5095433,121.0113045 14.5095690,121.0112772 14.5095844,121.0111975 14.5096516,121.0111544 14.5097096,121.0111451 14.5097274,121.0111297 14.5097580,121.0111103 14.5098180,121.0111018 14.5098741,121.0111021 14.5099309,121.0111185 14.5100130,121.0111360 14.5100573,121.0111595 14.5100986,121.0112224 14.5101740,121.0113031 14.5102315,121.0113596 14.5102563,121.0114195 14.5102722,121.0114747 14.5102785,121.0115398 14.5102761,121.0115526 14.5103928,121.0115789 14.5106451,121.0112723 14.5109658,121.0105305 14.5119192,121.0102129 14.5118367,121.0099030 14.5122611,121.0115637 14.5133041,121.0120817 14.5136098,121.0077119 14.5179120,121.0075980 14.5178791,121.0074102 14.5176299,121.0072090 14.5173624,121.0070642 14.5171002,121.0070293 14.5169989,121.0070296 14.5169108,121.0070454 14.5168392)))', 4326)::geography);

create index barangay_boundary_geom_idx on public.barangay_boundary using gist (geom);

-- ---------- live tanod position ------------------------------
-- attendance.geom is a check-in snapshot, not a current position,
-- so it cannot answer "who is nearest right now". The mobile app
-- updates these while the tanod is on duty.
--
-- PRIVACY: this is continuous location tracking of an employee. It is
-- written only while duty_status = 'on_duty' (enforced below), and the
-- barangay should confirm this is acceptable before deployment.

alter table public.users
  add column last_geom        geography(Point, 4326),
  add column last_location_at timestamptz;

create index users_last_geom_idx on public.users using gist (last_geom)
  where last_geom is not null;

-- A position older than this is not trusted for dispatch decisions.
create or replace function public.location_is_fresh(p_at timestamptz)
returns boolean language sql immutable as $$
  select p_at is not null and p_at > now() - interval '15 minutes'
$$;

create or replace function public.update_my_location(p_lat double precision,
                                                     p_lon double precision)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  update public.users
     set last_geom = st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography,
         last_location_at = now()
   where id = auth.uid()
     and role = 'tanod'
     and duty_status = 'on_duty';

  if not found then
    raise exception 'Location is only recorded for a tanod who is on duty';
  end if;
end $$;

-- ---------- jurisdiction test --------------------------------
-- This is the authoritative check. The browser map runs its own
-- point-in-polygon test for display only; this one decides routing.

create or replace function public.is_within_barangay(p_lat double precision,
                                                     p_lon double precision)
returns boolean language sql stable set search_path = public, extensions as $$
  select st_covers(b.geom, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography)
    from public.barangay_boundary b where b.id = 1
$$;

-- ---------- proximity selection ------------------------------
-- Candidate set is is_dispatchable (verified, on duty, not suspended)
-- with a fresh position and no live dispatch already held. Ordered by
-- true geodesic distance, which the GiST index on last_geom serves.

create or replace function public.nearest_available_tanod(p_report uuid)
returns table (tanod_id uuid, full_name text, metres double precision)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom) as metres
    from public.reports r
    cross join lateral (
      select u.* from public.users u
       where u.is_dispatchable
         and u.last_geom is not null
         and public.location_is_fresh(u.last_location_at)
         and not exists (
           select 1 from public.dispatches d
            where d.tanod_id = u.id and d.state in ('assigned', 'accepted'))
    ) u
   where r.id = p_report
   order by st_distance(u.last_geom, r.geom)
$$;

-- ---------- automatic dispatch -------------------------------
-- Barangay-first for everything inside the boundary. A report outside
-- it is not dispatched to a barangay unit at all; it is flagged for
-- referral, which is STA unit 6a.

create or replace function public.auto_dispatch(p_report uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    uuid;
  v_metres   double precision;
  v_dispatch uuid;
  v_system   uuid;
begin
  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  -- Out of jurisdiction: refer, do not dispatch.
  if not public.is_within_barangay(v_report.latitude, v_report.longitude) then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    values (p_report, v_report.resident_id, v_report.status, v_report.status,
            'Outside Barangay 183 — referred to city services', true);
    return null;
  end if;

  select t.tanod_id, t.metres into v_tanod, v_metres
    from public.nearest_available_tanod(p_report) t limit 1;

  if v_tanod is null then
    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    values (p_report, v_report.resident_id, v_report.status, v_report.status,
            'No tanod available for automatic dispatch — awaiting manual assignment', true);
    return null;
  end if;

  -- assigned_by records the system, using the report's own admin-less
  -- path: attributed to the nearest tanod's own id would be wrong, so
  -- the first admin on record stands as the dispatching authority.
  select id into v_system from public.users where role = 'admin' order by created_at limit 1;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, v_tanod, coalesce(v_system, v_tanod),
          format('Automatic dispatch — nearest available unit, %s m from the incident.',
                 round(v_metres)))
  returning id into v_dispatch;

  update public.reports set status = 'assigned' where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          format('Auto-dispatched to nearest unit (%s m)', round(v_metres)), true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment',
          format('New dispatch: %s', v_report.subject));

  return v_dispatch;
end $$;

revoke execute on function public.auto_dispatch(uuid) from public, anon;
grant  execute on function public.auto_dispatch(uuid) to authenticated;
revoke execute on function public.update_my_location(double precision, double precision) from public, anon;
grant  execute on function public.update_my_location(double precision, double precision) to authenticated;

alter table public.barangay_boundary enable row level security;
create policy boundary_read on public.barangay_boundary for select using (true);
