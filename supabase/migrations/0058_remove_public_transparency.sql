-- =============================================================
-- SmartSumbong — 0058 Remove the public transparency dashboard
--
-- Rose (15 Sep 2026): "completely remove the transparency page we dont
-- need it." public/transparency.php and its links (the admin dashboard's
-- "Public Transparency Page" button, the root landing page's "View Public
-- Transparency Dashboard" button, and public/'s allowlist entry in
-- .htaccess) are removed on the application side in this same pass.
--
-- This migration is the database half of that removal: the two functions
-- 0043 added specifically to back that page -- public_transparency_stats()
-- and public_report_heat() -- are dropped outright rather than just left
-- in place unused. Both were granted to anon precisely so the now-deleted
-- page could call them with no session at all; leaving that grant standing
-- would mean anyone holding the publishable key (which is not a secret --
-- it ships in every client build) could still call them directly over
-- PostgREST even with no page left that ever did. Dropping removes that
-- surface entirely instead of trusting nobody happens to try.
--
-- Nothing else in the schema reads either function -- both were written
-- for this one consumer (0043's own header comment: "a second,
-- deliberately narrower surface," never reused by dashboard_metrics() or
-- report_hotspots(), which keep their own separate implementations) --
-- so there is no other call site to update.
-- =============================================================

set search_path = public, extensions;

drop function if exists public.public_transparency_stats(timestamptz, timestamptz);
drop function if exists public.public_report_heat(timestamptz, timestamptz, complaint_category);

-- Verification. Run separately.
--
--   select proname from pg_proc
--    where pronamespace = 'public'::regnamespace
--      and proname in ('public_transparency_stats', 'public_report_heat');
--   -- expect: 0 rows
