-- =============================================================
-- SmartSumbong — 0038 Address and avatar on Edit Profile
--
-- Figma parity audit (27 Aug 2026): EDIT PROFILE (2254:1627) has a 5th
-- field (Address) and a camera-icon avatar upload that public.users had
-- no columns for.
--
-- BOTH ARE ORDINARY, RESIDENT-EDITABLE FIELDS — NOT LOCKED. Unlike
-- full_name and mobile_number (0026), neither is identity evidence an
-- admin checked against a government ID, and neither is a login
-- credential. They follow the same shape as email: a direct update from
-- the client, with no trigger change needed, because
-- guard_privileged_user_fields() (0026) only blocks role, verification,
-- suspension, mobile_number and full_name — everything else on this row
-- was already open to a resident's own UPDATE under users_update's
-- `id = auth.uid()` policy (0003). This migration adds the columns;
-- it does not touch the guard or the RLS policy.
--
-- avatar_url gets the same URL-pinning constraint as id_image_url and
-- selfie_url (0017/0018's is_media_url()) — a resident's own Cloudinary
-- upload, not an arbitrary external image.
--
-- address is free text, not geocoded. It is a "how to find your house"
-- line for the barangay, not a value anything spatial reads — reports
-- already carry their own latitude/longitude from the map pin, so
-- nothing needs this to be structured.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists address text
    check (address is null or char_length(address) <= 200);

alter table public.users
  add column if not exists avatar_url text;

alter table public.users
  drop constraint if exists users_avatar_url_pinned;

alter table public.users
  add constraint users_avatar_url_pinned
  check (avatar_url is null or public.is_media_url(avatar_url));

comment on column public.users.address is
  'Free text, resident-editable directly (0038) — a "how to find your '
  'house" line for the barangay, not a geocoded value anything spatial '
  'reads. Unlike full_name/mobile_number this is not identity evidence, '
  'so guard_privileged_user_fields() (0026) does not restrict it.';

comment on column public.users.avatar_url is
  'Resident-editable directly (0038), same pattern as email. Pinned to '
  'this project''s own Cloudinary account by users_avatar_url_pinned, '
  'same as id_image_url/selfie_url.';
