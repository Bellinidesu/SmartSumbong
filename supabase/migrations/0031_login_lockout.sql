-- =============================================================
-- SmartSumbong — 0031 login lockout: 5 failed attempts, 30 minutes
--
-- Rose's resident item 8 and Group 5's TC-NCS-01-1 (26 Aug 2026) both
-- asked for this: repeated wrong-password attempts should lock the
-- account out for a while, not stay open to unlimited guessing.
--
-- WHY A NEW TABLE KEYED BY MOBILE NUMBER, NOT BY auth.users.id. A failed
-- attempt against a number nobody registered has no user id to key off
-- of, and this has to work before GoTrue has confirmed anything. It also
-- has to key off the *number the caller typed*, not the account it
-- might belong to, or the lockout itself would become a second
-- enumeration channel: if only registered numbers could lock, "locked
-- out" vs "just keeps failing" would tell an attacker a number exists.
-- Locking any typed number the same way after five misses, real account
-- or not, keeps that closed the same way migration 0021 already closed
-- the login error message.
--
-- WHY THREE SECURITY DEFINER FUNCTIONS AND NO DIRECT TABLE ACCESS. This
-- table has to be writable by an anonymous caller — there is no session
-- yet at the point a login fails. RLS is enabled with zero policies, and
-- table privileges are revoked outright, so the only way in is through
-- these three functions, each returning only a computed yes/no and a
-- number of seconds — never the raw row, which would let anyone read
-- another number's attempt count.
--
--   * check_login_lockout(mobile)   — call before attempting sign-in.
--   * register_login_failure(mobile) — call after GoTrue rejects the
--     password. Increments the count; sets a 30-minute lock at 5.
--   * clear_login_attempts(mobile)  — call after a successful sign-in.
--
-- KNOWN TRADE-OFF, WORTH SAYING OUT LOUD. Any lockout keyed purely by a
-- caller-supplied identifier — phone number, username, email, whichever
-- — can be flipped into a denial-of-service: someone who knows a
-- resident's number can fail their login five times on purpose and lock
-- the real resident out for thirty minutes, with no account of their own
-- involved. That is not a bug in this migration, it is the shape of
-- every lockout-by-identifier scheme, and it is what Rose and Group 5
-- asked for. If this becomes a real problem in practice, the fix is
-- outside SQL — a CAPTCHA after a couple of misses, or rate-limiting by
-- request origin at an edge layer this project does not have. Recorded
-- here rather than left silent.
--
-- Attempt rows are small and self-clear on success; nothing here prunes
-- old locked-and-expired rows, which is fine at barangay scale but worth
-- a periodic cleanup job if this table ever grows large.
-- =============================================================

set search_path = public, extensions;

create table public.login_attempts (
  mobile_number  text primary key,
  failed_count   integer not null default 0,
  locked_until   timestamptz,
  last_attempt_at timestamptz not null default now()
);

comment on table public.login_attempts is
  'Failed sign-in attempts per typed mobile number (not per account — '
  'see 0031''s header comment on why). Written only by this migration''s '
  'SECURITY DEFINER functions; no direct grants to anon or authenticated.';

alter table public.login_attempts enable row level security;
revoke all on public.login_attempts from public, anon, authenticated;

-- ---------- check_login_lockout ----------

create or replace function public.check_login_lockout(p_mobile text)
returns table(locked boolean, seconds_remaining integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_locked_until timestamptz;
begin
  if p_mobile is null or p_mobile !~ '^\+63[0-9]{10}$' then
    return query select false, 0;
    return;
  end if;

  select la.locked_until into v_locked_until
    from public.login_attempts la
   where la.mobile_number = p_mobile;

  if v_locked_until is not null and v_locked_until > now() then
    return query select true,
      greatest(0, ceil(extract(epoch from (v_locked_until - now())))::int);
  else
    return query select false, 0;
  end if;
end $$;

comment on function public.check_login_lockout(text) is
  'Call before attempting sign-in. True + seconds remaining if this '
  'number is currently locked; false otherwise. Malformed input is '
  'treated as never-locked rather than raising, since the caller is '
  'about to fail its own normalisation check anyway.';

revoke all on function public.check_login_lockout(text) from public;
grant execute on function public.check_login_lockout(text) to anon, authenticated;

-- ---------- register_login_failure ----------

create or replace function public.register_login_failure(p_mobile text)
returns table(locked boolean, seconds_remaining integer, attempts_remaining integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now    timestamptz := now();
  v_count  integer;
  v_locked timestamptz;
begin
  if p_mobile is null or p_mobile !~ '^\+63[0-9]{10}$' then
    return query select false, 0, 5;
    return;
  end if;

  -- One INSERT ... ON CONFLICT DO UPDATE, not an insert-then-update pair.
  -- A two-statement version (a writable CTE feeding a second UPDATE) was
  -- tried first and is wrong: every sub-statement in a single WITH runs
  -- against the same snapshot, so a second statement's plain table scan
  -- cannot see a row the first one just inserted, and on a brand-new
  -- number the trailing UPDATE silently matches zero rows every time.
  -- Verified against a scratch database before this migration shipped —
  -- see the QA doc. The failed_count CASE has to be duplicated inside
  -- the locked_until CASE because an ON CONFLICT DO UPDATE SET list has
  -- no FROM clause to compute it once and reuse it.
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

comment on function public.register_login_failure(text) is
  'Call after GoTrue rejects a password for this number — never for '
  'not-confirmed, suspended, or rate-limited responses, which are not '
  'a guessed password. Returns whether this attempt just triggered the '
  '30-minute lock, and how many attempts remain if not.';

revoke all on function public.register_login_failure(text) from public;
grant execute on function public.register_login_failure(text) to anon, authenticated;

-- ---------- clear_login_attempts ----------

create or replace function public.clear_login_attempts(p_mobile text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.login_attempts where mobile_number = p_mobile;
end $$;

comment on function public.clear_login_attempts(text) is
  'Call once sign-in succeeds. Deletes the row outright rather than '
  'zeroing it — no row reads the same as zero attempts in '
  'check_login_lockout, and this keeps the table from growing with '
  'every ordinary successful login.';

revoke all on function public.clear_login_attempts(text) from public;
grant execute on function public.clear_login_attempts(text) to anon, authenticated;

-- Verification:
--
--   select p.proname, p.prosecdef,
--          has_function_privilege('anon', p.oid, 'execute') as anon_ok
--     from pg_proc p
--    where p.proname in ('check_login_lockout', 'register_login_failure',
--                         'clear_login_attempts');
--
-- Expect prosecdef = true and anon_ok = true on all three rows.
