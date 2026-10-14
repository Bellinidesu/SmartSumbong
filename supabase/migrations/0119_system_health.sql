-- 0119: health alerts beyond uptime (backend review, 10 Oct 2026).
--
-- The portal's downtime (0098) and crashes (0097) already reach the
-- admins. These did not:
--   - a scheduled job failing (the overdue sweeps, retention, the photo
--     cleanup): pg_cron records it in cron.job_run_details and nobody looks;
--   - the database nearing the free plan's 500 MB;
--   - the identity-photo cleanup (0118) falling behind;
--   - an Edge Function failing (push, sign-in codes, uploads, cleanup).
--
-- check_system_health() runs hourly. Each problem raises one alert, told
-- to every admin once, shown on Settings -> System status until it clears,
-- and announced again only if it comes back after clearing. Edge Functions
-- now log their failures to portal_errors as source 'function', so they
-- show in the same Recent errors list.

-- ---------- Edge Function errors in portal_errors --------------------------

alter table public.portal_errors drop constraint if exists portal_errors_source_check;
alter table public.portal_errors
  add constraint portal_errors_source_check check (source in ('server', 'browser', 'function'));

create or replace function public.log_portal_error(p_source text, p_page text, p_message text, p_detail text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_page text := left(coalesce(nullif(trim(p_page), ''), '?'), 200);
  v_msg  text := left(coalesce(nullif(trim(p_message), ''), '(no message)'), 500);
  v_sig  text;
begin
  if p_source not in ('server', 'browser', 'function') then return; end if;
  -- 0119: only the Edge Functions themselves (service role) log as 'function'.
  if p_source = 'function' and coalesce(auth.role(), '') <> 'service_role' then return; end if;
  v_sig := md5(p_source || '|' || v_page || '|' || v_msg);
  insert into public.portal_errors (source, page, message, detail, signature)
  values (p_source, v_page, v_msg, left(p_detail, 2000), v_sig)
  on conflict (signature) do update
     set count = portal_errors.count + 1, last_seen = now(),
         detail = coalesce(excluded.detail, portal_errors.detail);
  -- Keep the table small: the 500 most recently seen.
  delete from public.portal_errors where id in (
    select id from public.portal_errors order by last_seen desc offset 500);
end $$;
revoke all on function public.log_portal_error(text, text, text, text) from public;
grant execute on function public.log_portal_error(text, text, text, text) to anon, authenticated, service_role;

-- ---------- alerts ---------------------------------------------------------

create table if not exists public.system_alerts (
  key         text primary key,
  message     text not null,
  raised_at   timestamptz not null default now(),
  checked_at  timestamptz not null default now(),
  cleared_at  timestamptz
);

comment on table public.system_alerts is
  '0119: one row per kind of problem check_system_health() watches. Open '
  'while cleared_at is null; admins are told when it opens.';

alter table public.system_alerts enable row level security;
create policy system_alerts_admin_read on public.system_alerts
  for select using ((select public.is_admin()));

/** Opens (and announces) or refreshes one alert. */
create or replace function public._raise_alert(p_key text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_was_open boolean;
begin
  select cleared_at is null into v_was_open from public.system_alerts where key = p_key;
  insert into public.system_alerts as a (key, message)
  values (p_key, p_message)
  on conflict (key) do update
     set message = excluded.message,
         checked_at = now(),
         raised_at = case when a.cleared_at is null then a.raised_at else now() end,
         cleared_at = null;
  if not coalesce(v_was_open, false) then
    perform public._notify_admins('System check: ' || p_message);
  end if;
end $$;

create or replace function public._clear_alerts_except(p_prefix text, p_keep text[])
returns void
language sql
security definer
set search_path = public
as $$
  update public.system_alerts set cleared_at = now(), checked_at = now()
   where key like p_prefix || '%' and cleared_at is null and not (key = any (p_keep));
$$;

revoke all on function public._raise_alert(text, text) from public, anon, authenticated;
revoke all on function public._clear_alerts_except(text, text[]) from public, anon, authenticated;

create or replace function public.check_system_health()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep  text[] := '{}';
  r       record;
  v_bytes bigint := pg_database_size(current_database());
  v_limit bigint := 500 * 1024 * 1024;  -- Supabase free plan
  v_stuck integer;
  v_fn    integer;
begin
  -- Scheduled jobs that failed in the last day, by name.
  if to_regclass('cron.job_run_details') is not null then
    for r in execute $q$
      select j.jobname, count(*) as n, max(d.return_message) as why
        from cron.job_run_details d join cron.job j on j.jobid = d.jobid
       where d.status = 'failed' and d.start_time > now() - interval '1 day'
       group by j.jobname $q$
    loop
      v_keep := v_keep || ('job:' || r.jobname);
      perform public._raise_alert('job:' || r.jobname, format(
        'the scheduled job %s failed %s time%s in the last day (%s).',
        r.jobname, r.n, case when r.n = 1 then '' else 's' end, left(coalesce(r.why, 'no message'), 160)));
    end loop;
  end if;
  perform public._clear_alerts_except('job:', v_keep);

  -- Database size against the free plan.
  if v_bytes > v_limit * 0.8 then
    perform public._raise_alert('db_size', format(
      'the database is %s of the free plan''s 500 MB. Archive old records or move to a paid plan.',
      pg_size_pretty(v_bytes)));
  else
    perform public._clear_alerts_except('db_size', '{}');
  end if;

  -- Identity photos that should have been deleted a week ago.
  select count(*) into v_stuck from public.media_trash
   where queued_at < now() - interval '14 days' and not public.identity_media_in_use(url);
  if v_stuck > 0 then
    perform public._raise_alert('media_cleanup', format(
      '%s identity photo%s should have been deleted from Cloudinary by now. Check that media-cleanup is deployed and its Vault secrets are set.',
      v_stuck, case when v_stuck = 1 then '' else 's' end));
  else
    perform public._clear_alerts_except('media_cleanup', '{}');
  end if;

  -- Edge Function failures in the last day.
  select coalesce(sum(count), 0) into v_fn from public.portal_errors
   where source = 'function' and last_seen > now() - interval '1 day';
  if v_fn > 0 then
    perform public._raise_alert('functions', format(
      'Edge Functions failed %s time%s in the last day. See Settings -> System status -> Recent errors.',
      v_fn, case when v_fn = 1 then '' else 's' end));
  else
    perform public._clear_alerts_except('functions', '{}');
  end if;
end $$;

revoke all on function public.check_system_health() from public, anon, authenticated;

select cron.schedule('system-health', '5 * * * *', $$ select public.check_system_health() $$);

-- ---------- pausing report filing during an incident -----------------------
-- docs/INCIDENTS.md: when something is broken badly enough that new
-- complaints would be lost or mishandled, the barangay can stop new filings
-- with one update, and residents are told why instead of failing silently.
--   update operational_settings set filing_paused = true,
--     filing_paused_message = 'Filing is paused while we fix a problem. For urgent matters call the barangay hall.' where id = 1;

alter table public.operational_settings
  add column if not exists filing_paused boolean not null default false,
  add column if not exists filing_paused_message text;

create or replace function public.enforce_daily_report_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit   integer;
  v_paused  boolean;
  v_message text;
begin
  if new.resident_id is null or new.resident_id is distinct from (select auth.uid()) then
    return new;  -- not a resident filing for themselves (jobs, tests as postgres)
  end if;
  select max_reports_per_day, filing_paused, filing_paused_message
    into v_limit, v_paused, v_message
    from public.operational_settings where id = 1;
  if coalesce(v_paused, false) then
    raise exception '%', coalesce(nullif(trim(v_message), ''),
      'Filing new reports is paused for a moment. Please try again later, or call the barangay hall for anything urgent.')
      using errcode = 'check_violation';
  end if;
  if (select count(*) from public.reports r
       where r.resident_id = new.resident_id
         and r.created_at > now() - interval '24 hours') >= coalesce(v_limit, 20) then
    raise exception 'You have filed % reports in the last 24 hours, the most allowed. Please try again tomorrow, or visit the barangay hall.', coalesce(v_limit, 20)
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
