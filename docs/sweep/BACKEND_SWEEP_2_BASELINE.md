# Backend sweep 2: scripted baseline (20 Nov 2026)

Branch `backend-sweep-2`, draft PR, **not for merge**. Everything below was found by scripts in `tools/sweep/` (re-run: `bash tools/sweep/run_all.sh`,
~25 min; `quick` = static only, ~1 min). Read-only against the live project: live row counts, `supabase inspect db`, and GETs of the portal's headers.
Load numbers come from a throwaway PostgreSQL 16 + PostGIS on a laptop built from migrations 0001-0184 and driven through a real PostgREST as each rung's own role
(row level security on): treat them as **relative** (1x vs 250x), not as Singapore milliseconds. No migration was changed or applied; no fix drafts yet (round 2).

## Verdict

The perimeter is sound; the problem is **scale for the scoped rungs**. Headers, CSP, cookies, Edge Function auth, grants and RPC wiring are clean (no RPC called
that is missing or ungranted, no secret in the repo, filing survives a broken SMART engine, proved). But at 20,000 cases (250x) a Kagawad's or staff member's
pages do not load at all (single queries pass 30 s), and even today's size already costs them 0.2-0.6 s of database time per page. Super admin and Captain stay
under ~3.5 s at worst. Three working flows are broken by small code gaps (reopen, appeal, complaint print).

## Counts (ledger rows, `docs/sweep/GAP_LEDGER.md`; several rows can be one cause)

| critical | high | medium | low | info | total |
|---|---|---|---|---|---|
| 0 | 14 | 17 | 48 | 26 | 105 (+1 done) |

Fix class (ledger): **A mechanical 34, B needs one decision 68, C look/front end 3**. Generators for class A, options files for class B: round 2.

## Top 15 violations (proof pointer -> proposed fix)

1. **Kagawad/staff reads are O(rows x case rule) and time out at 20,000 cases.** `out/loadcost.json`: `reports?...status=in.(...)` as committee 84 ms at 1x, **>30 s** at 250x
   (24 pages); `reports?deleted_at=is.null&select=id` 126 ms -> >30 s; dispatches embed 86 ms -> 24 s; moderator list 119 ms -> 15 s. 76 of 122 (page, role) pairs exceed 200 ms
   of DB time at 250x (committee 24/24, moderator 24/24). Confirms F09, and it is wider than `count(*)`. Fix: let the policy use the row's own `committee`/`assigned_to`/
   `awaiting_placement` instead of calling `_user_sees_case` (re-reading reports and users) per row; options in K-04 (round 2). Class B (core rule).
2. **`users` is the same disease**: pending residents count as committee = 71 ms -> **8.9 s** (seq scan of 2,040 users, per-row `_admin_sees_user`, 0179). Same fix family.
3. **Resident public map query scans all cases**: `reports?is_public=eq.true&limit=500` as resident 10 ms -> **7.4 s** (seq scan 20,000). The policy's per-row function defeats the
   index; also hits the phone app's map. Likely fix: a policy branch that short-circuits `is_public` rows (and a partial index on them); to be proved on the throwaway in round 2. Class B.
4. **Reopen flow is broken end to end** (K-01): `request_reopen` and `request_appeal` notify EVERY active admin with no `report_id` (`_notifications_scope` only filters notices
   that carry one, so admins who cannot open the case are told and there is no Review button), `reopen_report()` is called by nothing, closed cases cannot be reopened
   (`admin_set_status` refuses closed/archived), the resident never gets an answer or decline. Fix: option A/B/C in K-01; adding `report_id` is class A (`fix/gen_notice_report_id.py`).
5. **`complaint-print.php` loses every photo**: it orders `report_media` by `created_at`; the live column is `uploaded_at` (live schema checked). The call is optional, so the page
   prints without evidence and nobody sees an error. One-word PHP fix (class A, not a migration).
6. **`smart_watch()` (cron every 5 min) takes 46.5 s at 20,000 cases** (`out/smart_250x.json`); `smart_queue` 0.6-0.9 s for every rung (budget 0.2 s); `_smart_snapshot_refresh`
   (every minute) 0.35 s. Today these are tiny; the watcher is the first thing to overlap itself. Fix: bound its scan to open cases / use the snapshot; class B.
7. **Filing cost grows with open cases**: one `file_report` = 158 ms at 250x, of which `reports_smart_triage` 119 ms and `main_concern` 23 ms. Under budget, but linear in nearby reports. Info/low.
8. **Every Kagawad/staff page issues calls that are always refused**: `smart_deadline_risk` and 4 other `smart_*` reads (`briefing.php`, `dashboard.php`, `spatial.php`) return
   "Only an administrator can see..." on 20+ pages for committee/moderator (D5-03..06). Harmless (optional) but a wasted DB request per page; role asymmetry, class B.
9. **Chatty pages**: `notifications.php`, `index.php`, `home.php` = 42 backend requests per load, `case.php` = 39 (most batched by `selectMany`, but each page is 40 DB queries). Class B.
10. **Notices with no label**: kinds `look_around` and `tanod_committee` are produced (0183, 0153) but neither the portal (`layout.php` notif look) nor the app has a label. Class C.
11. **Request/decision gaps**: `request_reopen` has no deny/answer notice; `request_additional_details` and `flag_case_for_forward` have no deny path (D3-01..05). Class B.
12. **status_logs is 95% noise**: 22,910 of 24,000 live rows are "No tanod available for automatic dispatch" for 7 cases (27 Aug - 18 Nov); append-only (cannot prune); the 0139 guard
    stopped it, nothing caps other system remarks. Low; B (retention decision).
13. **Test coverage**: 57 API-callable functions are never named in any test (incl. `admin_reset_password`, `admin_update_user`, `cancel_admin_handover`, `assignable_tanods`), and 15
    tables with policies (the whole `command_*` family) have no test. Class A (`fix/gen_test_skeleton.py`).
14. **Baseline out of date**: `supabase/baseline/README.md` says 0001-0176; migrations run to 0184. Class A (`bash supabase/baseline/build.sh`).
15. **Direct table writes from the portal**: 34 call sites (`settings.php` wording, barangay_profile, operational_settings, committee_for_category, `certificate.php` status_logs...) with
    `authenticated` still granted insert/update/delete as the only guard besides RLS. Low; A after a human look at each (`fix/gen_revoke_unused.py`).

Also noted (low/info): `password-otp` returns one exception message to the caller; 3 tables are written but never read (`mail_state`, `smart_overrides`, `tanod_committee_log`);
migrations: 177 files, 6 carry an undo note, idempotence gaps in 36 create-table / 28 create-index /
37 create-policy files; numbering gaps 0048 (scrapped backfill, status_logs is append-only) and 0108-0113 (production's 0107 was `look_shares`, that work became 0114-0120).
Author-admitted gaps: 168 marker hits (74 "later", 46 "temporary", 16 "not yet", 8 "deliberately not", 7 "todo", 5 "parked"...), top 25 strong ones in the ledger as `D4`, "still true?" unchecked.

## What passed (so nobody re-checks it)

Live portal (GET): HSTS 1 year, nonce CSP (default-src 'self', no unsafe-inline/eval), X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, cookie `__Host-` + Secure,
login and signed-in pages `no-store`, no version leak (server: cloudflare). Edge Functions: 6, `verify_jwt` matches `config.toml`, the 3 public ones (`password-otp`,
`media-cleanup`, `sign-upload`) check the caller in code and mention limits, CORS is not `*`. Secrets scan of 868 tracked files: 0 hits, no `.env` tracked.
Live DB: 61 MB, cache and index hit rate 1.00. Engine: a failing lexicon does not stop filing (`filing_survives_engine_failure: True`).

## Coverage

| Scanned | N |
|---|---|
| portal pages (admin/*.php) / include files | 46 / 38 (36 page loads captured per rung, 4 rungs, 2,422 requests, 368 distinct) |
| presses: POST forms / htmx-style swaps / fetch calls | 591 / 0 (the portal's `press.js` boosts plain forms) / 107 |
| pages with a POST handler | 44 (every one reaches `csrf_check`, login/reset excepted) |
| tables / RLS tables / policies | 106 / 105 / 167 |
| functions (public, project-owned) / triggers / cron jobs | 408 / 62 / 21 |
| RPCs called by clients | 187 (0 missing, 0 not granted); API-callable never called: 1 (`is_identity_media_url`) |
| status/enum values checked by the lifecycle detector | 55 (14 findings, mostly "no literal assignment", low) |
| notification kinds checked for producer + consumer | all (2 unlabelled) |
| migrations / pgTAP scripts / Edge Functions | 177 / 61 / 6 |
| roles replayed | super, captain, Kagawad (committee), staff (moderator) on the portal; resident, tanod on a short catalogue of the app's reads |

## Could not prove

- **Absolute timings**: laptop PostgreSQL, not Singapore; ratios 1x vs 250x are the evidence. Data is synthetic (bulk history loaded with the SMART triage trigger off, newest 3,000 open
  cases triaged), so engine tables are smaller than live would be at 20,000. 250x replay hit the 30 s per-request cap on the worst queries, so "30,010 ms" means "more than 30 s".
- **SMART at 1x** was not measured in this run (the first attempt failed on a role-setup bug, fixed afterwards); only 250x is in `out/smart_250x.json`.
- Page requests were recorded against the test fake backend, so data-dependent follow-ups on live (pagination, optional blocks) may differ; the phone app is covered by 8 hand-written
  reads, not every screen. Writes (RPCs that change data) were replayed on the throwaway only where a page issues them on load.
- Lifecycle/producer-consumer detectors are text heuristics over function bodies (a status set through a variable, not a literal, is invisible); every D-row is a lead, not a verdict.
  "Still true today" for the author-admitted markers is not judged. Columns written but never read were not checked (tables were).
- `supabase secrets list` was not run (not on the read-only list), so F08 (Cloudinary secrets) is carried from the earlier sweep, not re-proved.
- Rate limits and error leakage of Edge Functions were read in code, not exercised.

## Next (round 2, after this is pushed)

Class A generators in `tools/sweep/fix/` (notice report_id, missing index, revoke unused right, log instead of swallow, pgTAP skeletons) each emitting a DRAFT migration
(0185+, "DRAFT: not applied until Ace says apply NNNN", with an undo note) and a test that fails before and passes after on the throwaway; options files in `docs/sweep/options/`
for the B rows (first: reopen flow K-01, case rule K-04). Nothing is applied.
