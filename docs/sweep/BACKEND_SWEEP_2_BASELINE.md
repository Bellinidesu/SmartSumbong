# Backend sweep 2: scripted baseline + round 2 (20 Nov 2026)

Branch `backend-sweep-2`, PR 439 (**0185-0187 applied live 20 Nov**; Ace merges). Everything below was found by scripts in `tools/sweep/` (re-run: `bash tools/sweep/run_all.sh`, ~45 min; `quick` = static only, ~1 min).
Read-only against the live project (live row counts, `supabase inspect db`, GETs of the portal's headers). Load and probe results come from throwaway PostgreSQL 16 + PostGIS databases on a
laptop built from migrations 0001-0184, driven through a real PostgREST or directly as each rung's own database role (row level security on): **ratios, not Singapore milliseconds**.
The sweep itself changed nothing live. Drafts were kept in `supabase/drafts/` until Ace said apply; 0185-0187 have since been applied and moved to `supabase/migrations/` (see Applied 20 Nov). The remaining skeleton test stays in `supabase/drafts/tests/`.

## Verdict

The perimeter is sound; the problem is **scale for the scoped rungs**, plus a few broken flows. Headers, CSP, cookies, Edge Function auth, grants and RPC wiring are clean; filing survives
every injected engine/push/vault failure. But at 20,000 cases a Kagawad's or staff member's pages do not load (queries pass 15-30 s); option B in `docs/sweep/options/K-04` brings that to ~40 ms with
the same visible cases (proved). The reopen/appeal flow, complaint printing and the notice reach are broken by small gaps; 0185 (applied) fixes the notice part.

## Counts (ledger rows, `docs/sweep/GAP_LEDGER.md`; several rows can be one cause)

| critical | high | medium | low | info | total |
|---|---|---|---|---|---|
| 0 | 10 | 32 | 55 | 29 | 126 open (+23 fixed or done) |

Fix class (open rows): **A mechanical 33, B needs one decision 90, C look/front end 3**. Generators exist for 3 A-kinds (below); the other A rows name the generator they would use.

## Top violations (proof pointer -> fix)

1. **Kagawad/staff reads are O(rows x case rule)**: committee `reports` list query 84 ms at 1x, **>30 s** at 250x; `count(*)` 15 s; staff 7 s; pending-residents count (users policy) 71 ms -> 8.9 s; resident public map
   10 ms -> 7.4 s; 76 of 122 (page, role) pairs exceed 200 ms at 250x (`out/loadcost.json`). **Option B proved**: 15,082 -> 38 ms (Kagawad), 7,268 -> 19 ms (staff), identical case sets, also faster at 1x
   (97 -> 31 ms); a materialised table (C) is as fast with more risk; indexes (D) do nothing (`options/K-04-f09-case-rule.md`). Class B (core rule): needs Ace.
2. **Reopen/appeal flow** (K-01): the request notices go to every active admin with **no report_id**; the probe shows 6 admins told, **4 of whom cannot open the case**, no Review button; `reopen_report()` works
   (Kagawad, staff handling it, super; resolved and closed) but nothing calls it; no decline path. **0185** (applied) fixes the notice; options A/B/C in `options/K-01-reopen-flow.md` (the button is class C).
3. **`complaint-print.php` loses every photo**: it orders `report_media` by `created_at`; the live column is `uploaded_at` (checked live); the call is optional so the page prints without evidence and shows no error.
   One-word PHP fix (class A, not a migration).
4. **SMART at 20,000 cases**: `smart_watch()` (cron every 5 min) 46.5 s; `smart_queue` 0.6-0.9 s per rung (budget 0.2 s); filing 158 ms (triage 119 ms). Class B.
5. **Engine failures are invisible and some abort real presses** (injection): with scoring/triage broken `file_report` still succeeds but the only trace is a server-log warning; a failing `_smart_event` write **aborts
   `admin_dispatch`**; a failing notification trigger **aborts review, dispatch, post message and reopen request**. **0187** (applied) records `engine_error` and makes the event log best-effort; notification
   isolation is a decision (B).
6. **34 trigger functions are executable by signed-out/signed-in callers** (3 read `auth.uid()`); a trigger needs no EXECUTE right to fire (proved: filing still works after the revoke). **0186** (applied).
7. **28 API-callable functions have no caller of any kind** (strict cross-check; the first pass counted comments and tests as callers and said 1): the Inbox suite (`send_mail`, `mail_*`: backend without a screen), SMART
   screens not built (`smart_read`, `smart_duplicates`, `smart_similar_cases`, `smart_verify*`), `reopen_report`, `release_case`, `answer_reroute_question`, `reset_admin_password`, `places_status`, `assignable_tanods`,
   `audit_integrity`, `command_suggest`, 2 dead trigger functions; and 27 functions callable by the API that only other functions call (`options/B-dead-code.md`).
8. **Every Kagawad/staff page issues calls that are always refused** (`smart_deadline_risk` + 4 more `smart_*`, 20+ pages); pages make 39-42 backend requests per load (`options/B-role-symmetry.md`).
9. **Lifecycle (probed, not guessed)**: `archived` is unreachable and a dead end for every role; `cancelled` is a dead end (owner only in); `assigned` is entered only by `finalize_retirement`. 27 real from->to edges
   (`out/probe_lifecycle.json`; `options/B-state-machine.md`).
10. **Notices without a label**: kinds `look_around` and `tanod_committee` are produced but have no label in the portal or the app (class C).
11. **status_logs is 95% one historic burst** (22,910 of 24,000 live rows, 7 cases, stopped by 0139); append-only, nothing caps other system remarks. Low.
12. **Test coverage**: 57 API-callable functions are never named in a test (the generated skeleton already finds the 3 anon-executable trigger functions); 15 RLS tables have no test.
13. **Baseline out of date** (README says 0176, migrations run to 0184): `bash supabase/baseline/build.sh`. Class A.
14. **Direct table writes from the portal**: 34 sites (settings, wording, barangay_profile, certificate status_logs...) rely on grants + RLS alone. Low; A after a human look at each.
15. `request_retirement` succeeds for staff: intended (0166, confirmed by Ace 20 Nov). Only super can `request_ocr_rescan`: confirm intent (`options/B-request-decision.md`).

## What the probers found that the text detectors missed or got wrong

- `reopen_report` DOES reopen a closed case (the detector said closed cases cannot be reopened); the real gap is that nothing calls it and the resident is never answered.
- The reopen notice's reach was inferred as "every admin"; the probe measured it (6 told, 4 cannot open the case) and found `request_appeal` identical.
- Failure injection showed a failing event log or notification trigger **aborts real presses**, which no text scan could see, and that every engine failure is silent.
- The strict caller check moved "never called" from 1 to **28**.
- The probers cleared false leads: **14 of 16 doc claims confirmed** (staff do not assign/forward/take over, captain is view-only, residents cannot review, a Kagawad assigns, staff flag...); 2 not provable
  (fixtures lacked a Chairman account / extension conditions). No doc contradiction was proven.

## Checked and fine (counts only)

| Examined | Count | Consistent |
|---|---|---|
| Portal pages / POST handlers / form posts | 46 / 44 / 591 | all 44 reach `csrf_check` (login/reset excepted); every RPC the portal, app and Edge Functions call exists and is granted (187) |
| Functions in grants.txt vs database | 408 | 0 stale grants, 0 functions missing from grants.txt, 0 SQL calls to an undefined function |
| API-callable functions by caller | 295 | 183 client-called, 4 string-referenced, 53 policy/trigger/cron, 27 database-only (the rest are the orphans above) |
| Lifecycle values (report, dispatch, concern, retirement, verification, profile, escalation...) | 55 | 41 behave as designed |
| Dynamic probes | 227 functions, 37,642 probes | ok 7,641 / denied 23,938 / invalid 6,060 / fixture 3; signed-out callers can run exactly 12 functions (login lockout, catalogue, hall display, error log...) |
| Notice reach | 33 functions, 80 reaches | every case notice with a report_id reached only people who can open the case; only reopen/appeal leak |
| Request/decision pairs | 8 | 6 have a working decision path and tell the requester back; reopen and ocr rescan are the gaps above |
| Doc claims tested against behaviour | 16 | 14 confirmed, 2 not provable |
| Failure injection | 7 failures x 6 presses | `file_report` survived all 7; push gateway and secrets vault broke nothing; a failing audit chain blocks case actions (by design) |
| Live portal headers | 4 URLs | HSTS, nonce CSP (no unsafe-inline/eval), X-Frame, nosniff, referrer, permissions-policy, `__Host-` Secure cookie, no-store on signed-in pages, no version leak |
| Edge Functions | 6 | `verify_jwt` matches config.toml; the 3 public ones check the caller in code; CORS not `*` |
| Secrets scan | 868 tracked files | 0 hits; no `.env` tracked |
| Notification kinds | 15 | 13 have a producer and a label |
| Author-admitted markers (168 hits) | judged against the schema | 97 noise (UI strings), 4 still true, 1 no longer true (`REOPEN IS NOT ADDED`: reopen exists now), 66 need a human |

## Drafts -> applied live 20 Nov (Ace: "apply 185 186 187")

| No. | What | Test (now supabase/tests) | Test result before / after |
|---|---|---|---|
| 0185 `notice_report_id` | reopen and appeal notices carry the case, so only admins who can open it are told | 63 | 1 ok 3 FAIL / 4 ok |
| 0186 `revoke_dead_trigger_functions` | revoke API execute on 34 trigger functions (filing still works) | 64 | 2 ok 1 FAIL / 3 ok |
| 0187 `engine_failures_recorded` | triage failure recorded as `engine_error`; `_smart_event` best-effort | 65 | 1 ok 2 FAIL / 3 ok |

## Applied 20 Nov (applied by the coordinator, staged one by one, verified read-only after each; not touched again by the sweep)

- 0185: `request_reopen` / `request_appeal` now insert notifications with `report_id`.
- 0186: 0 of 50 trigger functions callable by anon/authenticated afterwards; none disabled; roles and queues unchanged.
- 0187: `_smart_triage_after_write` records `engine_error`; `_smart_event` is best-effort.
- 0188 (applied after Ace's "apply 0188", PR 'Notification failures isolated'): `_notifications_scope` is security definer, still scopes by `_user_sees_case`, records `notice_error`, has a best-effort exception block (fails closed); anon/authenticated cannot execute it; role counts unchanged. Test `supabase/tests/66_notification_failures_isolated.sql`. Ledger K-11 and the four matching injection rows: fixed live 20 Nov (0188).
- 0189 `case_rule_at_scale` (K-04 option B, applied after Ace's "apply 0189"; dry run showed only 0189, applied in about 2 s): the policies read the caller's facts once per query through 7 security-definer `_my_*` set helpers. Verified read-only: **198 of 198** per-role/per-table (9 test roles x 22 tables) count + md5 fingerprints of visible rows identical before vs after; 7 helpers security definer with pinned search_path, 0 callable by anon, 7 by signed-in; 167 policies unchanged in count; role counts unchanged. Tests: `supabase/tests/67_case_rule_equivalence.sql` (equivalence) and `68_case_rule_at_scale.sql` (fails before, passes after). The undo stays as documentation in `supabase/drafts/0189_undo.sql`. Ledger K-04 fixed; the L-rows are marked as addressed (re-measure with run_all.sh).
- The three files moved from `supabase/drafts/` to `supabase/migrations/`, the tests to `supabase/tests/63-65`; `baseline.sql` and `grants.txt` rebuilt for 0001-0187. Ledger rows K-07, K-08, K-09 and the matching detector/prober rows are marked "fixed live 20 Nov"; the reopen flow (K-01) stays open for the answer/decline part.

## Applied 21 Nov

- 0190 `smart_module_set_based` (follow-up to 0189, applied after Ace's "apply 0190"; dry run showed only 0190, applied in about 2 s): `smart_module()` reads the visible-case set `_my_scoped_case_ids()` once instead of running the case rule per open case (Kagawad 3,742 -> 271 ms at 250x, 845 -> 127 ms at 50x, 114 -> 114 ms at 1x on the sweep database). Verified read-only on live: `smart_module()` output fingerprints per admin test role x top-level key identical before vs after (**70 of 70**); grants unchanged; the function now uses `_my_scoped_case_ids`. Test `supabase/tests/70_smart_module_set_based.sql` (fails before, passes after; equivalence for 11 rungs in 3 fixture variants). Undo kept as documentation: `supabase/drafts/0190_undo.sql` (tested: restores the identical definition). Ledger K-12 fixed.

- 0191 `case_rule_consistency` (Ace: "apply 0191"; dry run showed only 0191, applied in about 2 s): the four old behaviours of the case rule made consistent between `_user_sees_case` and the 0189 set helpers: (1) rows of soft-deleted cases hidden from Kagawad and staff, (2) retired admins see nothing and get no case notices, (3) the committee branch needs the committee switched on (and `assign_case` refuses to place a case with a switched-off committee), (4) a case's handler keeps seeing it while it awaits placement. Verified on live with per-role snapshots: `smart_module()` output 70/70 identical; table snapshots across 9 test roles x 22 tables: the only difference attributable to 0191 is the committee2 status_logs count 10,397 -> 10,071 (-326 = rows of deleted cases a Kagawad could see: item 1); the 3 users fingerprint lines for super/captain/super2 (same count 23) are one resident row updated at 01:52 by an email-confirm test, unrelated. Tests: `supabase/tests/71_case_rule_consistency.sql` (fails before, passes after) and the updated `67_case_rule_equivalence.sql`; undo kept as documentation: `supabase/drafts/0191_undo.sql`. Ledger K-13 to K-17 fixed.

- 0192 `mechanical_fixes` (Ace: "apply 0192"; dry run showed only 0192, applied in about 6 s): the API's execute right is closed on 16 helpers that only other database code calls (each proved safe: every caller SECURITY DEFINER, nothing else depends on it; 11 others excluded with reasons), and `_command_auto()` records its swallowed race as a `command_auto_skipped` event. Verified read-only on live: 0 of 16 callable by anon or signed-in; smart_module fingerprints, role counts and queues unchanged for committee/moderator; the only differences are the super/captain report counts (+1 report filed after the before-snapshot); 0 new portal_errors; 0 command_auto_skipped events so far. Test `supabase/tests/76_mechanical_fixes.sql`; undo kept as documentation: `supabase/drafts/0192_undo.sql`. Ledger C-03 and D2-06 fixed.

Options files (no migration until Ace picks): `K-01-reopen-flow`, `K-04-f09-case-rule` (timed at 1x/50x/250x), `B-dead-code`, `B-state-machine`, `B-request-decision`, `B-role-symmetry`.
Not drafted on purpose: the case-rule policy (core visibility rule).


## Decisions after round 2 (Ace, 20 Nov)

K-04 = option B, run as its own careful round and applied as 0189 (below). K-01 = option B: the reopen button/answer card is front end (class C, Rose; ledger K-06). Notification failures: isolated by 0188. Staff retirement rule: confirmed by Ace, staff may request retirement (0166), no change (K-10).

## Coverage

| Scanned | N |
|---|---|
| portal pages / include files / requests captured (4 rungs) | 46 / 38 / 2,422 (368 distinct) |
| tables / RLS tables / policies / functions / triggers / cron jobs | 106 / 105 / 167 / 408 / 62 / 21 |
| migrations / pgTAP scripts / Edge Functions | 177 / 61 / 6 |
| probes: functions / actors / states / handling variants | 227 / 11 / 11 / 3 |

## Could not prove

- Absolute (Singapore) timings; the 250x worst queries hit my 30 s per-request cap ("over 30 s"). Synthetic data (triage trigger off for bulk history), so engine tables are smaller than live would be.
- SMART at 1x was not measured (only 250x). The K-04 equivalence proof compares the cases of one Kagawad and one staff member, not every user; the child tables' policies (users, dispatches, status_logs) were not rewritten or timed.
- 57 API functions never succeeded in any fixture (preconditions the fixtures lack: `admin_dispatch` needs a target date, `endorse_retirement` a roster, `request_profile_change` a valid mobile format...): their role
  matrix is "denied or invalid", not "allowed". The probers prove the denials and the allowed paths they reached, not every business precondition.
- 130 "page opens, action refused" leads are mostly by design (a Kagawad forwards, staff flag; role-specific buttons) and not each judged. The phone app is covered by 8 hand-written reads.
- Edge Function rate limits and error leakage were read in code, not exercised; F08 (Cloudinary secrets) is carried over from the earlier sweep (`supabase secrets list` is not on the read-only list).
- A "no literal assignment" lifecycle lead can be a status set through a variable; the probe matrix is the authority there.
