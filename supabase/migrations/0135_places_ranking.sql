-- 0135: places search, ranked for this barangay (22 Oct 2026).
--
-- The first live refresh (1,916 places) showed three things 0134 got wrong:
--   * "brgy hall" put Baclaran's hall (1.7 km) above Barangay 183 Hall: places
--     inside the barangay's own line, and its own places, now count for more,
--     and so does distance;
--   * the same place from the curated list and from OpenStreetMap read as
--     two branches ("Barangay 183 Hall, 2 branches"): one name within 150 m
--     is one place, and only places farther apart count as branches;
--   * listing a kind ("botika") showed such pairs twice: it now groups the
--     same way, nearest first.

set search_path = public, extensions;

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

  -- a kind of place on its own ("botika", "simbahan malapit", "pharmacy near me"): every word a kind word or a
  -- little word, so a name that holds one ("Shrine of St. Therese") is still searched as a name
  select k.grp into v_kind
    from public.place_kinds k, unnest(regexp_split_to_array(q, ' ')) w
   where w = any (k.words) and k.grp <> 'street'
   group by k.grp order by count(*) desc, k.grp limit 1;
  if v_kind is not null
     and (exists (select 1 from unnest(regexp_split_to_array(q, ' ')) w
                   where not exists (select 1 from public.place_kinds k where w = any (k.words))
                     and w not in ('near', 'me', 'nearby', 'nearest', 'malapit', 'pinakamalapit', 'sa', 'ng', 'na', 'the', 'a', 'in', 'around', 'dito', 'here'))
          or exists (select 1 from public.places p where p.active and p.search_text like q || '%')) then
    v_kind := null;
  end if;

  return query
    with hit as (
      select p.id, p.name, p.grp, p.kind, p.lat, p.lng, p.source, p.info, p.search_text, p.geom,
             st_distance(p.geom, here) as d,
             case when v_kind is not null then 1.0
                  else greatest(word_similarity(q, p.search_text), similarity(q, p.search_text))
                       + case when p.search_text like q || '%' then 0.35
                              when p.search_text like '% ' || q || '%' then 0.2 else 0 end end
               + case when p.source = 'barangay' then 0.2 else 0 end
               + case when st_covers(b.geom, p.geom) then 0.3 else 0 end as score
        from public.places p
        cross join (select bb.geom from public.barangay_boundary bb where bb.id = 1) b
       where p.active
         and case when v_kind is not null then p.grp = v_kind
                  else (p.search_text % q or q <% p.search_text or p.search_text like '%' || q || '%') end
    ), kept as (
      -- one row per name: the barangay's own copy when there is one, else the nearest
      select distinct on (h.search_text) h.*
        from hit h
       order by h.search_text, (h.source = 'barangay') desc, h.d
    )
    select k.id, k.name, k.grp, k.kind, k.lat, k.lng, round(k.d)::integer,
           (1 + (select count(*) from hit o where o.search_text = k.search_text and st_distance(o.geom, k.geom) > 150))::integer,
           k.source, k.info
      from kept k
     order by case when v_kind is not null then -k.d else k.score - least(k.d, 5000) / 5000.0 * 0.4 end desc, k.d
     limit v_lim;
end $$;
revoke all on function public.search_places(text, double precision, double precision, integer) from public, anon;
grant execute on function public.search_places(text, double precision, double precision, integer) to authenticated;
