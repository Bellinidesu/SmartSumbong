-- 0118: identity photos are deleted from Cloudinary once nothing uses them
-- (backend review, 10 Oct 2026).
--
-- Deleting an account cleared its ID, selfie and profile picture
-- addresses (0045) but left the files themselves on Cloudinary for good.
-- So did an approved new ID (the old one), a declined one, and a replaced
-- profile picture. Now every identity-photo address that stops being used
-- goes into media_trash. After a week (time to undo a mistake), the
-- media-cleanup Edge Function deletes each file that still nothing points
-- to. Only ids/, selfies/ and avatars/ are ever queued: complaint and
-- dispatch evidence is never touched by this.
--
-- The daily job calls media-cleanup through pg_net, with the function's
-- address and secret read from Supabase Vault (names media_cleanup_url and
-- media_cleanup_secret; see docs/OPERATIONS.md). Without them it does
-- nothing, and the queue simply waits.

create table if not exists public.media_trash (
  url        text primary key,
  queued_at  timestamptz not null default now()
);

comment on table public.media_trash is
  '0118: identity-photo addresses no longer used, waiting a week before '
  'media-cleanup deletes the file (if still unused).';

alter table public.media_trash enable row level security;
-- No policies: written by triggers, read and cleared by the service role.

create or replace function public.is_identity_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_url ~ '^https://res\.cloudinary\.com/nwb2kryl/image/(upload|authenticated)/v[0-9]+/(ids|selfies|avatars)/'
$$;

create or replace function public.identity_media_in_use(p_url text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.users
                  where id_image_url = p_url or selfie_url = p_url or avatar_url = p_url)
      or exists (select 1 from public.profile_requests
                  where id_image_url = p_url and status <> 'declined')
$$;

revoke all on function public.identity_media_in_use(text) from public, anon, authenticated;

create or replace function public.queue_media_trash(p_url text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.media_trash (url)
  select p_url
   where p_url is not null and public.is_identity_media_url(p_url)
  on conflict (url) do update set queued_at = now();
$$;

revoke all on function public.queue_media_trash(text) from public, anon, authenticated;

create or replace function public.users_queue_media_trash()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.queue_media_trash(old.id_image_url);
    perform public.queue_media_trash(old.selfie_url);
    perform public.queue_media_trash(old.avatar_url);
    return old;
  end if;
  if old.id_image_url is distinct from new.id_image_url then perform public.queue_media_trash(old.id_image_url); end if;
  if old.selfie_url   is distinct from new.selfie_url   then perform public.queue_media_trash(old.selfie_url); end if;
  if old.avatar_url   is distinct from new.avatar_url   then perform public.queue_media_trash(old.avatar_url); end if;
  return new;
end $$;

revoke all on function public.users_queue_media_trash() from public, anon, authenticated;

drop trigger if exists users_media_trash on public.users;
create trigger users_media_trash
  after update of id_image_url, selfie_url, avatar_url or delete on public.users
  for each row execute function public.users_queue_media_trash();

create or replace function public.profile_requests_queue_media_trash()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.queue_media_trash(old.id_image_url);
    return old;
  end if;
  if new.status = 'declined' and old.status <> 'declined' then
    perform public.queue_media_trash(new.id_image_url);
  end if;
  return new;
end $$;

revoke all on function public.profile_requests_queue_media_trash() from public, anon, authenticated;

drop trigger if exists profile_requests_media_trash on public.profile_requests;
create trigger profile_requests_media_trash
  after update of status or delete on public.profile_requests
  for each row execute function public.profile_requests_queue_media_trash();

-- ---------- for media-cleanup (service role) -------------------------------

create or replace function public.media_trash_due(p_limit integer default 100)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select t.url from public.media_trash t
   where t.queued_at < now() - interval '7 days'
     and not public.identity_media_in_use(t.url)
   order by t.queued_at
   limit p_limit
$$;

create or replace function public.media_trash_done(p_urls text[])
returns void
language sql
security definer
set search_path = public
as $$
  -- Also drops entries that came back into use: nothing to delete there.
  delete from public.media_trash t
   where t.url = any (p_urls)
      or public.identity_media_in_use(t.url);
$$;

revoke all on function public.media_trash_due(integer) from public, anon, authenticated;
revoke all on function public.media_trash_done(text[]) from public, anon, authenticated;
grant execute on function public.media_trash_due(integer) to service_role;
grant execute on function public.media_trash_done(text[]) to service_role;

-- ---------- the daily call -------------------------------------------------

create or replace function public.run_media_cleanup()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  if to_regclass('vault.decrypted_secrets') is null then return; end if;
  execute $q$ select max(decrypted_secret) filter (where name = 'media_cleanup_url'),
                     max(decrypted_secret) filter (where name = 'media_cleanup_secret')
                from vault.decrypted_secrets $q$
     into v_url, v_secret;
  if v_url is null or v_secret is null then return; end if;
  if not exists (select 1 from public.media_trash where queued_at < now() - interval '7 days') then return; end if;
  perform net.http_post(url := v_url,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cleanup-secret', v_secret),
                        body := '{}'::jsonb,
                        timeout_milliseconds := 60000);
end $$;

revoke all on function public.run_media_cleanup() from public, anon, authenticated;

select cron.schedule('media-cleanup', '40 3 * * *', $$ select public.run_media_cleanup() $$);
