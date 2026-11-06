-- =============================================================
-- SmartSumbong — 0161 App updates (the self-updater)
--
-- Ace, 1 Nov 2026: the app should be able to update itself. A super admin publishes a version in the Control Room (App updates): the APK's
-- link, its SHA-256, the notes, and whether it must be installed. The app asks for the newest one, compares the build number with its own,
-- offers it, downloads it, checks the SHA-256 and hands it to Android's installer. Android itself still refuses an APK signed with a different key.
--
--   app_releases               one row per published version (the link, the SHA-256, notes in English and Tagalog, mandatory or not)
--   latest_app_release()       what the app asks (everyone, signed in or not): the active release with the highest build, or null
--   app_release_publish(...)   a super admin adds one; its build must be higher than every earlier one
--   app_release_set_active()   a super admin withdraws a release (the app then offers the one before it) or puts it back
--   feature_switches 'app_updates'   on by default; off, latest_app_release() answers null and no phone is offered anything
-- =============================================================

set search_path = public, extensions;

insert into public.feature_switches (key, label_en, label_fil, enabled, note) values
  ('app_updates', 'App updates', 'Mga update ng app', true, 'Phones are offered the newest published version. Off, they are offered nothing.')
on conflict (key) do nothing;

create table public.app_releases (
  id         uuid primary key default gen_random_uuid(),
  version    text not null check (version ~ '^[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.]+)?$'),
  build      integer not null check (build > 0),
  apk_url    text not null check (apk_url ~ '^https://[^[:space:]]+$' and char_length(apk_url) <= 500),
  sha256     text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  notes_en   text check (char_length(notes_en) <= 600),
  notes_fil  text check (char_length(notes_fil) <= 600),
  mandatory  boolean not null default false,
  active     boolean not null default true,
  created_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (build)
);
create index app_releases_created_by_idx on public.app_releases (created_by) where created_by is not null;
alter table public.app_releases enable row level security;
create policy app_releases_read on public.app_releases for select using ((select public.is_super_admin()));
comment on table public.app_releases is '0161: published versions of the app for the self-updater. Written only by app_release_publish / app_release_set_active.';

create or replace function public.latest_app_release()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select to_jsonb(r) from (
    select id, version, build, apk_url, sha256, notes_en, notes_fil, mandatory
      from public.app_releases
     where active and public.feature_on('app_updates')
     order by build desc limit 1
  ) r
$$;

create or replace function public.app_release_publish(
  p_version text, p_build integer, p_url text, p_sha256 text, p_notes_en text default null, p_notes_fil text default null, p_mandatory boolean default false
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_max integer;
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'Only a super admin can publish a version' using errcode = '42501'; end if;
  select max(build) into v_max from public.app_releases;
  if v_max is not null and p_build <= v_max then
    raise exception 'The build number must be higher than the last one (%).', v_max using errcode = 'check_violation';
  end if;
  insert into public.app_releases (version, build, apk_url, sha256, notes_en, notes_fil, mandatory, created_by)
  values (btrim(p_version), p_build, btrim(p_url), lower(btrim(p_sha256)), nullif(btrim(coalesce(p_notes_en, '')), ''), nullif(btrim(coalesce(p_notes_fil, '')), ''),
          coalesce(p_mandatory, false), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.app_release_set_active(p_id uuid, p_on boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'Only a super admin can change a release' using errcode = '42501'; end if;
  update public.app_releases set active = coalesce(p_on, false) where id = p_id;
end $$;

revoke all on function public.latest_app_release() from public;
revoke all on function public.app_release_publish(text, integer, text, text, text, text, boolean) from public, anon;
revoke all on function public.app_release_set_active(uuid, boolean) from public, anon;
grant execute on function public.latest_app_release() to anon, authenticated;
grant execute on function public.app_release_publish(text, integer, text, text, text, text, boolean) to authenticated;
grant execute on function public.app_release_set_active(uuid, boolean) to authenticated;
