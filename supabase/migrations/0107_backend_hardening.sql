-- 0107: backend review fixes (10 Oct 2026).
--
--   1. Login lockout (0031). The app calls these three functions itself,
--      with the public key, so anyone could too:
--        - clear_login_attempts('+639…') wiped any number's count, which
--          undid the lockout for whoever called it;
--        - register_login_failure('+639…') five times locked any resident
--          out for 30 minutes, for as many numbers as one script could
--          list, with none of GoTrue's own rate limit in the way.
--      Now clearing only works on the caller's own number once signed in
--      (which is when the app calls it), and failures are counted at most
--      20 per network address per 15 minutes. Past that a failure is not
--      counted: the throttle fails open, so a resident is never refused
--      sign-in by it; the worst a shared address (a carrier's CGNAT, the
--      barangay hall's wifi) does is make the lockout less strict for a
--      while. GoTrue's own per-address sign-in limit is still the hard
--      control; this lockout stays a layer on top.
--   2. SMS codes (0085, 0104). The Edge Function read `attempts`, compared,
--      then wrote attempts + 1, so many guesses sent at once all saw the
--      same count and the 5-try limit did not hold. otp_attempt() locks
--      the row and counts in one statement. revoke_user_sessions() signs a
--      user out everywhere after an SMS password reset.
--   3. The two sweeps pg_cron runs were callable by anyone through the API.
--      Harmless (each is idempotent) but nobody else should call them.
--   4. A resident may file at most max_reports_per_day reports in any 24
--      hours (default 20; operational_settings), whichever way the row
--      arrives. A resend of an already-filed outbox report is not a new
--      row, so it never counts.

-- ---------- 1. login lockout ----------------------------------------------

create table if not exists public.login_failure_sources (
  source        text primary key,
  window_start  timestamptz not null default now(),
  hits          integer not null default 0
);

comment on table public.login_failure_sources is
  '0107: how many failed sign-ins each network address has reported in the '
  'current 15-minute window. Read and written only by register_login_failure.';

alter table public.login_failure_sources enable row level security;
-- No policies: only the definer function below touches it.

create or replace function public.request_source()
returns text
language sql
stable
set search_path = public
as $$
  -- The caller's address as Supabase's gateway saw it. cf-connecting-ip is
  -- set by Cloudflare and cannot be supplied by the client; the others are
  -- fallbacks. Null outside an API request (SQL editor, cron, tests).
  select nullif(trim(coalesce(
           h ->> 'cf-connecting-ip',
           split_part(h ->> 'x-forwarded-for', ',', 1),
           h ->> 'x-real-ip')), '')
    from (select nullif(current_setting('request.headers', true), '')::json as h) s
$$;

revoke all on function public.request_source() from public, anon, authenticated;

create or replace function public.register_login_failure(p_mobile text)
returns table(locked boolean, seconds_remaining integer, attempts_remaining integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now    timestamptz := now();
  v_source text := public.request_source();
  v_hits   integer;
  v_count  integer;
  v_locked timestamptz;
begin
  if p_mobile is null or p_mobile !~ '^\+63[0-9]{10}$' then
    return query select false, 0, 5;
    return;
  end if;

  if v_source is not null then
    insert into public.login_failure_sources as s (source, window_start, hits)
    values (v_source, v_now, 1)
    on conflict (source) do update
       set hits = case when s.window_start < v_now - interval '15 minutes' then 1 else s.hits + 1 end,
           window_start = case when s.window_start < v_now - interval '15 minutes' then v_now else s.window_start end
    returning hits into v_hits;

    if v_hits > 20 then
      return query select false, 0, 5;
      return;
    end if;

    -- Keep the table to the addresses seen today.
    if v_hits = 1 then
      delete from public.login_failure_sources where window_start < v_now - interval '1 day';
    end if;
  end if;

  -- Unchanged from 0031 from here on.
  insert into public.login_attempts (mobile_number, failed_count, locked_until, last_attempt_at)
  values (p_mobile, 1, null, v_now)
  on conflict (mobile_number) do update
     set failed_count = case
           when login_attempts.locked_until is not null
                and login_attempts.locked_until <= v_now
           then 1
           else login_attempts.failed_count + 1
         end,
         locked_until = case
           when (case
                   when login_attempts.locked_until is not null
                        and login_attempts.locked_until <= v_now
                   then 1
                   else login_attempts.failed_count + 1
                 end) >= 5
           then v_now + interval '30 minutes'
           else null
         end,
         last_attempt_at = v_now
  returning failed_count, locked_until
    into v_count, v_locked;

  if v_count >= 5 then
    return query select true,
      greatest(0, ceil(extract(epoch from (v_locked - v_now)))::int),
      0;
  else
    return query select false, 0, greatest(0, 5 - v_count);
  end if;
end $$;

revoke all on function public.register_login_failure(text) from public;
grant execute on function public.register_login_failure(text) to anon, authenticated;

create or replace function public.clear_login_attempts(p_mobile text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- Only your own number, and only once signed in: the app calls this
  -- right after a successful sign-in, never before.
  delete from public.login_attempts la
   using public.users u
   where u.id = (select auth.uid())
     and u.mobile_number = p_mobile
     and la.mobile_number = p_mobile;
end $$;

comment on function public.clear_login_attempts(text) is
  'Call once sign-in succeeds. 0107: clears only the signed-in caller''s own '
  'number; anyone else''s, or a call made while signed out, does nothing.';

revoke all on function public.clear_login_attempts(text) from public, anon;
grant execute on function public.clear_login_attempts(text) to authenticated;

-- ---------- 2. SMS codes ---------------------------------------------------

create or replace function public.otp_attempt(
  p_user uuid, p_purpose text, p_hash text, p_max integer default 5)
returns table(outcome text, attempts_left integer, otp_id uuid, new_mobile text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v public.password_otps%rowtype;
begin
  select * into v
    from public.password_otps o
   where o.user_id = p_user and o.purpose = p_purpose and o.used_at is null
   order by o.created_at desc
   limit 1
   for update;

  if not found or v.expires_at < now() or v.attempts >= p_max then
    return query select 'expired', 0, null::uuid, null::text;
    return;
  end if;

  if v.code_hash = p_hash then
    -- Marked used by the caller once the change it unlocks has gone through.
    return query select 'ok', p_max - v.attempts, v.id, v.new_mobile;
    return;
  end if;

  update public.password_otps set attempts = attempts + 1 where id = v.id;
  return query select 'wrong', greatest(0, p_max - v.attempts - 1), v.id, null::text;
end $$;

comment on function public.otp_attempt(uuid, text, text, integer) is
  '0107: checks one guess at the newest live SMS code, counting a wrong one '
  'under a row lock so parallel guesses cannot share a try. password-otp only.';

revoke all on function public.otp_attempt(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function public.otp_attempt(uuid, text, text, integer) to service_role;

create or replace function public.revoke_user_sessions(p_user uuid)
returns void
language sql
security definer
set search_path = public, auth
as $$
  -- Refresh tokens go with their session; an access token already issued
  -- runs out within the hour.
  delete from auth.sessions where user_id = p_user;
$$;

comment on function public.revoke_user_sessions(uuid) is
  '0107: signs a user out on every device. Called by password-otp after an '
  'SMS password reset.';

revoke all on function public.revoke_user_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;

-- ---------- 3. cron-only sweeps --------------------------------------------

revoke execute on function public.sweep_overdue_reports() from public, anon, authenticated;
revoke execute on function public.sweep_overdue_verifications() from public, anon, authenticated;

-- ---------- 4. daily filing limit ------------------------------------------

alter table public.operational_settings
  add column if not exists max_reports_per_day smallint not null default 20
    check (max_reports_per_day between 1 and 200);

comment on column public.operational_settings.max_reports_per_day is
  '0107: most reports one resident may file in any 24 hours.';

create or replace function public.enforce_daily_report_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer;
begin
  if new.resident_id is null or new.resident_id is distinct from (select auth.uid()) then
    return new;  -- not a resident filing for themselves (jobs, tests as postgres)
  end if;
  select max_reports_per_day into v_limit from public.operational_settings where id = 1;
  if (select count(*) from public.reports r
       where r.resident_id = new.resident_id
         and r.created_at > now() - interval '24 hours') >= coalesce(v_limit, 20) then
    raise exception 'You have filed % reports in the last 24 hours, the most allowed. Please try again tomorrow, or visit the barangay hall.', coalesce(v_limit, 20)
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists reports_daily_limit on public.reports;
create trigger reports_daily_limit
  before insert on public.reports
  for each row execute function public.enforce_daily_report_limit();
-- The count uses reports_resident_idx (0060) on (resident_id, created_at desc).
