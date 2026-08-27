-- =============================================================
-- SmartSumbong — 0035 Device tokens for real push notifications
--
-- 0034 got the resident notified in the notifications table when a tanod
-- is actually dispatched. That is still only visible if the resident
-- reopens the app — there is no push notification system anywhere in
-- this project (the README lists it as "planned"). This migration is the
-- database half of closing that: a place to keep each signed-in device's
-- Firebase Cloud Messaging token, so a Database Webhook + Edge Function
-- (supabase/functions/send-dispatch-push) can turn a new notifications
-- row into an actual phone banner.
--
-- Registration goes through a security-definer RPC rather than a direct
-- insert policy: a resident who could INSERT into device_tokens directly
-- could register a token against ANY user_id, which would let them
-- receive (or spam) another account's push notifications. The RPC pins
-- user_id to auth.uid(), full stop.
-- =============================================================

set search_path = public, extensions;

create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  fcm_token   text not null,
  platform    text not null default 'android' check (platform in ('android', 'ios')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, fcm_token)
);

create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- A user may see their own registered devices (Settings could someday
-- list "notifications active on 2 devices"); nobody may read anyone
-- else's, and nobody writes this table directly — see the RPCs below.
create policy device_tokens_own_read on public.device_tokens
  for select using (user_id = auth.uid());

create or replace function public.register_device_token(
  p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if p_token is null or char_length(trim(p_token)) = 0 then
    raise exception 'A device token is required';
  end if;

  insert into public.device_tokens (user_id, fcm_token, platform)
  values (auth.uid(), trim(p_token), coalesce(nullif(trim(p_platform), ''), 'android'))
  on conflict (user_id, fcm_token)
  do update set updated_at = now(), platform = excluded.platform;
end $$;

revoke execute on function public.register_device_token(text, text) from public, anon;
grant  execute on function public.register_device_token(text, text) to authenticated;

-- Called at sign-out so a token for a logged-out account stops receiving
-- that account's notifications on a shared or reused device.
create or replace function public.unregister_device_token(p_token text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  delete from public.device_tokens
   where user_id = auth.uid() and fcm_token = p_token;
end $$;

revoke execute on function public.unregister_device_token(text) from public, anon;
grant  execute on function public.unregister_device_token(text) to authenticated;

comment on table public.device_tokens is
  'One row per (user, installed app) FCM registration. Written only via '
  'register_device_token()/unregister_device_token() — never directly, so '
  'a user can only ever register a token against their own account. Read '
  'by supabase/functions/send-dispatch-push using the service role key, '
  'which bypasses RLS by design.';
