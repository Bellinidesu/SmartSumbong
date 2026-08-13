-- =============================================================
-- SmartSumbong — 0022 Synthetic addresses are confirmed at creation
--
-- 0021 made the auth identity a synthetic address derived from the
-- mobile number. Those addresses are unresolvable by design — .local is
-- reserved by RFC 6762 — so no confirmation mail can ever be delivered
-- to one, and email_confirmed_at can never be set the normal way.
--
-- GoTrue refuses sign-in for an unconfirmed address. So with "Confirm
-- email" enabled in the Auth dashboard, every account created through
-- the app registers successfully and can then never log in. The failure
-- is silent from the applicant's side: signup shows a success screen,
-- and login gives an error that reads like a wrong password.
--
-- That setting has been switched back on twice during development
-- without anyone changing it deliberately. Which is the real lesson
-- here: this cannot depend on a dashboard toggle nobody documented and
-- nothing enforces. The barangay has no IT staff, the project turns over
-- every three years, and "log in is broken for every new resident" is a
-- long way from "someone flipped a switch in a settings page".
--
-- So the schema settles it. A synthetic address is confirmed at the
-- moment it is created, in the same transaction, because there is
-- nothing to confirm — the applicant proved nothing by owning it and
-- never could. Real identity verification is the admin comparing ID,
-- face and name (Verify User Account UC); that is the check that
-- matters, and it is unaffected.
--
-- This trigger deliberately touches only addresses in the synthetic
-- domain. An admin account created by hand with a real address still
-- goes through normal confirmation.
-- =============================================================

set search_path = public, extensions;

create or replace function public.confirm_synthetic_auth_email()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- Only the derived domain. A real address created for an admin by
  -- hand keeps whatever confirmation flow it came with.
  if new.email like '%@auth.smartsumbong.local'
     and new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end $$;

comment on function public.confirm_synthetic_auth_email() is
  'Marks derived auth addresses confirmed at creation. They cannot '
  'receive mail — .local is unresolvable — so an unconfirmed one is an '
  'account that can never sign in. Identity is verified by the barangay '
  'admin against ID and selfie, not by proving control of a mailbox that '
  'does not exist.';

drop trigger if exists auth_users_confirm_synthetic on auth.users;

create trigger auth_users_confirm_synthetic
  before insert on auth.users
  for each row execute function public.confirm_synthetic_auth_email();

-- ---------- backfill ------------------------------------------
-- Accounts created between 0021 and this migration are unconfirmed and
-- cannot sign in.

update auth.users
   set email_confirmed_at = now()
 where email like '%@auth.smartsumbong.local'
   and email_confirmed_at is null;

-- Verification. Run separately.
--
--   select 'trigger' as part,
--          case when exists (select 1 from pg_trigger
--                             where tgname = 'auth_users_confirm_synthetic')
--          then 'OK' else 'MISSING' end as state
--   union all
--   select 'no unconfirmed synthetic accounts',
--          case when count(*) = 0 then 'OK'
--               else 'STILL ' || count(*)::text end
--     from auth.users
--    where email like '%@auth.smartsumbong.local'
--      and email_confirmed_at is null;
--
-- Both OK. Then register a fresh account through the app and sign in
-- with it without touching the database — that is the test this
-- migration exists to make pass.
