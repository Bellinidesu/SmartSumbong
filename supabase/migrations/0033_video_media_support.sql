-- =============================================================
-- SmartSumbong — 0033 Widen report/dispatch media for video
--
-- Rose asked whether video submission works (team chat, 26 Aug
-- 2026). The client side already got pickVideo()/uploadVideo() in
-- mobile/core/lib/src/media_upload.dart this same day — but that
-- alone does not make video work. Both media tables were built for
-- photos only:
--
--   report_media.mime_type    check (mime_type in ('image/jpeg', 'image/png'))
--   dispatch_media.mime_type  check (mime_type in ('image/jpeg', 'image/png'))
--   dispatch_media.bytes      check (bytes > 0 and bytes <= 10 MB)
--   enforce_media_cap()       combined report total capped at 10 MB
--
-- Verified against a real Postgres instance before writing this
-- file: a video row (mime_type = 'video/mp4') was rejected outright
-- by report_media_mime_type_check, independent of anything the
-- Flutter app does. Without this migration, file_report() and the
-- tanod app's `dispatch_media` insert both fail for any video,
-- every time, regardless of the Cloudinary upload succeeding.
--
-- WHAT THIS MIGRATION DOES NOT FIX. It widens the database's
-- constraints to accept video. It does not, and cannot, make
-- Cloudinary accept a video upload — `smartsumbong_unsigned` is
-- configured "Allowed formats: jpg, png, webp" (see the header
-- comment in media_upload.dart). Someone with access to the
-- Cloudinary dashboard still needs to widen that preset (or add a
-- second unsigned preset for video) before an upload actually
-- lands in Cloudinary. Until then, uploadVideo() will surface the
-- "Video uploads are not enabled yet" message it was written to
-- detect, rather than silently failing.
--
-- CAP NUMBERS. mobile/core/lib/src/media_upload.dart caps a
-- gallery-picked video at 25 MB client-side (there is no
-- duration-reading library in this project to enforce the 30s
-- limit outside of direct camera capture, so this is the backstop
-- for that path). The numbers below exist to make room for that,
-- not because 25/35 MB are independently meaningful:
--
--   report_media combined cap:   10 MB -> 35 MB  (room for 5 photos
--     under the existing per-photo ~2 MB post-compression size, plus
--     one 25 MB video)
--   dispatch_media per-row cap:  10 MB -> 25 MB  (parity with the
--     client's video ceiling; a tanod's field-proof photo/video
--     insert has no combined-total trigger, only this per-row one)
--
-- All six cases below were run against a real Postgres instance
-- before this file was written: a video insert that used to fail
-- now succeeds; a report with 5 photos (~9.5 MB) plus a 20 MB video
-- now fits under the new 35 MB combined cap; a report that tries to
-- exceed 35 MB combined is still rejected; a 20 MB dispatch video
-- now fits under the new 25 MB per-row cap; a 30 MB dispatch video
-- is still rejected; and a bogus mime_type (image/gif) is still
-- rejected exactly as before. This migration only adds video to the
-- allow-list and raises the two size ceilings — it narrows nothing.

alter table public.report_media
  drop constraint report_media_mime_type_check;

alter table public.report_media
  add constraint report_media_mime_type_check
  check (mime_type in (
    'image/jpeg', 'image/png',
    'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp'
  ));

alter table public.dispatch_media
  drop constraint dispatch_media_mime_type_check;

alter table public.dispatch_media
  add constraint dispatch_media_mime_type_check
  check (mime_type in (
    'image/jpeg', 'image/png',
    'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp'
  ));

alter table public.dispatch_media
  drop constraint dispatch_media_bytes_check;

alter table public.dispatch_media
  add constraint dispatch_media_bytes_check
  check (bytes > 0 and bytes <= 25 * 1024 * 1024);

-- Full body re-declared (CREATE OR REPLACE, same signature) rather
-- than an ALTER — this is a trigger function, so its body has to be
-- restated in full; only the literal 10 * 1024 * 1024 -> 35 * 1024 *
-- 1024 changed from the version in 0001_init_schema.sql.
create or replace function public.enforce_media_cap()
returns trigger language plpgsql as $$
declare
  total integer;
begin
  select coalesce(sum(bytes), 0) into total
    from public.report_media where report_id = new.report_id;
  if total + new.bytes > 35 * 1024 * 1024 then
    raise exception 'Combined media for this report exceeds the 35 MB limit';
  end if;
  return new;
end $$;
