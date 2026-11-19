-- 0177: a report is written only by the functions (backend sweep, 19 Nov 2026). DRAFT: not applied until Ace says "apply 0177".
--
-- Found by the sweep (proved on a copy built from the migrations):
--   * reports_resident_insert checks only that the row is the resident's own, and the table lets a signed-in resident write EVERY
--     column. A verified resident posting straight to /rest/v1/reports could choose status = validated (skipping review),
--     handler_id (a Kagawad of their choice), committee, is_sensitive, assigned_to and tracking_id. A tracking id they pick
--     ("BRG-2026-0020") makes the filing of a later, real report fail on the unique index when the counter reaches it.
--   * reports_admin_update lets an administrator who may act on a case write EVERY column of it with a plain PATCH: category
--     (the one-category rule of 0176 then no longer holds), resident_id, tracking_id, created_at, status = closed with no entry
--     in the trail. No page of the portal and no screen of the app updates reports directly; every change goes through a function.
--
-- The filing function (file_report) runs as the resident and inserts only these columns, so the grant below is exactly what it
-- needs; the triggers still fill tracking_id, status, flags and the rest. Updates go away: the functions that change a case are
-- all security definer.
--
--   * insert: only resident_id, is_anonymous, category, subject, description, latitude, longitude, client_ref
--   * update: nobody signed in; the policy that allowed it is dropped

set search_path = public, extensions;

revoke insert, update on public.reports from authenticated, anon;
grant insert (resident_id, is_anonymous, category, subject, description, latitude, longitude, client_ref) on public.reports to authenticated;

drop policy if exists reports_admin_update on public.reports;

comment on table public.reports is
  '0177: written only through functions. A signed-in resident may insert the columns file_report writes and nothing else; nobody signed in updates it.';
