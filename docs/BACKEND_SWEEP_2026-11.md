# Backend sweep, 19-20 Nov 2026

Audit of the database, the Edge Functions and the operations around them, with draft fixes. Read-only against the live project
(Singapore, `vmtzyyyxcmhtqgeeorhg`): catalog and count queries, and `set role` reads with a development team account to prove what
each rung sees. Anything that needed a write was proved on a throwaway PostgreSQL 17 built from `supabase/migrations`
(0001–0176), the same way CI builds it. Nothing was applied, deployed or set. No secret value was read or printed.

## Verdict

The base is sound: every one of the 105 public tables has row level security on, every security definer function pins its
`search_path`, the live grants equal `supabase/grants.txt` line for line (531 objects), signed-out callers read only eight reference tables,
residents and tanods are refused by every administrator function that was tried, the nightly backup and all 21 cron jobs are healthy,
and the new 0174–0176 code (email reset, case hierarchy, one category) does what it says. What is **not** sound is the layer under
the functions: the API roles can write most tables directly, and several policies are wider than the product's own rules. Two
findings matter before the 2 Dec defense: **any administrator, down to staff, can read every resident's profile and open their ID
photo** (F01), and **a verified resident can post a report straight to the API with a handler, a status and a tracking id of their
choosing** (F02). Both are fixed by drafts below. 8 draft migrations (0177–0184), each with a check that fails before it and passes
after, are in this branch; the full database suite (61 scripts) passes with all of them applied.

| Severity | Count | Findings |
|---|---|---|
| Critical | 0 | |
| High | 2 | F01, F02 |
| Medium | 7 | F03 to F09 |
| Low | 10 | F10 to F19 |
| Info | 5 | F20 to F24 |

**Status, 20 Nov: 0177 to 0184 are applied live** (see "Applied 20 Nov" at the end). Still open: the `password-otp` code fix (F07, not deployed, Ace's word), the Cloudinary secrets (F08, Ace's), the one-line `spatial.js` change (F12, goes out with the next Render deploy), and F09 (not drafted).

---

## High

### F01. Every administrator reads every account; staff and Kagawad reach residents' IDs *(fixed live 20 Nov, 0179)*
- **Where:** policies `users_self_read`, `profile_requests_read`, `account_audit_read` (`is_admin()`), RPC `admin_candidates()`; `is_admin()` itself; `supabase/functions/sign-upload/handler.ts:mayView`.
- **What:** `users_self_read` is "your own row, or any administrator's". `is_admin()` is `my_role() = 'admin'`: any tier, and a suspended or retired administrator too. So staff (who may see only cases assigned to them, 0175) and Kagawad (who have no Residents page) can `GET /rest/v1/users` and read mobile number, email, address, `id_image_url`, OCR fields of every resident. `sign-upload` then signs a viewing link for any stored private ID photo for "an administrator" (any tier), so the address is enough. `account_audit` (30 password resets, number and email changes) and `profile_requests` (new names, ID photos waiting) are read the same way. `admin_candidates()` (invoker) returns verified residents' email and number to staff.
- **Proof (live, development staff account, counts only):** `set role authenticated` with a staff (moderator) account: users visible 23 of 23 (8 of 8 residents), account_audit 30 of 30, profile_requests 3 of 3, while reports 1, notifications 1, status_logs 1 (the case rules work). `select count(*) from admin_candidates('')` as staff: 3. Same on the local build. `docs/ROLES_AND_PAGES.md` says Residents: super admin yes, Kagawad no, staff no.
- **Fix:** **0179** (check `57_users_visibility.sql`: 6 checks, fail before, pass after). `is_admin()` becomes "active administrator" (`admin_tier() is not null`); a new `_admin_sees_user()` lets Kagawad and staff read themselves, every administrator and tanod (as before), and a resident only through a case they may open; `profile_requests` and `account_audit` go to the super admins and the captain; `admin_candidates()` to super admins. **Risk:** click through Case Reports, the case page and Personnel as a Kagawad and as staff after applying; the reporter's name must still show on cases they open. Cost per resident row is the case rule per report until the first visible one; fine at this size.
- Not changed, and worth Ace's decision: every administrator still reads every tanod row (`last_geom`, duty status) and the Workspace staff tables (`staff_credentials`, `staff_dates`, `staff_leave`) are readable by every administrator.

### F02. A resident can write any column of a report *(fixed live 20 Nov, 0177)*
- **Where:** policy `reports_resident_insert`, table rights on `reports`.
- **What:** the policy checks only that the row is the resident's own and that they are verified. The table accepts every column. A direct `POST /rest/v1/reports` sets `status = 'validated'` (skips review), `handler_id` (a Kagawad of their choosing), `committee`, `is_sensitive`, `assigned_to`, dates, and `tracking_id`. A chosen tracking id such as `BRG-2026-0020` makes the filing of the real report that reaches 20 fail on `reports_tracking_id_key` (the generator does not retry): one resident can block everyone's filing, number by number (the daily limit of 20 only slows it).
- **Proof (local build):** as a resident, `insert into reports (..., status, handler_id, committee, tracking_id, is_sensitive, assigned_to) values (..., 'validated', <kagawad>, 'environment', 'BRG-FAKE', true, <self>)` returned the row with all of it; `BRG-2026-0020` inserted; the next legitimate filing was numbered 0010 and would collide at 0020.
- **Fix:** **0177** (check `55_reports_direct_writes.sql`: 4 checks). `file_report` (the only writer, security invoker) inserts exactly `resident_id, is_anonymous, category, subject, description, latitude, longitude, client_ref`; the migration grants INSERT on those columns only.

---

## Medium

### F03. An administrator who may act on a case can patch any column of it *(fixed live 20 Nov, 0177)*
- **Where:** policy `reports_admin_update` (all columns writable).
- **What:** nothing in the portal (PHP, JS) or the app updates `reports` directly; every change is a function. But a handler (or any in-scope super admin) holding a token can `PATCH /rest/v1/reports`: `category` (breaks the one-category rule of 0176 after the fact, the case keeps a concern of the old category), `resident_id` (hands the case to another resident), `tracking_id`, `created_at`, `status = 'closed'` (no `status_logs` entry, so the hash-chained trail misses it).
- **Proof (local):** Kagawad takes a case, `update reports set category = 'environmental_waste_hazard'` returns the row; then `set ... tracking_id = 'BRG-HACK', status = 'closed', resident_id = <other>` succeeded; `status_logs` for the case stayed empty.
- **Fix:** **0177** also drops the update right and policy (the functions are definer and unaffected). Same check file.

### F04. Direct writes to dispatches, deadline extensions, retirement decisions, accounts, look-arounds, notifications *(fixed live 20 Nov, 0178)*
- **Where:** policies `dispatches_admin_insert/update/delete`, `sla_extensions_admin_*`, `retirement_requests_super_*`, `users_super_insert/delete`, `look_shares_admin_update/delete`, `notifications_update`.
- **What:** no client uses them. They let an administrator bypass the functions' rules: a Kagawad who is **not** the handler deleted a dispatch row (the tanod's assignment history) with one DELETE; the handler inserted a dispatch without `admin_dispatch`'s checks; extensions skip the cap that sends the request up; retirement decisions skip the Kagawad's endorsement; a person could rewrite the text, kind and case of their own notifications (the app only ever sets `is_read`).
- **Proof (local):** as a second Kagawad of the same committee, `delete from dispatches where report_id = ...` returned `DELETE 1`. `status_logs` direct inserts were already guarded by `_case_guard_row` (clean).
- **Fix:** **0178** (check `56_least_privilege_writes.sql`: 5 checks). Revokes the write rights and drops the dead policies; `look_shares` keeps INSERT (the portal's Look around) and UPDATE of `read_at` only; `notifications` UPDATE of `is_read` only.

### F05. The queue (Next up) shows a Kagawad cases that left their committee, and misses the ones that arrived *(fixed live 20 Nov, 0180)*
- **Where:** `smart_queue()` (0175 changed only the staff branch).
- **What:** the Kagawad branch filters by `admin_sees_category`, not by the case rule. After a forward, the old committee's Kagawad still lists the case (tracking id, subject) while Case Reports shows 0 rows; the receiving committee's queue does not list it (their category is not the case's).
- **Proof (local):** Environment Kagawad forwards an Environment case to Peace and Order: `select count(*) from reports` 0, `smart_queue` still lists it; the Peace and Order Kagawad's queue does not.
- **Fix:** **0180** (check `58_smart_queue_scope.sql`): every rung uses `admin_sees_report` (full viewers short-circuit).

### F06. A sensitive case can be published on the residents' map *(fixed live 20 Nov, 0184)*
- **Where:** `set_report_public()`, `public_incidents()`.
- **What:** nothing stops an administrator from publishing a sensitive case; `public_incidents()` then returns its category, status and coordinates to every signed-in resident. (Live today: 4 public cases, none sensitive; one anonymous, which is fine.)
- **Proof (local):** super admin marks a case sensitive and publishes it; a resident's `public_incidents()` returns it.
- **Fix:** **0184** (check `62_sensitive_not_public.sql`): publishing is refused, the function leaves sensitive cases out, any already public is taken off.

### F07. password-otp: hourly limits can be beaten by parallel requests, and there is no per-connection or overall limit *(code fix in the branch, NOT deployed: open)*
- **Where:** `supabase/functions/password-otp/handler.ts` (`send`, `mobileSend`, `emailSend`).
- **What:** "3 codes an hour" is read-then-write: it counts rows in `password_otps`, then inserts. Twenty parallel requests all see 0 and all send. Each is a Gmail send (a free Gmail account caps near 500 a day, so a flood stops resets for everyone) or a Semaphore text (Ace pays credits, once the key is set). There is no limit per connection and none overall, and an unknown number costs nothing to ask about, so a script can walk numbers. `email_send` mails a code to whatever address the person typed, so any account can make the barangay's sender mail a stranger (3 an hour per account, unlimited accounts).
- **Proof:** code reading plus the unit tests (`deno test`); a live burst was not run (it would send mail).
- **Fix (code, in this branch; deploy is Ace's):** the allowances are taken atomically with the existing `take_rate_slot` (one upsert): 3 an hour per account for each purpose, 20 an hour per connection, 200 an hour overall, and the limit applies before the account lookup, so an unknown number gets the same 429. Two new tests, all 17 pass. No migration.
- Accepted as designed (documented in the header): the masked address (first letter and domain) is shown to whoever asks about a number with a confirmed email, and timing differs slightly for accounts that really send mail.

### F08. The Cloudinary secrets are not among the Edge Function secrets *(open: Ace's)*
- **Where:** `supabase secrets list` (names and digests only) shows `FCM_*`, `VAPID_*`, `SMTP_*`, `PUSH_WEBHOOK_SECRET`, `MEDIA_CLEANUP_SECRET` and the platform ones; no `CLOUDINARY_API_KEY` or `CLOUDINARY_API_SECRET`, and no `SEMAPHORE_API_KEY` (known, Ace's).
- **What:** without them `sign-upload` answers 503 and `media-cleanup` answers 503, so the app uses the unsigned upload preset (anyone with the cloud name can upload) and the identity-photo cleanup queue does not drain: `media_trash` holds 2 selfies, the older queued 30 Oct (3 weeks; policy is one week), while the nightly cron "succeeds" (it only posts to the function). `DEPLOY.md` says they go to the functions; `docs/SECRETS.md` did not list them (fixed).
- **Not proven:** the function's own response to the nightly post (pg_net keeps responses only a few hours). Set the two secrets (Ace), redeploy nothing, and the queue should empty the next night.

### F09. Scoped administrators pay per row for the case rule: counts take seconds at volume *(open, not drafted)*
- **Where:** `_user_sees_case` called from policies (`reports_resident_read`, `notifications_read`, every child table).
- **What:** about 0.35 to 0.6 ms per row. Measured on the local build with 20,000 reports and 60,000 notifications (unindexed laptop, warm): Kagawad `select count(*) from reports` 11.7 s, notifications 13.6 s; staff 6.9 s and 9.8 s; a super admin 28 ms and 16 ms (short-circuit). Lists with `order by ... limit 50` are fine (92 to 230 ms). `smart_queue(null, 50)` 0.4 to 0.6 s for everyone. The CI budget (`perf/query_budget.sql`) times only the admin, so this is outside it.
- **Impact today:** none (78 reports); about 1 s per count at 2,000 cases, which is the first thing a Kagawad's chips and pager will feel (the portal counts with `Prefer: count=exact`).
- **Fix (not drafted, core rule):** have the policy pass the row's `committee`, `awaiting_placement` and `assigned_to` instead of re-reading `reports` and `users` inside the function, and add a Kagawad and a staff case to the budget. Do it with the full suite and the budget file, not in a sweep.

---

## Low

*(fixed live 20 Nov, 0182)* - **F10. The error log can be flooded signed out.** `log_portal_error` is callable by anyone with the public key; 500 made-up messages evict the real ones and raise the hourly health alert. Local proof: 100 calls from one address filed 100 rows. Fix **0182** (check `60_error_log_rate.sql`): 60 an hour per address for browsers, 600 for the portal's server, none for functions.
*(fixed live 20 Nov, 0181)* - **F11. API roles hold every table right.** `anon` and `authenticated` have select, insert, update, delete, **truncate, references, trigger** on every table; RLS is the only guard (TRUNCATE ignores RLS; PostgREST never issues it). `anon` can write ~100 tables on paper. Fix **0181** (check `59_api_role_table_rights.sql`): `anon` keeps select on the eight reference tables only, `authenticated` loses the three rights, new tables start that way. `grants.txt` regenerated (118 lines change). Test 50 now accepts "permission denied" as unreadable.
*(fixed live 20 Nov, 0183, database side; portal line pending Render deploy)* - **F12. "Look around" never notifies the tanod.** `admin/assets/js/spatial.js:1119` inserts the tanod's notification itself; `notifications` has no insert policy, so it is refused every time and the error is swallowed (local proof: `new row violates row-level security policy`). Fix **0183** (check `61_look_share_notice.sql`): a trigger makes the notice; the JS line is removed in this branch.
- **F13. Login lockout can be used against someone.** `register_login_failure(p_mobile)` is callable signed out for any number; five calls lock that person out for 30 minutes. The per-address cap (20 failures per 15 minutes) limits one attacker to about four numbers per quarter hour, but an attacker with many addresses can keep a chosen person out. Not drafted: counting failures per (number, address) is a product choice (it also weakens brute-force protection).
- **F14. Forced password change and self-set flags.** `clear_password_change_flag()` clears the "you must change your password" mark without changing it; a resident can also set their own `is_test`, `is_retired`, `must_change_password`, `removed_at` by a direct update (only harm: to themselves; a retired flag locks them out of uploads and reset). The temporary-password flow is therefore advice, not a rule.
- **F15. Uploads have no per-person cap.** `sign-upload` signs `reports`, `dispatch` and `avatars` for any signed-in caller with no rate; only registration ID uploads are limited (10 an hour per address). A signed-in resident can fill Cloudinary. Add `take_rate_slot('upload:<id>', 60)` in the function.
- **F16. Swallowed errors, judged one by one** (every `exception when others` in public): `_main_concern` (parse of a setting, harmless), `places_refresh_file` (bad JSON from a mirror, records `last_error`: fine), `smart_replay` (re-raises real errors: fine), `smart_triage` and `_smart_triage_after_write` (a broken rule never blocks filing, by design, but only a Postgres WARNING: nothing in Recent errors), `file_report`'s concern loop (a concern that cannot be added is dropped silently: documented), `run_admin_handover_expirations` (skips a failing row and tries hourly forever, no alert). Suggest writing the last three to `portal_errors` through `log_portal_error('server', ...)`.
- **F17. Dead and disabled objects.** The administrator succession feature is switched off in the portal (`ADMIN_SUCCESSION_ENABLED = false`) but its cron job (`sweep-admin-handovers`, hourly) and functions (`admin_candidates`, `my_admin_handover_status`, `cancel_admin_handover`, `step_down_as_admin`, `run_admin_handover_expirations`) are live. Functions with no caller in `admin/`, `mobile/`, `supabase/functions/` or other functions: `_cld_sign`, `_concern_backfill`, `_system_mail`, `assert_not_client`, `assignable_tanods`, `places_status`, `release_case`, `reset_admin_password`, and the SMART engine functions only the checks use (`smart_read`, `smart_duplicates`, `smart_similar_cases`, `smart_verify`, `smart_verify_queue`). BarangayMail's tables stay unused (15 Nov note). Dropping them is safe once Ace confirms; not drafted, because the engine checks (04 to 10) call several of them.
- **F18. Status flapping history.** Two reports hold 13,393 and 9,572 `status_logs` rows (validated and pending_review alternating, 21 Aug to 1 Oct): 23,994 rows, 15 of the database's 61 MB. Not happening any more (last row 1 Oct). The table is append-only and hash-chained, so the rows stay; worth knowing before an export.
- **F19. Browser noise fills Recent errors.** `Transition was aborted because of invalid state` (ViewTransition, 21 hits since 5 Nov on notifications, residents and personnel pages) is an unhandled promise from `startViewTransition(...).finished`; catch it where the transition starts. Real bugs in the log over the last 30 days: none (the rest are the Oct dashboard `T is not a function`, fixed, a `probe.php` test, and two `send-dispatch-push` 401 "JWT issued at" clock-skew rows on 25 Oct).

## Info

- **F20.** Six live function bodies carry CRLF line endings (`_case_guard_row`, `assignable_tanods`, `nearest_available_tanod`, `request_account_deletion`, `reroute_dispatch`, `tanod_dispatch_cap`) from Windows checkouts; identical after stripping `\r`. Harmless; 0175 already copes.
- **F21.** Baseline against live: after stripping that, the object lists are identical (functions, columns, policies, indexes, constraints, triggers, enums, cron, realtime, RLS flags). The only live-only object is the Database Webhook trigger `notifications.dispatch_push`, which is dashboard-managed by design.
- **F22.** `level-switch` lets a development team member open a session as a test account; a super admin can set `is_dev` on themselves, so it is a super admin's power, not an escalation.
- **F23.** No Storage buckets exist (media is in Cloudinary), so there are no storage policies to audit.
- **F24.** The reset code goes only to a confirmed email; if Gmail refuses, the stored code is deleted and the person gets a 502 "try again" (no SMS fallback in that case, by design: SMS is only for accounts with no confirmed email and needs the Semaphore key, which is not set). If Semaphore is down the same applies. Cloudinary down: signed uploads fail and the app falls back to the preset (F08).

---

## Checked and clean

**Security**
- RLS on for all 105 public tables; 181 policies read in full. No `true` policy for a write; the `true`/public reads are the eight reference tables only (barangay profile and boundary, complaint types and options, hazard zones, hotlines, wording).
- Live grants equal `supabase/grants.txt` (diff empty). 62 functions are callable signed out; the non-trigger ones are the login lockout, catalogue, command hall (token, 192 bits, hashed), release info, `log_portal_error` (F10) and pure helpers.
- 327 security definer functions, all with `set search_path`; `public` and `extensions` are not creatable by `anon` or `authenticated`.
- Of the 220 functions signed-in callers can run, all but 16 name an administrator or ownership check in their body; the 16 were read (helpers, login lockout, `smart_eta`: aggregates only, `extensions_used`, `feature_on`, `command_hall`). A resident and a tanod were refused by 16 administrator functions tried (assign, take, take over, forward, publish, set status, review, approve, suspend, access, rules); staff, Kagawad and captain by the super-admin ones.
- `case_forward_flags` view is `security_invoker`. `reports` rows readable by anon: 0; users, notifications, messages: 0.
- Edge Functions: `verify_jwt` matches `config.toml` for all six; `media-cleanup` and `send-dispatch-push` compare their secrets in constant time; `delete-account` acts only for the caller's own token and refuses non-residents; errors returned to callers are generic; every outside call has a 10 s limit; SMTP address and header injection are closed (`plainAddress`, CRLF stripped, base64 bodies); codes are 6 digits drawn uniformly, HMAC-keyed with the service key, 10 minutes, 5 tries counted under a row lock in `otp_attempt`, single use, bound to the number or address; a reset ends every session.
- PII: `notifications` (own rows only; case-linked ones also need the case rule), `case_handler_log`, chat messages, `report_triage`, `status_logs` and `report_concerns` follow the case rule (a staff member without an assignment saw 1 of 78 rows in each, their own); `public_incidents()` returns only id, category, status, coordinates and time.

**Hierarchy and visibility (0175), proved on the local build** (`53_case_hierarchy.sql` also passes)
- Staff see nothing of an unassigned committee case in reports, concerns, triage, logs, queue, messages, notifications, SMART case card, why-order, duplicates, similar cases, tanod ranking, roster, assignees (all refused with "not assigned to you" or empty).
- Take-over: staff never; Kagawad only from staff of their committee; a second Kagawad of the same committee cannot; super admin from anyone; captain cannot write. Enforced in `_may_take_over` and the handler trigger.
- Assign and answer: row lock (`for update`) serialises accept, decline and re-assign; a waiting assignment ends when the case changes hands, committee or status; the assignee cannot act before accepting, neither through functions nor by direct insert (`_case_guard_row`).
- A forward tells only the target committee's Kagawad by name, the super admins when it has none; the origin committee gets nothing; a forwarded-away notice stops showing.
- One category per case: a resident's `add_report_concern` and a direct concern insert of another category are refused; same-category concerns file; `file_report` resend with the same `client_ref` returns the first report. The only bypass was F03 (a direct `PATCH` of `reports.category`), closed by 0177.
- Realtime publishes ten tables, all with RLS, so a channel only carries rows the subscriber's policies show.

**Integrity and hygiene**
- Every foreign key has an index; no duplicate indexes; unused indexes (idx_scan 0 since 3 Nov) are all foreign-key covers or small (`places_*` 1.3 MB): keep.
- No orphans: 23 auth users = 23 profiles; the 9 reports without a main concern are all soft-deleted before 0130; the 5 in-progress cases without a live dispatch are awaiting approval or deleted; 2 live cases still mix categories (known, 0176 leaves them); 0 stale assignments.
- Enum `notification_kind` (15 values): each has a writer; `look_around` had none until 0183 (F12).
- Every migration applies from scratch to a clean database; the baseline header says 0001 to 0176 and matches.
- Cache hit 99.9999% (tables) and 99.996% (indexes), no bloat, 61 MB.

**Operations**
- Nightly backup: success on each of the last 6 runs (up to 6 hours late, GitHub's scheduler); keep-awake workflow: success daily; 21 cron jobs: all `succeeded` over 2 days; `pg_cron` history trimmed nightly; `portal_errors` capped at 500; `purge_old_records` covers OTPs, attendance, punches, inbox, workspace; `media_trash` is the one queue that is not draining (F08).

## Could not prove
- Realtime delivery per role (no Realtime server in the local build): reasoned from RLS only.
- A live burst against `password-otp` (it would send mail and use credits): F07 is proved by code and unit tests.
- The Cloudinary secrets (F08): inferred from the secrets list and the stuck queue, not from a call.
- The cost numbers (F09) are from a laptop build with synthetic data, not the Singapore instance.
- `set_case_sensitive`, `feature_set`, `category_save` were probed under names that do not exist; the same guards were read in code instead.
- Local Windows build differences: `pg_cron` is a stand-in, so check 03's failed-job alert and the time-of-day dependent check 04 ("night") fail locally on the base as well; every other check passes.

## Where things are
- Drafts: `supabase/migrations/0177` to `0184`; checks `supabase/tests/55` to `62`; `supabase/grants.txt` regenerated; `password-otp/handler.ts` and its tests; `admin/assets/js/spatial.js` (one line); docs corrected (`schema.md` migration and table counts and the cron list, `tests/README.md`, `baseline/README.md`, `DEPLOY.md` function list and the `config push` rule, `SECRETS.md`).
- Suggested order to apply: 0177, 0178, 0184, 0180, 0182, 0183 (low risk), then 0179 (click through the Kagawad and staff pages), then 0181 last (it changes the most grant lines; run the nightly grants check after).

## Applied 20 Nov

Ace said "apply it all"; the coordinator applied 0177 to 0184 to the live project in five batches, each checked read-only with the
development team's test accounts (counts only, no writes) before the next. `supabase migration list --linked` shows 0177 to 0184 on
the remote. Nothing failed and nothing was rolled back. Edge Functions were not deployed and no secret was touched.

| Batch | Migrations | Verification | Result |
|---|---|---|---|
| 1 | 0177, 0178 | reports insert limited to 8 columns for `authenticated`; no UPDATE on reports for anyone signed in; `anon` none. Policies `reports_admin_update`, `dispatches_admin_*`, `sla_extensions_admin_*`, `retirement_requests_super_*`, `users_super_insert/delete`, `look_shares_admin_update/delete` gone. `notifications` update only `is_read`; `look_shares` update only `read_at`; `users` keeps its own UPDATE | as expected |
| 2 | 0179 | read-only impersonation, before to after: Kagawad account users 23 to 18, residents 8 to 3 (8 cases seen, 0 reporters hidden, the 3 are anonymous), `account_audit` 30 to 0, `profile_requests` 3 to 0; staff account users 23 to 16, residents 8 to 1 (1 case, its reporter visible); super admin, captain, resident and tanod unchanged | as expected; no page lost a name |
| 3 | 0180 | `smart_queue` rows before to after: super 34 to 34, captain 34 to 34, Kagawad 4 to 5, second Kagawad 20 to 20, staff 1 to 1; every row readable (0 not readable) | as expected (the Kagawad gained the case forwarded in) |
| 4 | 0181 | `anon` reads the eight reference tables (profile 1, boundary 1, categories 8, options 34, hotlines 14, hazards 2,296, wording 0: empty on live) and is refused on `users` (42501); `authenticated` rights now delete, insert, select, update only; role counts identical | as expected |
| 5 | 0182, 0183, 0184 | 0 sensitive public cases; trigger `look_share_notice` present on `look_shares`; `log_portal_error` present; a resident's `public_incidents()` returns 4 rows; role counts identical | as expected |

Scripts used (read-only, test accounts only): `role_check.sh` and `queue_check.sh` in the archive tools folder.

Unexpected: none. Housekeeping: `supabase/baseline/baseline.sql` and `supabase/grants.txt` were rebuilt from the migrations through the
repo's baseline workflow and committed to this branch.
