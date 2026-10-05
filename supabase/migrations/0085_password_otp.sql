-- 0085 — Forgot password by SMS code (5 Oct 2026).
--
-- Rose's design: Forgot Password → Verify OTP → Reset Password → Success.
-- Codes go out through Semaphore (Philippine SMS gateway) from the
-- password-otp Edge Function, which holds the API key as a secret. The
-- counter reset (0028/0029) stays as the route for residents with no load
-- or no signal.
--
-- Only a keyed hash of each code is kept, never the code. A code expires
-- after 10 minutes, allows 5 tries, and works once; asking for a new one
-- retires the old. The function, not this table, enforces the limits; the
-- table is closed to everyone but the service role.

set search_path = public, extensions;

create table if not exists public.password_otps (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  code_hash   text not null,
  expires_at  timestamptz not null,
  attempts    smallint not null default 0,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

comment on table public.password_otps is
  'One-time SMS codes for resetting a password (0085). Keyed hashes only; '
  'read and written by the password-otp Edge Function with the service role.';

create index if not exists password_otps_user_idx on public.password_otps (user_id, created_at desc);

alter table public.password_otps enable row level security;
-- No policies: nobody but the service role (the Edge Function) touches it.
revoke all on public.password_otps from public, anon, authenticated;
