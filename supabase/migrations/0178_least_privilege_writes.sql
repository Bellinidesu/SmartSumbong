-- 0178: write rights only where something signed in really writes (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0178".
--
-- Found by the sweep: the API roles hold INSERT, UPDATE and DELETE on every table and row level security alone decides, so
-- every policy that is a little too wide is a hole. Several tables have write policies for administrators that no page of the
-- portal and no screen of the app uses (every change goes through a security definer function, which does not need them):
--
--   dispatches          an in-scope administrator who is not the case's handler could DELETE a dispatch (the tanod's assignment
--                       history), and the handler could INSERT one without admin_dispatch's checks (dispatch cap, tanod on duty)
--   sla_extensions      the audited deadline extensions: written directly, they skip the cap that sends a request to a higher official
--   retirement_requests the decisions of a retirement: written directly, they skip the Kagawad's endorsement and the super admins' vote
--   users               INSERT and DELETE by a super admin (accounts are made by the sign-up trigger and create_admin_account, and
--                       removed by delete-account with the service role)
--   look_shares         DELETE, and an administrator's UPDATE of what was sent (only the tanod marks it seen: read_at)
--   notifications       a person could rewrite the text, kind and case of their own notifications (only is_read is ever changed)
--
-- What stays: the portal's "Look around" still inserts a look_shares row; the tanod still marks it seen; people still mark their
-- notifications read. Anything else goes through the functions, as it already does.

set search_path = public, extensions;

-- ---------- tables nothing signed in writes directly ----------
revoke insert, update, delete on public.dispatches from authenticated, anon;
drop policy if exists dispatches_admin_insert on public.dispatches;
drop policy if exists dispatches_admin_update on public.dispatches;
drop policy if exists dispatches_admin_delete on public.dispatches;

revoke insert, update, delete on public.sla_extensions from authenticated, anon;
drop policy if exists sla_extensions_admin_insert on public.sla_extensions;
drop policy if exists sla_extensions_admin_update on public.sla_extensions;
drop policy if exists sla_extensions_admin_delete on public.sla_extensions;

revoke insert, update, delete on public.retirement_requests from authenticated, anon;
drop policy if exists retirement_requests_super_insert on public.retirement_requests;
drop policy if exists retirement_requests_super_update on public.retirement_requests;
drop policy if exists retirement_requests_super_delete on public.retirement_requests;

revoke insert, delete on public.users from authenticated, anon;
revoke update on public.users from anon;
drop policy if exists users_super_insert on public.users;
drop policy if exists users_super_delete on public.users;

-- ---------- tables written only in one column ----------
-- look_shares: the portal inserts the share, the tanod sets read_at
revoke update, delete on public.look_shares from authenticated, anon;
grant update (read_at) on public.look_shares to authenticated;
drop policy if exists look_shares_admin_update on public.look_shares;
drop policy if exists look_shares_admin_delete on public.look_shares;

-- notifications: people mark their own read, nothing else
revoke update on public.notifications from authenticated, anon;
grant update (is_read) on public.notifications to authenticated;
