-- =============================================================
-- 0193_auth_triggers_idempotent  (DRAFT, backend round 3, 25 Nov 2026. NOT APPLIED: it moves to supabase/migrations
-- and is pushed only when Ace says "apply 0193".)
--
-- Why. On 23-24 Nov new residents could not register or sign in: live auth.users had lost both of its triggers,
--   on_auth_user_created         AFTER INSERT  -> public.handle_new_auth_user()          (0004: makes the public.users row)
--   auth_users_confirm_synthetic BEFORE INSERT -> public.confirm_synthetic_auth_email()  (0022: confirms the derived
--                                                  @auth.smartsumbong.local address, which can never receive mail)
-- Ace re-created them by hand on 24-25 Nov (checked 25 Nov: identical to 0004/0022). Most likely they were lost in the
-- 7 Nov Mumbai -> Singapore move: `supabase db dump` leaves out Supabase's managed schemas (auth, storage), and a trigger
-- ON auth.users belongs to auth.users, so it never travels with a dump even though its function (public) does. Migration
-- history said 0004 and 0022 were applied, so `db push` could not put them back either.
--
-- What. The same two triggers, re-created idempotently (drop if exists + create, in the migration's one transaction, so
-- there is no moment without them). On live today this changes nothing: the definitions are the ones already there.
-- Its real use is as THE restore step: after any restore or project move, run this file in the SQL editor (a migration
-- that is already marked applied is not re-run by `db push`), then `python tools/sweep/drift_check.py` (docs/OPERATIONS.md).
--
-- Test: supabase/tests/77_auth_triggers.sql (both triggers exist with the right timing and function, a new phone sign-up
-- gets its users row and a confirmed address, a real address is left unconfirmed). Undo: supabase/drafts/0193_undo.sql.
-- =============================================================

set search_path = public, extensions;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

drop trigger if exists auth_users_confirm_synthetic on auth.users;
create trigger auth_users_confirm_synthetic
  before insert on auth.users
  for each row execute function public.confirm_synthetic_auth_email();

do $$
begin
  if (select count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal and tgenabled = 'O'
        and tgname in ('on_auth_user_created', 'auth_users_confirm_synthetic')) <> 2 then
    raise exception '0193: the two auth.users triggers are not both in place';
  end if;
end $$;
