-- 0115: notification retention, and signing people out when their access
-- changes (backend review, 10 Oct 2026).
--
--   1. notifications grew forever: every status change, dispatch and
--      reminder adds a row per recipient and nothing removed them. A daily
--      job now deletes read notifications after 90 days and any after a
--      year. The complaint's own history (status_logs, the threads) is
--      untouched; only the inbox copy goes.
--   2. Sessions. A password reset at the counter (admin_reset_password,
--      which sets must_change_password), a suspension and a retirement
--      changed the database but left every phone already signed in with a
--      working refresh token. Now each one ends the person's sessions:
--      their next token refresh fails and the app asks them to sign in,
--      which is where the temporary password, suspension and retirement
--      are checked. An access token already issued runs out within the hour.

-- ---------- 1. notification retention -------------------------------------

create index if not exists notifications_created_idx
  on public.notifications (created_at);

create or replace function public.purge_old_notifications()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.notifications
   where (is_read and created_at < now() - interval '90 days')
      or created_at < now() - interval '365 days';
$$;

comment on function public.purge_old_notifications() is
  '0115: daily. Read notifications go after 90 days, any after a year.';

revoke all on function public.purge_old_notifications() from public, anon, authenticated;

select cron.schedule('purge-old-notifications', '20 3 * * *',
  $$ select public.purge_old_notifications() $$);

-- ---------- 2. sign out on reset, suspension, retirement ------------------

create or replace function public.end_sessions_on_access_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  delete from auth.sessions where user_id = new.id;
  return new;
end $$;

comment on function public.end_sessions_on_access_change() is
  '0115: ends every session of a user whose password was reset by the '
  'barangay, or who was suspended or retired.';

revoke all on function public.end_sessions_on_access_change() from public, anon, authenticated;

drop trigger if exists users_end_sessions on public.users;
create trigger users_end_sessions
  after update of must_change_password, is_suspended, is_retired on public.users
  for each row
  when ((new.must_change_password and not old.must_change_password)
     or (new.is_suspended and not old.is_suspended)
     or (new.is_retired and not old.is_retired))
  execute function public.end_sessions_on_access_change();
