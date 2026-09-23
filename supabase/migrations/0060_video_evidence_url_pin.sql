-- =============================================================
-- SmartSumbong — 0060 Let video evidence past the media URL pin;
--                     index reports.resident_id
--
-- Written 23 Sep 2026 during the pre-defense sweep. NOT APPLIED —
-- replay against a local copy first (verification block at the end),
-- then Ace pushes.
--
-- 1. VIDEO URLS NEVER PASSED THE PIN.
--
-- 0033 widened report_media/dispatch_media for video: mime types, the
-- per-row and combined size caps. It did not touch the URL pin. Both
-- tables still carry
--
--   report_media_url_pinned    check (public.is_media_url(media_url))
--   dispatch_media_url_pinned  check (public.is_media_url(media_url))
--
-- and is_media_url() (0018) accepts only .../image/upload/... with an
-- image extension. Cloudinary returns a video as
--
--   https://res.cloudinary.com/nwb2kryl/video/upload/v<n>/reports/<uuid>.mp4
--
-- which is exactly what MediaUploader.uploadVideo() checks for on the
-- phone (_pinnedVideoUrl in mobile/core/lib/src/media_upload.dart). So
-- a resident who attaches a video gets as far as a finished Cloudinary
-- upload, and then file_report() fails on report_media_url_pinned — the
-- app maps that to "your photos could not be attached". The tanod's
-- field-proof video fails the same way on dispatch_media_url_pinned.
--
-- is_media_url() itself is left alone. It also guards users.id_image_url,
-- selfie_url and avatar_url, which must stay photo-only, and it is the
-- function _pinnedUrl mirrors. A second function takes its place on the
-- two evidence tables only: a photo URL exactly as before, or a video
-- URL in the reports/dispatch folders — the same shape _pinnedVideoUrl
-- accepts, character for character. The two must change together, the
-- same rule 0018 states for is_media_url()/_pinnedUrl.
--
-- Strictly wider than before: every row that passed is_media_url()
-- passes this, so re-adding the constraints cannot fail on existing
-- data.
--
-- 2. reports.resident_id HAS NO INDEX.
--
-- It is the column reports_resident_read (0003) filters every resident
-- query on, the filter the resident app's own Reports list sends, and a
-- foreign key to users. Every one of those is a sequential scan of
-- reports today. Harmless at this size, linear from here; the index
-- changes no behaviour.
-- =============================================================

set search_path = public, extensions;

-- ---------- 1. evidence URL pin ------------------------------------

create or replace function public.is_evidence_media_url(p_url text)
returns boolean
language sql
immutable
parallel safe
as $$
  select public.is_media_url(p_url)
      or p_url ~
    '^https://res\.cloudinary\.com/nwb2kryl/video/upload/v[0-9]+/(reports|dispatch)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(mp4|mov|webm|3gp)$'
$$;

comment on function public.is_evidence_media_url(text) is
  'is_media_url() or a Cloudinary video URL in the reports/dispatch '
  'folders with a UUIDv4 name and a video extension. Used only by the '
  'report_media and dispatch_media pins (0060); identity columns stay on '
  'is_media_url(). Mirrored by _pinnedVideoUrl in '
  'mobile/core/lib/src/media_upload.dart — the two must change together.';

revoke all on function public.is_evidence_media_url(text) from public, anon;
grant execute on function public.is_evidence_media_url(text) to authenticated, service_role;

alter table public.report_media
  drop constraint if exists report_media_url_pinned;
alter table public.report_media
  add constraint report_media_url_pinned
  check (public.is_evidence_media_url(media_url));

alter table public.dispatch_media
  drop constraint if exists dispatch_media_url_pinned;
alter table public.dispatch_media
  add constraint dispatch_media_url_pinned
  check (public.is_evidence_media_url(media_url));

-- ---------- 2. reports.resident_id ---------------------------------

create index if not exists reports_resident_idx
  on public.reports (resident_id, created_at desc);

-- Verification. Run separately; every row should read PASS.
--
--   select 'photo url still accepted' as check_name,
--          case when public.is_evidence_media_url(
--            'https://res.cloudinary.com/nwb2kryl/image/upload/v1785742127/'
--            || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.jpg')
--          then 'PASS' else 'FAIL' end as result
--   union all
--   select 'report video accepted',
--          case when public.is_evidence_media_url(
--            'https://res.cloudinary.com/nwb2kryl/video/upload/v1785742127/'
--            || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.mp4')
--          then 'PASS' else 'FAIL' end
--   union all
--   select 'dispatch video accepted',
--          case when public.is_evidence_media_url(
--            'https://res.cloudinary.com/nwb2kryl/video/upload/v1785742127/'
--            || 'dispatch/c92a9dea-3b47-4578-953a-2bb837470fca.mov')
--          then 'PASS' else 'FAIL' end
--   union all
--   select 'video in ids folder rejected',
--          case when public.is_evidence_media_url(
--            'https://res.cloudinary.com/nwb2kryl/video/upload/v1785742127/'
--            || 'ids/c92a9dea-3b47-4578-953a-2bb837470fca.mp4')
--          then 'FAIL' else 'PASS' end
--   union all
--   select 'foreign cloud rejected',
--          case when public.is_evidence_media_url(
--            'https://res.cloudinary.com/someoneelse/video/upload/v1/'
--            || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.mp4')
--          then 'FAIL' else 'PASS' end
--   union all
--   select 'identity pin still photo-only',
--          case when public.is_media_url(
--            'https://res.cloudinary.com/nwb2kryl/video/upload/v1785742127/'
--            || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.mp4')
--          then 'FAIL' else 'PASS' end
--   union all
--   select 'both pins now use is_evidence_media_url',
--          case when count(*) = 2 then 'PASS' else 'FAIL' end
--     from pg_constraint
--    where conname in ('report_media_url_pinned', 'dispatch_media_url_pinned')
--      and pg_get_constraintdef(oid) like '%is_evidence_media_url%'
--   union all
--   select 'reports_resident_idx exists',
--          case when count(*) = 1 then 'PASS' else 'FAIL' end
--     from pg_indexes
--    where schemaname = 'public' and indexname = 'reports_resident_idx';
--
-- And the end-to-end case that failed before this migration — a video
-- row on a real report, inside a transaction that is rolled back:
--
--   begin;
--   insert into public.report_media (report_id, media_url, mime_type, bytes)
--   select id,
--          'https://res.cloudinary.com/nwb2kryl/video/upload/v1785742127/'
--          || 'reports/c92a9dea-3b47-4578-953a-2bb837470fca.mp4',
--          'video/mp4', 1048576
--     from public.reports limit 1
--   returning id, media_url;   -- expect 1 row, not a check violation
--   rollback;
