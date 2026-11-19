-- 0183: a look-around tells the tanod, from the database (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0183". Goes with the one-line change in admin/assets/js/spatial.js (deploy with the portal).
--
-- The portal's "Look around" inserts a look_shares row and then tries to insert the tanod's notification itself
-- (spatial.js, lkSendGo). notifications has no insert policy for anyone signed in, so that second insert is refused every time and
-- the error is swallowed: the tanod's list and push never carried it (proved on a copy built from the migrations: an administrator
-- inserts the share, then the notification insert fails with "violates row-level security policy"). A trigger does it instead, as
-- every other notification is made, and the browser stops trying.

set search_path = public, extensions;

create or replace function public._look_share_notice()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, report_id, kind, message)
  values (new.tanod_id, new.report_id, 'look_around', left('From the barangay: ' || new.message, 500));
  return new;
end $$;
revoke all on function public._look_share_notice() from public, anon, authenticated;

drop trigger if exists look_share_notice on public.look_shares;
create trigger look_share_notice after insert on public.look_shares
  for each row execute function public._look_share_notice();
