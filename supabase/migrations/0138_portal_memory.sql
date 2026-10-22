-- =============================================================
-- SmartSumbong — 0138 The portal's memory, measured by its own checks
--
-- Render's free plan hides its Metrics. To decide what the engine can run
-- inside the portal's own server (Ace, 22 Oct 2026: "separate stuff and
-- just send to the engine what can be sent"), we need to know how much of
-- its 512 MB the portal uses. ping.php now reports the container's memory
-- in a header; the 10-minute check files it next to the answer, and
-- portal_uptime_summary() gives Settings the week's figures.
-- =============================================================

set search_path = public, extensions;

alter table public.portal_uptime
  add column if not exists mem_used_mb int,
  add column if not exists mem_peak_mb int,
  add column if not exists mem_limit_mb int;

comment on column public.portal_uptime.mem_used_mb is '0138: the portal container''s memory in use at this check (MB), from ping.php.';
comment on column public.portal_uptime.mem_peak_mb is '0138: the highest the container has used since it started (MB), when the host reports it.';
comment on column public.portal_uptime.mem_limit_mb is '0138: the container''s memory limit (MB), when the host reports it.';

create or replace function public.ping_portal()
returns void language plpgsql security definer set search_path = public, extensions, net as $$
declare
  v_req   bigint;
  v_open  public.portal_outages;
  v_last2 boolean[];
begin
  -- File the answers that have arrived since the last run.
  update public.portal_uptime u
     set status = r.status_code,
         ok     = (r.status_code = 200 and not coalesce(r.timed_out, false)),
         error  = left(coalesce(r.error_msg, case when r.timed_out then 'timed out' end), 200),
         -- 0138: the container's memory, from ping.php's X-Portal-Memory header (MB)
         mem_used_mb  = (regexp_match(coalesce(r.headers ->> 'X-Portal-Memory', r.headers ->> 'x-portal-memory'), 'used=([0-9]+)'))[1]::int,
         mem_peak_mb  = (regexp_match(coalesce(r.headers ->> 'X-Portal-Memory', r.headers ->> 'x-portal-memory'), 'peak=([0-9]+)'))[1]::int,
         mem_limit_mb = (regexp_match(coalesce(r.headers ->> 'X-Portal-Memory', r.headers ->> 'x-portal-memory'), 'limit=([0-9]+)'))[1]::int
    from net._http_response r
   where r.id = u.request_id and u.ok is null;
  update public.portal_uptime set ok = false, error = 'no answer'
   where ok is null and checked_at < now() - interval '15 minutes';
  delete from public.portal_uptime where checked_at < now() - interval '30 days';

  -- Two misses in a row open an outage (and alert); an answer closes it.
  select array_agg(ok order by checked_at desc) into v_last2
    from (select ok, checked_at from public.portal_uptime where ok is not null order by checked_at desc limit 2) x;
  select * into v_open from public.portal_outages where ended_at is null order by started_at desc limit 1;
  if v_open.id is null and v_last2 = array[false, false] then
    insert into public.portal_outages (started_at)
    select min(checked_at) from (select checked_at from public.portal_uptime where ok is not null order by checked_at desc limit 2) y;
    perform public._notify_admins('The admin portal stopped answering at '
      || to_char(now() at time zone 'Asia/Manila', 'HH12:MI AM') || '. It is checked every 10 minutes; you will be told when it is back.');
  elsif v_open.id is not null and coalesce(v_last2[1], false) then
    update public.portal_outages set ended_at = now() where id = v_open.id;
    perform public._notify_admins('The admin portal is answering again. It was down for about '
      || greatest(1, round(extract(epoch from now() - v_open.started_at) / 60))::int || ' minutes.');
  end if;

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
    'last_ok',     (select ok from portal_uptime where ok is not null order by checked_at desc limit 1),
    -- 0138: memory
    'mem_now',      (select mem_used_mb from portal_uptime where mem_used_mb is not null order by checked_at desc limit 1),
    'mem_limit',    (select mem_limit_mb from portal_uptime where mem_limit_mb is not null order by checked_at desc limit 1),
    'mem_week_avg', (select round(avg(mem_used_mb)) from portal_uptime where checked_at > now() - interval '7 days'),
    'mem_week_max', (select max(greatest(mem_used_mb, mem_peak_mb)) from portal_uptime where checked_at > now() - interval '7 days'),
    'mem_samples',  (select count(mem_used_mb) from portal_uptime where checked_at > now() - interval '7 days')
  );
end $$;
revoke all on function public.portal_uptime_summary() from public, anon;
grant execute on function public.portal_uptime_summary() to authenticated;
