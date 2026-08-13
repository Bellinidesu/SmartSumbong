-- =============================================================
-- SmartSumbong — 0020 Overdue verification notice, once only
--
-- sweep_overdue_verifications() notifies every admin about every pending
-- account whose two-hour window has passed. It runs every ten minutes,
-- and it selects on a condition that stays true — so it re-notifies on
-- every run for as long as the account stays pending. An application left
-- overnight produces roughly ninety identical rows per admin.
--
-- That is not merely untidy. The notification list is how an admin sees
-- what needs attention; ninety copies of one warning buries everything
-- else, and an admin who learns to ignore that list is an admin who
-- misses the next real one. The failure mode is a queue nobody reads.
--
-- The other two sweeps do not have this problem, and the difference is
-- instructive: sweep_overdue_reports() and sweep_unaccepted_dispatches()
-- both notify off rows they have just UPDATEd, in a CTE, so a row can
-- only be picked up once. This one notifies off a plain SELECT.
--
-- Fix: record when the notice was sent, and only send when it has not
-- been. Cleared whenever an account re-enters pending, so a resident who
-- is denied and applies again gets a fresh window rather than silence.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists verification_overdue_notified_at timestamptz;

comment on column public.users.verification_overdue_notified_at is
  'When admins were told this account passed its two-hour verification '
  'window. Non-null suppresses further notices; cleared on re-entry to '
  'pending. Bookkeeping for sweep_overdue_verifications(), not a '
  'service-level record — verification_due_at is that.';

-- ---------- the sweep, made idempotent ------------------------

create or replace function public.sweep_overdue_verifications()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- Mark first and notify from what was marked, matching the shape of
  -- the other two sweeps. A row can only be returned by the UPDATE once,
  -- so it can only generate one round of notifications however often
  -- this runs.
  with newly_overdue as (
    update public.users u
       set verification_overdue_notified_at = now()
     where u.verification_status = 'pending'
       and u.verification_due_at < now()
       and u.verification_overdue_notified_at is null
    returning u.id, u.full_name
  )
  insert into public.notifications (user_id, kind, message)
  select a.id, 'sla_warning',
         'Account verification for ' || n.full_name
           || ' has passed the 2-hour limit.'
    from newly_overdue n
    cross join public.users a
   where a.role = 'admin'
     and not a.is_suspended;
end $$;

comment on function public.sweep_overdue_verifications() is
  'Notifies admins once per account when its two-hour verification window '
  'elapses. Idempotent: the UPDATE that marks the account is what drives '
  'the notification, so repeated runs cannot duplicate it.';

-- ---------- clear the mark on re-entry to pending --------------
-- A denied applicant who registers again, or an account an admin returns
-- to the queue, starts a new window and must be able to raise a new
-- notice. Without this the second wait is silent.

create or replace function public.reset_verification_overdue_mark()
returns trigger
language plpgsql
as $$
begin
  if new.verification_status = 'pending'
     and old.verification_status is distinct from 'pending' then
    new.verification_overdue_notified_at := null;
  end if;
  return new;
end $$;

drop trigger if exists users_reset_overdue_mark on public.users;

create trigger users_reset_overdue_mark
  before update on public.users
  for each row execute function public.reset_verification_overdue_mark();

-- ---------- backfill ------------------------------------------
-- Accounts already past their window would each fire one more notice on
-- the next run, which is correct and useful — admins should know they are
-- waiting. Nothing to backfill. Existing duplicate notifications are left
-- alone: they are a record of what the system did, and 0015's audit chain
-- treats history as evidence rather than something to tidy.

-- Verification. Run separately.
--
--   select full_name, verification_status, verification_due_at,
--          verification_overdue_notified_at
--     from public.users
--    where verification_status = 'pending';
--
--   -- Run the sweep twice; the second must add no rows.
--   select count(*) as before from public.notifications where kind = 'sla_warning';
--   select public.sweep_overdue_verifications();
--   select count(*) as after_first from public.notifications where kind = 'sla_warning';
--   select public.sweep_overdue_verifications();
--   select count(*) as after_second from public.notifications where kind = 'sla_warning';
