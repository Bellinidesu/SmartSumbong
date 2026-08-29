-- =============================================================
-- SmartSumbong — 0041 Filing a report is a resident-only action, at the
-- database, not just in whichever app happens to be asking.
--
-- reports_resident_insert (0003) already checks resident_id = auth.uid()
-- and that the account is verified and not suspended. It never checked
-- role. Nothing in the tanod app exposes a "file a complaint" screen, so
-- in practice this has never been exploitable through the apps as they
-- exist today -- but the rule "a resident who abuses the report system
-- can be restricted" (0040) is only actually true account-wide if
-- reporting itself is something only a resident account can do in the
-- first place. A tanod account calling the insert (or the RPC behind it)
-- directly, bypassing the app entirely, was still technically allowed.
-- Closing that here rather than relying on app-side gating that a
-- future screen could quietly undo.
-- =============================================================

set search_path = public, extensions;

drop policy if exists reports_resident_insert on public.reports;

create policy reports_resident_insert on public.reports
  for insert with check (
    resident_id = auth.uid()
    and exists (select 1 from public.users u
                 where u.id = auth.uid()
                   and u.role = 'resident'
                   and u.verification_status = 'verified'
                   and not u.is_suspended)
  );

comment on policy reports_resident_insert on public.reports is
  'Only a verified, non-suspended resident account may file a report -- '
  'role = ''resident'' added in 0041 so this is true regardless of which '
  'client calls the insert, not just the resident app''s own UI.';

-- Verification. Run separately.
--
--   select polname, pg_get_expr(polqual, polrelid), pg_get_expr(polwithcheck, polrelid)
--     from pg_policy where polrelid = 'public.reports'::regclass and polname = 'reports_resident_insert';
