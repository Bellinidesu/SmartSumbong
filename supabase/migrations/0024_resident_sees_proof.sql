-- =============================================================
-- SmartSumbong — 0024 The resident can see the proof
--
-- The Completed view in Rose's design says, in as many words:
--
--     "Your report has been resolved. View Photo for the proof."
--
-- dispatch_media_read admits the assigned tanod and admins, and nobody
-- else. So the resident taps View Photo and gets nothing.
--
-- That is worth fixing rather than removing from the design, because
-- proof of resolution is the thing that makes a complaint system
-- trustworthy instead of a place where reports go to disappear. A
-- resident who is told their pothole was filled, and can see the filled
-- pothole, has a reason to file the next one. A resident who is told it
-- was filled and shown nothing has only the barangay's word, and the
-- Report Summary's resolution figures become a number nobody outside the
-- office believes.
--
-- status_logs_read already lets a resident read the history of their own
-- report, which is what the Track Complaint Status use case describes as
-- "a linear progress timeline showing tracking updates". This closes the
-- matching gap for the evidence.
--
-- SCOPE. Only the resident who filed the complaint, only for their own
-- report, and only media attached to a dispatch on that report. It does
-- not open dispatch_media generally, and it does not let a resident see
-- anything about the tanod beyond the photograph they submitted.
-- =============================================================

set search_path = public, extensions;

drop policy if exists dispatch_media_read on public.dispatch_media;

create policy dispatch_media_read on public.dispatch_media
  for select using (
    exists (
      select 1
        from public.dispatches d
        join public.reports r on r.id = d.report_id
       where d.id = dispatch_media.dispatch_id
         and (
           -- the tanod who took the photo
           d.tanod_id = auth.uid()
           or public.is_admin()
           -- the resident whose complaint it evidences
           or (r.resident_id = auth.uid() and r.deleted_at is null)
         )
    )
  );

comment on table public.dispatch_media is
  'Tanod field photographs. Readable by the tanod who submitted them, by '
  'admins, and — since 0024 — by the resident whose complaint they '
  'evidence, because the Completed view promises them proof and a '
  'complaint system that cannot show its work is not one.';

-- Verification. Run separately.
--
--   -- the policy should name reports, not just dispatches
--   select case when qual::text like '%resident_id%' then 'OK' else 'MISSING' end
--     from pg_policies
--    where schemaname='public' and tablename='dispatch_media'
--      and policyname='dispatch_media_read';
--
-- The real test needs a resolved complaint with tanod proof attached,
-- which the tanod app does not exist to produce yet. Until then this is
-- correct by construction and untested by observation — worth saying so
-- in turnover.md rather than assuming it works.
