-- =============================================================
-- SmartSumbong — 0044 Notification mute preferences
--
-- A resident who mutes one notification kind used to have no way to do
-- that short of disabling push entirely at the OS level, which mutes
-- everything, including the dispatch update they actually want. This
-- gives them per-kind control instead.
--
-- Scope, deliberately narrow: muting only ever suppresses the FCM push
-- (the phone buzz) for that kind, never the row in public.notifications
-- itself. The in-app inbox (notifications_screen.dart) still shows every
-- notification regardless of mute state. Two reasons: first, a muted
-- category is "don't interrupt me for this," not "hide this from me
-- entirely" — a resident who muted status_change updates still expects
-- to see them when they open the app. Second, every RPC that inserts a
-- notification (review_report, dispatch functions, escalation sweeps,
-- and now review_report's abuse-flag path from 0040) would otherwise
-- need to know about mute state too, multiplying the surface this touches
-- for no real benefit — the one place a push actually gets sent is
-- send-dispatch-push, so that is the only place that needs to check.
--
-- 'verification' is deliberately left out of the mutable set entirely —
-- see set_notification_mute() below. Account-status changes (approved,
-- denied, suspended) are rare and important enough that muting them
-- isn't a real feature request, just an easy way to miss something that
-- matters.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists muted_notification_kinds notification_kind[] not null default '{}';

comment on column public.users.muted_notification_kinds is
  'Notification kinds this user does not want a phone push for. Never '
  'suppresses the public.notifications row itself -- only checked by '
  'send-dispatch-push before it calls FCM. See 0044.';

create or replace function public.set_notification_mute(
  p_kind   notification_kind,
  p_muted  boolean)
returns notification_kind[]
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_out notification_kind[];
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;

  if p_kind = 'verification' then
    raise exception 'Account-status notifications cannot be muted';
  end if;

  update public.users
     set muted_notification_kinds = case
           when p_muted then (
             select array_agg(distinct k) from (
               select unnest(coalesce(muted_notification_kinds, '{}')) as k
               union
               select p_kind
             ) t
           )
           else (
             select coalesce(array_agg(k), '{}') from (
               select unnest(coalesce(muted_notification_kinds, '{}')) as k
             ) t
             where k <> p_kind
           )
         end
   where id = v_uid
  returning muted_notification_kinds into v_out;

  if v_out is null then
    raise exception 'No such account';
  end if;

  return v_out;
end $$;

revoke execute on function public.set_notification_mute(notification_kind, boolean) from public, anon;
grant  execute on function public.set_notification_mute(notification_kind, boolean) to authenticated;

comment on function public.set_notification_mute(notification_kind, boolean) is
  'Self-service push-mute toggle, one kind at a time. verification is '
  'refused -- account-status changes are not muteable. Reading the '
  'current set needs no separate RPC: it is already on users, readable '
  'via the same self-select policy edit_profile_screen.dart already '
  'relies on.';

-- Verification. Run separately.
--
--   select public.set_notification_mute('status_change', true);
--   select public.set_notification_mute('status_change', false);
--   select public.set_notification_mute('verification', true); -- expect: refused
