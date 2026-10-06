-- 0096 — Portal uptime record (industry pass 5, 7 Oct 2026).
--
-- The keep-awake ping (0091/0094) now also keeps score: every 10 minutes it
-- asks the portal for /admin/ping.php and remembers whether it answered.
-- pg_net delivers answers asynchronously, so each run first files the
-- previous runs' answers, then sends the next request. Settings → System
-- status shows the last day and week from portal_uptime_summary().

create table if not exists public.portal_uptime (
  id          bigint generated always as identity primary key,
  request_id  bigint not null,
  checked_at  timestamptz not null default now(),
  status      int,
  ok          boolean,
  error       text
);
create index if not exists portal_uptime_checked_at_idx on public.portal_uptime (checked_at desc);
alter table public.portal_uptime enable row level security;
-- No policies: only the functions below (and the database owner) touch it.

create or replace function public.ping_portal()
returns void language plpgsql security definer set search_path = public, extensions, net as $$
declare v_req bigint;
begin
  -- File the answers that have arrived since the last run.
  update public.portal_uptime u
     set status = r.status_code,
         ok     = (r.status_code = 200 and not coalesce(r.timed_out, false)),
         error  = left(coalesce(r.error_msg, case when r.timed_out then 'timed out' end), 200)
    from net._http_response r
   where r.id = u.request_id and u.ok is null;
  -- A request with no answer after 15 minutes counts as down.
  update public.portal_uptime set ok = false, error = 'no answer'
   where ok is null and checked_at < now() - interval '15 minutes';
  delete from public.portal_uptime where checked_at < now() - interval '30 days';

  select net.http_get('https://smartsumbong-ph.onrender.com/admin/ping.php', timeout_milliseconds := 60000) into v_req;
  insert into public.portal_uptime (request_id) values (v_req);
end $$;
revoke all on function public.ping_portal() from public, anon, authenticated;

create or replace function public.portal_uptime_summary()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only an administrator may see the uptime record'; end if;
  return json_build_object(
    'day_checks',  (select count(*) from portal_uptime where ok is not null and checked_at > now() - interval '1 day'),
    'day_ok',      (select count(*) from portal_uptime where ok and checked_at > now() - interval '1 day'),
    'week_checks', (select count(*) from portal_uptime where ok is not null and checked_at > now() - interval '7 days'),
    'week_ok',     (select count(*) from portal_uptime where ok and checked_at > now() - interval '7 days'),
    'last_at',     (select checked_at from portal_uptime where ok is not null order by checked_at desc limit 1),
    'last_ok',     (select ok from portal_uptime where ok is not null order by checked_at desc limit 1)
  );
end $$;
revoke all on function public.portal_uptime_summary() from public, anon;
grant execute on function public.portal_uptime_summary() to authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'keep-portal-awake';
select cron.schedule('keep-portal-awake', '*/10 * * * *', $$ select public.ping_portal() $$);

-- Start the record with the pings already in pg_net's own log (last ~6 h).
insert into public.portal_uptime (request_id, checked_at, status, ok, error)
select r.id, r.created, r.status_code, (r.status_code = 200 and not coalesce(r.timed_out, false)), left(r.error_msg, 200)
  from net._http_response r
 where not exists (select 1 from public.portal_uptime u where u.request_id = r.id);
