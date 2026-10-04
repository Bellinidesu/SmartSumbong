-- 0083 — Each evidence table takes photos from its own folder only
-- (system sweep, 5 Oct 2026).
--
-- report_media and dispatch_media were pinned to the barangay's Cloudinary
-- cloud (0017/0018/0060), but to any of its folders, so a tanod's update
-- could point at an image in ids/ or selfies/. Every upload path already
-- uses its own folder (the app's MediaKind: complaint photos, reopen,
-- appeal and details answers in reports/; tanod proof and updates in
-- dispatch/), and every stored row complies (33 and 8 checked before this
-- was written), so this only closes the gap.

set search_path = public, extensions;

alter table public.report_media
  drop constraint if exists report_media_url_folder;
alter table public.report_media
  add constraint report_media_url_folder
  check (media_url ~ '^https://res\.cloudinary\.com/nwb2kryl/(image|video)/upload/v[0-9]+/reports/');

alter table public.dispatch_media
  drop constraint if exists dispatch_media_url_folder;
alter table public.dispatch_media
  add constraint dispatch_media_url_folder
  check (media_url ~ '^https://res\.cloudinary\.com/nwb2kryl/(image|video)/upload/v[0-9]+/dispatch/');
