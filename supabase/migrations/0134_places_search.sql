-- 0134: places, searched the way people search (22 Oct 2026).
--
-- Rose found the landmark search outdated: it matched text against 38
-- places saved on 26 Sep, forgave no typo and never learned a new place.
-- Now one table holds the places and streets the portal and the app find:
--
--   osm        named places and streets in and around Barangay 183 from
--              OpenStreetMap (ODbL), refreshed every six hours through
--              Overpass: asked by pg_net, filed ten minutes later. A place
--              gone from the map goes inactive here; an answer that looks
--              broken (too few places) changes nothing.
--   barangay   the places the barangay keeps itself: the 38 curated
--              landmarks to start with, and any an administrator adds
--              (the name residents and tanods actually use). The refresh
--              never touches them.
--
-- search_places() forgives what people type: letter slips (pg_trgm),
-- shorthand (St, Ave, Brgy, Sto, Gen), accents (Thérèse), and Tagalog or
-- English words for a kind of place ("botika", "simbahan", "pharmacy"),
-- which list that kind, nearest first. A chain is one result, its branches
-- counted, the nearest shown.
--
-- Places and streets only, never anyone's home: a resident's location
-- stays on their own report.

set search_path = public, extensions;

-- ---------- matching text -----------------------------------------------------------------

/** Text as search compares it: lower case, accents off, punctuation out, shorthand spelled out. */
create or replace function public.places_norm(p text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select coalesce(string_agg(case w
      when 'st' then 'street' when 'str' then 'street' when 'ave' then 'avenue' when 'av' then 'avenue'
      when 'blvd' then 'boulevard' when 'rd' then 'road' when 'dr' then 'drive' when 'hwy' then 'highway'
      when 'brgy' then 'barangay' when 'bgy' then 'barangay' when 'brg' then 'barangay'
      when 'sto' then 'santo' when 'sta' then 'santa' when 'gen' then 'general' when 'mt' then 'mount'
      when 'ext' then 'extension' when 'cor' then 'corner'
      else w end, ' ' order by i), '')
    from unnest(regexp_split_to_array(trim(regexp_replace(
           translate(lower(coalesce(p, '')), 'áàâäãéèêëíìîïóòôöõúùûüñç', 'aaaaaeeeeiiiiooooouuuunc'),
           '[^a-z0-9]+', ' ', 'g')), ' ')) with ordinality as t(w, i)
   where w <> ''
$$;

/** The kinds of place, and the words people use for each (English, Tagalog, Taglish). */
create table public.place_kinds (
  grp   text primary key,
  label text not null,
  words text[] not null
);
alter table public.place_kinds enable row level security;
create policy place_kinds_read on public.place_kinds for select to authenticated using (true);
insert into public.place_kinds (grp, label, words) values
  ('health',     'Health',             array['hospital','ospital','clinic','klinika','health','doctor','doktor','dentist','pharmacy','botika','drugstore','parmasya','medical']),
  ('school',     'School',             array['school','paaralan','eskwelahan','eskwela','skul','college','university','kolehiyo','daycare','kindergarten','academy']),
  ('worship',    'Church and worship', array['church','simbahan','chapel','kapilya','mosque','masjid','temple','parish','shrine']),
  ('safety',     'Police and fire',    array['police','pulis','pulisya','presinto','fire','bumbero','firestation','outpost']),
  ('hall',       'Barangay hall',      array['munisipyo','cityhall','bulwagan']),
  ('government', 'Government office',  array['government','gobyerno','opisina','immigration','agency']),
  ('transport',  'Transport',          array['terminal','sakayan','bus','jeep','jeepney','tricycle','taxi','airport','paliparan','parking','paradahan','train','lrt','mrt']),
  ('food',       'Food',               array['food','pagkain','kainan','restaurant','karinderya','carinderia','cafe','coffee','kape','fastfood','eatery','bakery','panaderya']),
  ('shop',       'Shop and market',    array['store','tindahan','sarisari','shop','market','palengke','mall','grocery','supermarket','convenience','hardware']),
  ('service',    'Bank and service',   array['bank','bangko','atm','remittance','padala','pawnshop','sanglaan','laundry','salon','gasolinahan','fuel','courier']),
  ('lodging',    'Hotel',              array['hotel','inn','lodge','motel','hostel','condotel']),
  ('park',       'Park and sports',    array['park','parke','playground','palaruan','court','basketball','gym','plaza']),
  ('military',   'Military',           array['military','kampo','squadron','afp']),
  ('street',     'Street',             array['street','kalye','road','daan','avenue','boulevard','highway','alley','eskinita']),
  ('area',       'Area',               array['zone','purok','village','subdivision','compound']);

-- ---------- the places --------------------------------------------------------------------------

create table public.places (
  id          bigserial primary key,
  source      text not null check (source in ('osm', 'barangay')),
  osm_ref     text unique,                       -- n123, w456, street:harvard street (osm only)
  name        text not null check (length(trim(name)) between 1 and 120),
  aliases     text[] not null default '{}',      -- other names people use
  kind        text,                              -- the map's own tag value: cafe, school, residential
  grp         text not null references public.place_kinds (grp),
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  info        jsonb not null default '{}',       -- opening_hours, brand, operator, website, cuisine
  search_text text generated always as (public.places_norm(name || ' ' || array_to_string(aliases, ' '))) stored,
  geom        geography(Point, 4326) generated always as (st_setsrid(st_makepoint(lng, lat), 4326)::geography) stored,
  active      boolean not null default true,
  added_by    uuid references public.users (id) on delete set null,
  updated_at  timestamptz not null default now(),
  seen_at     timestamptz not null default now()
);
create index places_search_trgm_idx on public.places using gin (search_text gin_trgm_ops);
create index places_geom_idx on public.places using gist (geom);
create index places_grp_idx on public.places (grp) where active;

alter table public.places enable row level security;
create policy places_read on public.places for select to authenticated using (active or (select public.is_admin()));
comment on table public.places is
  '0134: places and streets the portal and app search: OpenStreetMap (refreshed every 6 h) and the barangay''s own. Places only, never homes. Read by every signed-in user; changed by place_save/place_remove (admins) and the refresh.';

-- the 38 landmarks the barangay curated (assets/map/landmarks.geojson), now its own places
insert into public.places (source, name, grp, lat, lng) values
  ('Royal Air Charter', 'transport', 14.527416, 121.000992),
  ('Police Help Desk', 'safety', 14.509743, 121.012676),
  ('Metro Supermarket', 'shop', 14.524096, 121.013598),
  ('Ang Dating Daan', 'worship', 14.526977, 121.012850),
  ('Philippine Air Force Finance Center', 'government', 14.515984, 121.020810),
  ('Church of God - Marriott Manila', 'worship', 14.520613, 121.018861),
  ('TGP', 'health', 14.525187, 121.012089),
  ('Watsons', 'health', 14.523107, 121.013910),
  ('Zoe', 'health', 14.525104, 121.012100),
  ('LBC', 'service', 14.525140, 121.011999),
  ('Watsons', 'health', 14.521818, 121.015843),
  ('Bureau of Immigration One-Stop Shop', 'government', 14.518816, 121.013777),
  ('Muslim Prayer Room', 'worship', 14.508922, 121.011826),
  ('Villamor Airbase Elementary School', 'school', 14.529860, 121.021490),
  ('Villamor Air Base', 'military', 14.517147, 121.023315),
  ('Shrine of St. Thérèse of the Child Jesus', 'worship', 14.521242, 121.015915),
  ('Philippines State College of Aeronautics', 'school', 14.526701, 121.023628),
  ('Pasay City South High School', 'school', 14.528671, 121.022535),
  ('The Airmen''s Mall', 'shop', 14.516857, 121.020853),
  ('Barangay 183 Hall', 'hall', 14.525104, 121.012596),
  ('Our Lady of Loreto Chapel', 'worship', 14.517326, 121.021854),
  ('Villamor Police Sub-station', 'safety', 14.525239, 121.011864),
  ('Villamor Post Exchange', 'shop', 14.516449, 121.020643),
  ('Terminal 2 South Wing', 'transport', 14.509000, 121.012737),
  ('Terminal 2 North Wing', 'transport', 14.510361, 121.013027),
  ('NAIA Terminal 3', 'transport', 14.519225, 121.013440),
  ('NAIA Centennial Terminal 2', 'transport', 14.509618, 121.013414),
  ('Air Force Office School', 'school', 14.520384, 121.023676),
  ('Protacio Park', 'park', 14.519014, 121.025586),
  ('PAF Firing Range', 'military', 14.517381, 121.028262),
  ('Newport Mall', 'shop', 14.518895, 121.019938),
  ('Philippine National Police Aviation Security Group', 'safety', 14.509541, 121.028809),
  ('PNP Aviation Security Group', 'safety', 14.509144, 121.024109),
  ('Eighty One Mall', 'shop', 14.522658, 121.014136),
  ('505th Squadron Serenity Park', 'park', 14.516823, 121.027393),
  ('Mini Playground', 'park', 14.518129, 121.027882),
  ('Air Force General Hospital', 'health', 14.516912, 121.019923),
  ('Manila International Airport Fire Station', 'safety', 14.509001, 121.025333);

-- ---------- searching ---------------------------------------------------------------------------

/**
 * Places for what was typed, best first. Near p_lat/p_lng when given (the
 * barangay hall otherwise). A word for a kind of place lists that kind,
 * nearest first; anything else is matched by name, forgiving slips. A name
 * with several branches comes back once: the nearest, and how many.
 */
create or replace function public.search_places(p_q text, p_lat double precision default null,
                                                p_lng double precision default null, p_limit integer default 8)
returns table (id bigint, name text, grp text, kind text, lat double precision, lng double precision,
               metres integer, branches integer, source text, info jsonb)
language plpgsql
stable
set search_path = public, extensions
set jit = off
as $$
declare
  q      text := public.places_norm(left(coalesce(p_q, ''), 80));
  here   geography := st_setsrid(st_makepoint(coalesce(p_lng, 121.012596), coalesce(p_lat, 14.525104)), 4326)::geography;
  v_lim  integer := least(greatest(coalesce(p_limit, 8), 1), 25);
  v_kind text;
begin
  if length(q) < 2 then return; end if;

  -- a kind of place on its own ("botika", "simbahan", "pharmacy near me"), unless a place is named so
  select k.grp into v_kind
    from public.place_kinds k, unnest(regexp_split_to_array(q, ' ')) w
   where w = any (k.words) and k.grp <> 'street'
   group by k.grp order by count(*) desc, k.grp limit 1;
  if v_kind is not null and q !~ '[0-9]' and coalesce(array_length(regexp_split_to_array(q, ' '), 1), 0) <= 3
     and not exists (select 1 from public.places p where p.active and p.search_text like q || '%') then
    return query
      select p.id, p.name, p.grp, p.kind, p.lat, p.lng, round(st_distance(p.geom, here))::integer, 1, p.source, p.info
        from public.places p
       where p.active and p.grp = v_kind
       order by p.geom <-> here
       limit v_lim;
    return;
  end if;

  return query
    with hit as (
      select p.id, p.name, p.grp, p.kind, p.lat, p.lng, p.source, p.info, p.search_text,
             greatest(word_similarity(q, p.search_text), similarity(q, p.search_text))
               + case when p.search_text like q || '%' then 0.35
                      when p.search_text like '% ' || q || '%' then 0.2 else 0 end
               + case when p.source = 'barangay' then 0.05 else 0 end as score,
             st_distance(p.geom, here) as d
        from public.places p
       where p.active
         and (p.search_text % q or q <% p.search_text or p.search_text like '%' || q || '%')
    ), grouped as (
      select distinct on (h.search_text, h.grp)
             h.id, h.name, h.grp, h.kind, h.lat, h.lng, h.d, h.score, h.source, h.info,
             count(*) over (partition by h.search_text, h.grp) as n
        from hit h
       order by h.search_text, h.grp, h.d
    )
    select g.id, g.name, g.grp, g.kind, g.lat, g.lng, round(g.d)::integer, g.n::integer, g.source, g.info
      from grouped g
     order by g.score - least(g.d, 5000) / 50000.0 desc, g.d
     limit v_lim;
end $$;
revoke all on function public.search_places(text, double precision, double precision, integer) from public, anon;
grant execute on function public.search_places(text, double precision, double precision, integer) to authenticated;

-- ---------- the barangay's own places ------------------------------------------------------------

/** An administrator adds or edits one of the barangay's own places. Returns its id. */
create or replace function public.place_save(p_id bigint, p_name text, p_grp text, p_lat double precision,
                                             p_lng double precision, p_aliases text[] default '{}')
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id bigint;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can change the barangay''s places.' using errcode = 'insufficient_privilege';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 120 then raise exception 'A place needs a name (2 to 120 letters).'; end if;
  if not exists (select 1 from public.place_kinds where grp = p_grp) then raise exception 'Unknown kind of place.'; end if;
  if p_lat is null or p_lng is null or not st_dwithin(st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
                    st_setsrid(st_makepoint(121.012596, 14.525104), 4326)::geography, 5000) then
    raise exception 'The place must be within 5 km of the barangay hall.';
  end if;
  if p_id is null then
    insert into public.places (source, name, grp, lat, lng, aliases, added_by)
    values ('barangay', trim(p_name), p_grp, p_lat, p_lng, coalesce(p_aliases, '{}'), auth.uid())
    returning places.id into v_id;
  else
    update public.places set name = trim(p_name), grp = p_grp, lat = p_lat, lng = p_lng,
           aliases = coalesce(p_aliases, '{}'), updated_at = now(), active = true
     where places.id = p_id and places.source = 'barangay'
    returning places.id into v_id;
    if v_id is null then raise exception 'Only the barangay''s own places can be edited here.'; end if;
  end if;
  return v_id;
end $$;
revoke all on function public.place_save(bigint, text, text, double precision, double precision, text[]) from public, anon;
grant execute on function public.place_save(bigint, text, text, double precision, double precision, text[]) to authenticated;

/** An administrator removes one of the barangay's own places. */
create or replace function public.place_remove(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can change the barangay''s places.' using errcode = 'insufficient_privilege';
  end if;
  update public.places set active = false, updated_at = now() where id = p_id and source = 'barangay';
end $$;
revoke all on function public.place_remove(bigint) from public, anon;
grant execute on function public.place_remove(bigint) to authenticated;

-- ---------- the refresh from OpenStreetMap -------------------------------------------------------

create table public.places_refresh (
  id          smallint primary key default 1 check (id = 1),
  request_id  bigint,
  mirror      smallint not null default 0,
  asked_at    timestamptz,
  filed_at    timestamptz,
  last_ok_at  timestamptz,
  last_count  integer,
  last_error  text
);
alter table public.places_refresh enable row level security;
create policy places_refresh_admin_read on public.places_refresh for select using ((select public.is_admin()));
insert into public.places_refresh (id) values (1);

/** The Overpass query: named places and streets within about 500 m of the barangay. */
create or replace function public._places_query()
returns text
language sql
immutable
as $$
  select '[out:json][timeout:80];('
      || 'nwr["name"]["amenity"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["shop"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["tourism"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["leisure"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["office"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["healthcare"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["historic"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["public_transport"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["aeroway"~"terminal|aerodrome|helipad"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["military"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["place"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["landuse"~"residential|military|commercial|retail"](14.498,120.995,14.535,121.037);'
      || 'nwr["name"]["building"~"school|church|chapel|hospital|civic|government|public|train_station|transportation|mosque|temple|commercial|retail"](14.498,120.995,14.535,121.037);'
      || 'way["name"]["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|living_street|pedestrian|footway)$"](14.498,120.995,14.535,121.037);'
      || ');out center tags qt;'
$$;

/** The group for a place from its map tags. */
create or replace function public._places_grp(t jsonb)
returns text
language sql
immutable
as $$
  select case
    when t ? 'highway' then 'street'
    when t->>'amenity' in ('hospital', 'clinic', 'doctors', 'dentist', 'pharmacy', 'health_post') or t ? 'healthcare' then 'health'
    when t->>'amenity' in ('school', 'college', 'university', 'kindergarten', 'childcare', 'library') or t->>'building' = 'school' then 'school'
    when t->>'amenity' = 'place_of_worship' or t->>'building' in ('church', 'chapel', 'mosque', 'temple') then 'worship'
    when t->>'amenity' in ('police', 'fire_station') then 'safety'
    when t->>'amenity' = 'townhall' then 'hall'
    when t->>'office' = 'government' or t->>'building' in ('government', 'civic', 'public') or t->>'amenity' in ('post_office', 'courthouse') then 'government'
    when t->>'amenity' in ('bus_station', 'taxi', 'parking', 'ferry_terminal', 'car_rental') or t ? 'public_transport' or t ? 'aeroway'
         or t->>'building' in ('train_station', 'transportation') then 'transport'
    when t->>'amenity' in ('restaurant', 'fast_food', 'cafe', 'food_court', 'bar', 'pub', 'ice_cream') then 'food'
    when t ? 'shop' or t->>'amenity' = 'marketplace' or t->>'landuse' in ('retail', 'commercial') or t->>'building' in ('commercial', 'retail') then 'shop'
    when t->>'amenity' in ('bank', 'atm', 'bureau_de_change', 'money_transfer', 'fuel', 'car_wash') then 'service'
    when t->>'tourism' in ('hotel', 'guest_house', 'hostel', 'motel', 'apartment') then 'lodging'
    when t ? 'leisure' then 'park'
    when t ? 'military' or t->>'landuse' = 'military' then 'military'
    when t ? 'place' or t->>'landuse' = 'residential' then 'area'
    else 'service' end
$$;

/** Asks Overpass for the places (pg_cron, every six hours); places_refresh_file() files the answer. */
create or replace function public.places_refresh_ask()
returns void
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  v_urls text[] := array['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter',
                         'https://overpass.kumi.systems/api/interpreter'];
  v_m    smallint;
  v_req  bigint;
begin
  select mirror into v_m from public.places_refresh where id = 1;
  select net.http_get(v_urls[1 + coalesce(v_m, 0) % array_length(v_urls, 1)],
                      params := jsonb_build_object('data', public._places_query()),
                      headers := jsonb_build_object('User-Agent', 'SmartSumbong-Barangay183/1.0 (barangay complaint system)'),
                      timeout_milliseconds := 100000)
    into v_req;
  update public.places_refresh set request_id = v_req, asked_at = now() where id = 1;
end $$;
revoke all on function public.places_refresh_ask() from public, anon, authenticated;

/**
 * Files Overpass's answer: places upserted by their map id, each street once
 * (its pieces joined, placed at the piece nearest their middle), and map
 * places no longer in the answer set inactive. An answer with fewer than 30
 * places is taken as broken and changes nothing; a failed answer moves the
 * next ask to the next mirror. Returns what it did.
 */
create or replace function public.places_refresh_file()
returns text
language plpgsql
security definer
set search_path = public, extensions, net
set jit = off
as $$
declare
  st     public.places_refresh%rowtype;
  r      record;
  v_json jsonb;
  v_n    integer;
  v_run  timestamptz := clock_timestamp();
begin
  select * into st from public.places_refresh where id = 1;
  if st.request_id is null then return 'nothing asked'; end if;
  select * into r from net._http_response where id = st.request_id;
  if not found then
    if st.asked_at < now() - interval '30 minutes' then
      update public.places_refresh set request_id = null, mirror = (mirror + 1) % 3, last_error = 'no answer' where id = 1;
      return 'no answer';
    end if;
    return 'waiting';
  end if;

  begin
    v_json := r.content::jsonb;
  exception when others then
    v_json := null;
  end;
  if r.status_code is distinct from 200 or v_json is null or jsonb_typeof(v_json -> 'elements') is distinct from 'array' then
    update public.places_refresh set request_id = null, mirror = (mirror + 1) % 3, filed_at = now(),
           last_error = left(trim(coalesce('HTTP ' || r.status_code, '') || ' ' || coalesce(r.error_msg, '')), 200) where id = 1;
    return 'failed';
  end if;

  drop table if exists _places_in;
  create temporary table _places_in on commit drop as
    select left(e ->> 'type', 1) || (e ->> 'id') as ref,
           left(trim(e -> 'tags' ->> 'name'), 120) as name,
           e -> 'tags' as tags,
           coalesce((e ->> 'lat')::float8, (e -> 'center' ->> 'lat')::float8) as lat,
           coalesce((e ->> 'lon')::float8, (e -> 'center' ->> 'lon')::float8) as lng
      from jsonb_array_elements(v_json -> 'elements') e
     where length(trim(coalesce(e -> 'tags' ->> 'name', ''))) > 0
       and coalesce(e ->> 'lat', e -> 'center' ->> 'lat') is not null;
  select count(*) into v_n from _places_in;
  if v_n < 30 then
    update public.places_refresh set request_id = null, filed_at = now(),
           last_error = 'only ' || v_n || ' places in the answer; kept the last good set' where id = 1;
    return 'too few';
  end if;

  -- places (not streets): one row per map object
  insert into public.places as p (source, osm_ref, name, kind, grp, lat, lng, info, seen_at, updated_at, active)
  select 'osm', x.ref, x.name,
         coalesce(x.tags ->> 'amenity', x.tags ->> 'shop', x.tags ->> 'tourism', x.tags ->> 'leisure', x.tags ->> 'office',
                  x.tags ->> 'healthcare', x.tags ->> 'aeroway', x.tags ->> 'public_transport', x.tags ->> 'military',
                  x.tags ->> 'place', x.tags ->> 'landuse', x.tags ->> 'building', x.tags ->> 'historic'),
         public._places_grp(x.tags), x.lat, x.lng,
         jsonb_strip_nulls(jsonb_build_object('opening_hours', x.tags ->> 'opening_hours', 'brand', x.tags ->> 'brand',
           'operator', x.tags ->> 'operator', 'website', x.tags ->> 'website', 'cuisine', x.tags ->> 'cuisine',
           'name_tl', x.tags ->> 'name:tl', 'alt_name', x.tags ->> 'alt_name')),
         v_run, v_run, true
    from _places_in x
   where not (x.tags ? 'highway')
  on conflict (osm_ref) do update
     set name = excluded.name, kind = excluded.kind, grp = excluded.grp, lat = excluded.lat, lng = excluded.lng,
         info = excluded.info, seen_at = excluded.seen_at, active = true,
         updated_at = case when (p.name, p.lat, p.lng, p.info) is distinct from (excluded.name, excluded.lat, excluded.lng, excluded.info)
                           then excluded.updated_at else p.updated_at end;

  -- streets: one row per name, at the piece nearest the middle of all its pieces
  insert into public.places as p (source, osm_ref, name, kind, grp, lat, lng, seen_at, updated_at, active)
  select 'osm', 'street:' || s.key, s.name, 'street', 'street', s.lat, s.lng, v_run, v_run, true
    from (
      select distinct on (m.key) m.key, x.name, x.lat, x.lng
        from _places_in x
        join (select public.places_norm(name) as key, avg(lat) as alat, avg(lng) as alng
                from _places_in where tags ? 'highway' group by 1) m on m.key = public.places_norm(x.name)
       where x.tags ? 'highway'
       order by m.key, (x.lat - m.alat) ^ 2 + (x.lng - m.alng) ^ 2
    ) s
  on conflict (osm_ref) do update
     set name = excluded.name, lat = excluded.lat, lng = excluded.lng, seen_at = excluded.seen_at, active = true;

  update public.places set active = false, updated_at = v_run
   where source = 'osm' and active and seen_at < v_run;

  update public.places_refresh set request_id = null, filed_at = now(), last_ok_at = now(), last_count = v_n, last_error = null
   where id = 1;
  return 'filed ' || v_n;
end $$;
revoke all on function public.places_refresh_file() from public, anon, authenticated;

select cron.schedule('places-ask', '7 */6 * * *', $$ select public.places_refresh_ask() $$);
select cron.schedule('places-file', '17 */6 * * *', $$ select public.places_refresh_file() $$);

/** Admins: when the places were last refreshed, and how many there are. */
create or replace function public.places_status()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see this.' using errcode = 'insufficient_privilege';
  end if;
  return (select json_build_object('last_ok_at', r.last_ok_at, 'last_count', r.last_count, 'last_error', r.last_error,
            'osm', (select count(*) from public.places where source = 'osm' and active),
            'barangay', (select count(*) from public.places where source = 'barangay' and active))
          from public.places_refresh r where r.id = 1);
end $$;
revoke all on function public.places_status() from public, anon;
grant execute on function public.places_status() to authenticated;
