-- =============================================================
-- SmartSumbong — 0049 Who wrote the status_logs entry
--
-- Round 12 (29 Aug 2026) put the tanod's own field-report text on the
-- resident's card once a complaint is resolved -- "Out of jurisdiction",
-- "Maintenance team replaced the faulty bulb..." -- pulled straight from
-- status_logs.remark, already resident-readable for their own report.
-- The next question the resident asked, off a live screenshot, was the
-- obvious follow-up: whose words are these? A remark with no byline
-- reads like a system status line even when it is someone's own account
-- of what they did -- and the very next round asked for the same byline
-- on every row of the full timeline too, not just the card's resolution
-- note, e.g. "SYSTEM:" ahead of the auto-dispatch line.
--
-- WHY NOT BAKE A NAME INTO remark AT WRITE TIME, THE WAY 0047 DID FOR
-- auto_dispatch. That pattern (format('Auto-dispatched to %s (...)',
-- tanod_name)) works precisely because status_logs is append-only and
-- immutable (0015's status_logs_immutable trigger -- see this repo's own
-- recent history hitting that exact wall on a backfill attempt). Every
-- report already resolved before this migration ships -- including the
-- five completed reports on the resident's screen right now -- has its
-- remark already written and permanently un-editable. Changing
-- submit_field_report (0002) to prepend the tanod's name would only take
-- effect on the NEXT resolution; today's cards would keep showing bare
-- text with no byline, which is worse than not shipping this at all.
--
-- So the name is resolved at READ time instead, via two narrow functions
-- -- not a widened RLS policy on public.users. A resident can already
-- read every column of their own reports' status_logs rows, changed_by
-- included (status_logs_read, 0001/0003); the only gap is that
-- changed_by is a uuid and users_read only lets a resident see their OWN
-- user row. Both functions close exactly that gap and no further, each
-- scoped to what one screen actually needs:
--
--   my_resolution_authors(report_ids[]) -- the resident app's list
--   screen, which shows many reports' cards at once and only needs the
--   ONE 'resolved' entry's author per report (batch, resolved-only).
--
--   my_status_log_authors(report_id) -- the detail screen's full
--   per-report timeline, which needs EVERY entry's author, one report
--   at a time. (The list screen's own compact hero mini-timeline never
--   renders remark text at all, so it has no use for this.)
--
-- Both check ownership in the query itself (r.resident_id = auth.uid()),
-- not left to RLS, and return nothing about the other user's account
-- beyond full_name.
-- =============================================================

set search_path = public, extensions;

create or replace function public.my_resolution_authors(p_report_ids uuid[])
returns table (
  report_id   uuid,
  author_name text,
  is_system   boolean)
language sql stable security definer set search_path = public, extensions as $$
  select distinct on (sl.report_id)
         sl.report_id,
         u.full_name,
         sl.is_system
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
   where sl.new_status = 'resolved'
     and sl.report_id = any(p_report_ids)
     and r.resident_id = auth.uid()
   order by sl.report_id, sl.created_at desc
$$;

revoke execute on function public.my_resolution_authors(uuid[]) from public, anon;
grant  execute on function public.my_resolution_authors(uuid[]) to authenticated;

comment on function public.my_resolution_authors(uuid[]) is
  'For the caller''s own reports only: who wrote the latest resolved-status remark (a tanod''s full_name) and whether it was a system entry. Backs the "TANOD X:" / "SYSTEM:" byline on the resident app''s resolution-note text. See 0049.';

-- ---------- every entry in one report's timeline --------------

create or replace function public.my_status_log_authors(p_report_id uuid)
returns table (
  status_log_id uuid,
  author_name   text,
  is_system     boolean)
language sql stable security definer set search_path = public, extensions as $$
  select sl.id,
         u.full_name,
         sl.is_system
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
   where sl.report_id = p_report_id
     and r.resident_id = auth.uid()
$$;

revoke execute on function public.my_status_log_authors(uuid) from public, anon;
grant  execute on function public.my_status_log_authors(uuid) to authenticated;

comment on function public.my_status_log_authors(uuid) is
  'For the caller''s own report only: who wrote each status_logs entry (a tanod''s full_name, or nothing for a system entry) and whether it was a system entry. Backs the "TANOD X:" / "SYSTEM:" byline on every row of report_view_screen.dart''s full timeline (its resolution-note card body reuses the same lookup, since that note IS one timeline entry''s remark). See 0049.';
