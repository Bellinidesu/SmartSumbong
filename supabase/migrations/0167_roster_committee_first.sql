-- 0167: the dispatch list puts the case's committee's tanods first (Ace, 7 Nov 2026, the flow check: "recommendation").
--
-- A Kagawad's Personnel shows their committee's tanods, and the automatic reroute already tries the committee's tanods
-- first (0155), but the manual dispatch list was every tanod, nearest first, whatever their committee. Now every tanod is
-- still listed (a case is never left with nobody to send), and each row says whether the tanod is approved in the
-- committee the case is with now (0152); among the tanods who can take it, the committee's come first.

drop function public.tanod_roster(uuid);
create function public.tanod_roster(p_report uuid)
returns table (tanod_id uuid, full_name text, duty_status public.duty_state, assignable boolean, unavailable_why text,
               metres double precision, location_fresh boolean, in_committee boolean)
language sql stable set search_path = public, extensions as $$
  with c as (select public._case_committee(p_report) as committee)
  select u.id,
         u.full_name,
         u.duty_status,
         u.is_dispatchable and coalesce(b.n, 0) < public.tanod_dispatch_cap(),
         case
           when coalesce(b.n, 0) >= public.tanod_dispatch_cap() then 'Has ' || b.n || ' dispatches (the most at once)'
           when u.is_suspended                then 'Suspended'
           when u.verification_status <> 'verified' then 'Not yet verified'
           when coalesce(u.duty_status, 'offline') <> 'on_duty'
             then initcap(replace(coalesce(u.duty_status, 'offline')::text, '_', ' '))
           else null
         end,
         st_distance(u.last_geom, r.geom),
         public.location_is_fresh(u.last_location_at),
         exists (select 1 from public.tanod_committees tc, c
                  where tc.tanod_id = u.id and tc.status = 'approved' and tc.committee = c.committee)
    from public.users u
    cross join public.reports r
    left join lateral (
      select count(*)::int as n from public.dispatches d
       where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) b on true
   where r.id = p_report
     and u.role = 'tanod'
   order by (u.is_dispatchable and coalesce(b.n, 0) < public.tanod_dispatch_cap()) desc,
            exists (select 1 from public.tanod_committees tc, c
                     where tc.tanod_id = u.id and tc.status = 'approved' and tc.committee = c.committee) desc,
            coalesce(b.n, 0),
            st_distance(u.last_geom, r.geom) nulls last,
            u.full_name
$$;
comment on function public.tanod_roster(uuid) is
  'Every tanod with availability and distance, for the assign screen. Available first; among those, the tanods of the committee the case is with now (0167, in_committee); then the fewest jobs in hand, then nearest.';
revoke all on function public.tanod_roster(uuid) from public, anon;
grant execute on function public.tanod_roster(uuid) to authenticated, service_role;
