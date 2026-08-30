-- =============================================================
-- SmartSumbong — 0049 Who wrote the resolution note
--
-- Round 12 (29 Aug 2026) put the tanod's own field-report text on the
-- resident's card once a complaint is resolved -- "Out of jurisdiction",
-- "Maintenance team replaced the faulty bulb..." -- pulled straight from
-- status_logs.remark, already resident-readable for their own report.
-- The next question the resident asked, off a live screenshot, was the
-- obvious follow-up: whose words are these? A remark with no byline
-- reads like a system status line even when it is someone's own account
-- of what they did.
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
-- So the name is resolved at READ time instead, via a narrow function --
-- not a widened RLS policy on public.users. A resident can already read
-- every column of their own reports' status_logs rows, changed_by
-- included (status_logs_read, 0001/0003); the only gap is that
-- changed_by is a uuid and users_read only lets a resident see their OWN
-- user row. This function closes exactly that gap and no further: it
-- returns a name only for a 'resolved' entry on a report the CALLER
-- owns (r.resident_id = auth.uid(), checked in the query itself, not
-- left to RLS), nothing else about the tanod's account.
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
