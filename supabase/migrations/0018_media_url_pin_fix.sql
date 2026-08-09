-- =============================================================
-- SmartSumbong — 0018 Media URL pin correction
--
-- 0017 shipped an is_media_url() that requires a `smartsumbong/`
-- segment in the delivery URL. That segment does not exist and never
-- will. The upload preset uses Cloudinary's dynamic folders mode with
-- "use asset folder as public id prefix" off, so `smartsumbong` is
-- organisational metadata in the media library only — it does not enter
-- the public_id and therefore not the URL.
--
-- Verified against a real upload from the resident app:
--
--   secure_url    https://res.cloudinary.com/nwb2kryl/image/upload/
--                 v1785742127/reports/c92a9dea-3b47-4578-953a-2bb837470fca.jpg
--   public_id     reports/c92a9dea-3b47-4578-953a-2bb837470fca
--   folder        null
--   asset_folder  smartsumbong
--
-- Consequence of leaving this unfixed: every genuine photo upload fails
-- report_media_url_pinned, and no resident can attach evidence to a
-- complaint. The constraint is not merely wrong, it is closed.
--
-- The folder segment was not load-bearing in any case. The preset
-- applies its asset folder to every caller, so requiring it in the URL
-- would constrain nobody — an attacker with the cloud name and preset
-- (both extractable from the APK) gets the same prefix applied to their
-- own upload. What actually constrains a forged media_url is:
--
--   * the cloud prefix — it cannot point at a host the attacker runs,
--     which is the whole point of 0017: nothing third-party loads in an
--     administrator's browser;
--   * a UUIDv4-shaped object name — it cannot point at an asset the
--     attacker named themselves;
--   * one of the four known kind folders.
--
-- What this still does not stop: someone with the cloud name and preset
-- uploading a UUID-named file into `reports/` and submitting that URL.
-- Guarding that is RLS's job — they would need a verified, unsuspended
-- resident account to insert the row at all. Say this plainly if asked;
-- the pin is about the admin browser, not about Cloudinary abuse.
--
-- CREATE OR REPLACE on a function behind a CHECK changes what the
-- constraint means without revalidating existing rows, so each
-- constraint is dropped and re-added below. Re-adding validates.
-- =============================================================

set search_path = public, extensions;

create or replace function public.is_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/image/upload/v[0-9]+/(reports|ids|selfies|dispatch)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
$$;

comment on function public.is_media_url(text) is
  'True only for delivery URLs in the barangay''s own Cloudinary cloud, '
  'under one of the four kind folders, with a UUIDv4 object name, an image '
  'extension and no query string. Mirrored by _pinnedUrl in '
  'mobile/core/lib/src/media_upload.dart — the two must change together.';

-- Re-add so existing rows are validated against the new definition.

alter table public.report_media
  drop constraint if exists report_media_url_pinned;
alter table public.report_media
  add constraint report_media_url_pinned
  check (public.is_media_url(media_url));

alter table public.dispatch_media
  drop constraint if exists dispatch_media_url_pinned;
alter table public.dispatch_media
  add constraint dispatch_media_url_pinned
  check (public.is_media_url(media_url));

alter table public.users
  drop constraint if exists users_id_image_url_pinned;
alter table public.users
  add constraint users_id_image_url_pinned
  check (id_image_url is null or public.is_media_url(id_image_url));

alter table public.users
  drop constraint if exists users_selfie_url_pinned;
alter table public.users
  add constraint users_selfie_url_pinned
  check (selfie_url is null or public.is_media_url(selfie_url));

-- Verification. Run separately; expect PASS on both rows.
--
--   select 'accepts real upload' as case,
--          case when public.is_media_url(
--            'https://res.cloudinary.com/nwb2kryl/image/upload/v1785742127/'
--            || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.jpg')
--          then 'PASS' else 'FAIL' end as result
--   union all
--   select 'rejects foreign host',
--          case when public.is_media_url('https://evil.example/x.jpg')
--          then 'FAIL' else 'PASS' end;
