-- 0101 — The database-level guard follows the new cap (0100).
--
-- 0008's unique index allowed one live dispatch per tanod "full stop".
-- It becomes a trigger that allows up to tanod_dispatch_cap() (5). A per-
-- tanod advisory lock keeps two dispatches made at the same moment from
-- both slipping under the cap. The same report twice is still refused by
-- 0002's own index.

drop index if exists public.dispatches_one_live_job_per_tanod;

create or replace function public._dispatch_cap_guard()
returns trigger language plpgsql set search_path = public as $$
declare v_n int;
begin
  if new.state not in ('assigned', 'accepted') then return new; end if;
  if tg_op = 'UPDATE' and old.state in ('assigned', 'accepted') and old.tanod_id = new.tanod_id then
    return new;   -- the same live dispatch moving between live states
  end if;
  perform pg_advisory_xact_lock(hashtext('dispatch-cap:' || new.tanod_id::text));
  select count(*) into v_n from public.dispatches
   where tanod_id = new.tanod_id and state in ('assigned', 'accepted') and id <> new.id;
  if v_n >= public.tanod_dispatch_cap() then
    raise exception 'This tanod already has % dispatches, the most at once.', v_n;
  end if;
  return new;
end $$;

drop trigger if exists dispatch_cap_guard on public.dispatches;
create trigger dispatch_cap_guard
  before insert or update of state, tanod_id on public.dispatches
  for each row execute function public._dispatch_cap_guard();
