-- 0098 — Uptime alerts (industry pass 7, 7 Oct 2026).
--
-- When the portal misses two checks in a row, every admin gets a
-- notification; when it answers again, another says so and for how long it
-- was down. One alert per outage, never one per failed check.

alter table public.portal_uptime add column if not exists alerted boolean not null default false;

create table if not exists public.portal_outages (
  id         bigint generated always as identity primary key,
  started_at timestamptz not null,
  ended_at   timestamptz
);
alter table public.portal_outages enable row level security;
create policy portal_outages_admin_read on public.portal_outages for select using ((select public.is_admin()));

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
         error  = left(coalesce(r.error_msg, case when r.timed_out then 'timed out' end), 200)
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
