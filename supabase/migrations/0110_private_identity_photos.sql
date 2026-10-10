-- 0110: identity photos stop being public (backend review, 10 Oct 2026).
--
-- A resident's government ID and registration selfie were stored as
-- ordinary public Cloudinary images: anyone holding the address could open
-- them, and the address is readable by everyone RLS lets see the row. Now
-- sign-upload stores ids/ and selfies/ as Cloudinary "authenticated"
-- assets. Their stored address opens nothing by itself; the portal signs a
-- viewing link with the API secret each time it shows one, and the app
-- asks sign-upload for one when it re-reads its own ID.
--
-- Profile pictures move out of selfies/ into a public avatars/ folder:
-- unlike the registration selfie, they are meant to be seen.
--
-- Strictly wider than before: every address that passed is_media_url()
-- still passes. Older uploads stay public until
-- scripts/privatize-identity-photos.mjs moves them.

create or replace function public.is_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/image/upload/v[0-9]+/(reports|ids|selfies|dispatch|avatars)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
      or p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/image/authenticated/v[0-9]+/(ids|selfies)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
$$;

comment on function public.is_media_url(text) is
  'True only for delivery URLs in the barangay''s own Cloudinary cloud: '
  'public images under reports, ids, selfies, dispatch or avatars, or '
  'private (authenticated) images under ids or selfies (0110), with a '
  'UUIDv4 object name, an image extension, no signature and no query '
  'string. Mirrored by _pinnedUrl in mobile/core/lib/src/media_upload.dart.';
