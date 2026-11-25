# Backend round 3 + ledger refresh (25 Nov 2026)

Branch `round3`, one PR. Everything here was **read-only against live** (SQL inside `begin read only … rollback`, `supabase inspect db`,
`functions list`, `secrets list` names, `config diff`, a `db dump` into a folder outside the repo, GETs of the portal). The only
fix is a **draft**: `supabase/drafts/0193_auth_triggers_idempotent.sql` (not applied; Ace says "apply 0193"). Numbers below are
counts, sizes and timings only.

## Ledger refresh (`docs/sweep/GAP_LEDGER.md`, `bash tools/sweep/run_all.sh`, WITH_FIX/WITH_EXP off)

Full pipeline on 0001-0192 (185 migrations), load cost at 1x/50x/250x (`SCALES=1,50,250`), probers 37,224 probes, injection, detectors.
`ledger.py` now keeps history: rows the re-run no longer produces are carried over as closed (detector ids are positional; a reused
id gets `~prev`). Closed in this refresh: K-03 (Cloudinary secrets, 20 Nov), Q-01 (print photos, #440), K-04 + K-18 (the old
L-03..L-07: no committee/staff query passes 225 ms at 250x any more), K-07..K-17 (0185-0191), C-03 and D2-06 (0192), D2-07/D2-08
(0188/0187 record notice_error/engine_error; the detector cannot see that), D6/T/P rows fixed by #445 and 0192, and **K-19, the
sign-up drift** (below). Two tool fixes: `probe_db.sh` failed whenever its dump had zero errors (`grep -c` exits 1), so run_all
silently skipped the probers; `run_all.sh` ended with exit 1 when the optional steps were off.

| re-measured (laptop DB time per page load, ms) | 1x | 50x | 250x | 20 Nov at 250x |
|---|---|---|---|---|
| cases.php, Kagawad | 172 | 248 | 737 | 132,874 |
| cases.php, staff | 85 | 153 | 409 | (>30 s queries) |
| cases.php, super admin / captain | 132 / 113 | 758 / 695 | 3,219 / 2,750 | |
| workspace.php, super admin | 192 | 491 | 1,154 | |
| resident app / tanod app | 12 / 11 | 13 / 22 | 17 / 47 | |
| (page, role) pairs over 200 ms | 0 of 122 | 34 | 63 | 76 |
| smart_queue super / Kagawad / staff | 50 / 104 / 88 | 112 / 228 / 324 | 424 / 525 / 614 | |
| smart_watch (cron, every 5 min) | 394 | 9,620 | 51,088 | 46,500 |

The new five slowest queries (L-03..L-07) are the super admin's and captain's committee-tab counts on cases.php: `case_committee`
is a computed column (a function per row), so each tab is a full pass over reports (500-625 ms at 250x, ~4 ms live).

## 1. Drift guard (priority) — `tools/sweep/drift_check.py`

**Result: live PASS on all 15 checks, 25 Nov 07:14 UTC** (1 INFO: optional secrets SEMAPHORE_API_KEY, SEMAPHORE_SENDER_NAME,
SMTP_FROM_NAME not set). It compares live, item by item, with `supabase/drift_manifest.txt` (832 lines, built from the migrations
on a local database: `--write`) and the repo's own files: auth.users triggers (2, full definition hash), pg_cron jobs (21: name,
schedule, active, command hash), realtime tables (10), extensions the migrations use (9), the Dashboard webhook
`notifications.dispatch_push`, storage buckets and storage.objects policies (repo: none), Vault secret names (2), grants (540 vs
`grants.txt`), Edge Functions + verify_jwt (6), function secret names the code reads (15 required), Auth config (`config diff`:
SMTP host = config.toml, SMTP user set, 13 Dashboard-only settings), and every public function (415), policy (167), trigger (62)
and table/view (106) by definition hash. ~10 s.

Evidence that it catches the real failure: on the restored copy of live (section 4), **before** the post-restore steps it FAILs
"auth.users triggers: 0 live / 2 repo" (and the cron jobs), and passes after 0193. Gotchas found while building it: PG16 vs PG17
and CRLF checkouts differ only in whitespace (hashes are whitespace-normalised); aggregate hashes differ by collation (compared
item by item); PostGIS lives in `extensions` on live but `public` locally (extension-owned objects excluded).

**The sign-up drift (K-19, closed):** live auth.users had lost `on_auth_user_created` and `auth_users_confirm_synthetic`, most likely
in the 7 Nov move; new residents could not register or sign in on 23-24 Nov; Ace re-created both by hand 24-25 Nov (checked:
identical to 0004/0022; `watch.py`: 0 accounts without a users row, 0 unconfirmed phone addresses). **Lesson:** `supabase db dump`
(and so the nightly backup) leaves out the auth, storage and vault schemas and the cron jobs; every public-schema check (grants,
baseline, the nightly restore drill's row counts) stayed green the whole time. Draft **0193** re-creates both triggers
idempotently (drop if exists + create, one transaction; on live today it changes nothing); test `supabase/tests/77_auth_triggers.sql`
(3 checks) passes on the migrations, **fails 2 of 3 with the triggers dropped**, passes again after 0193 and after its undo.
Wired into `docs/OPERATIONS.md` (Restore steps 5-7 and "Drift check and the daily watch").

## 2. Storage rules

- **Supabase Storage is unused:** 0 buckets, 0 storage.objects policies on live (drift check). All media is on Cloudinary.
- **Upload contract (sign-upload, verify_jwt off by design):** the function picks every signed value (public id `folder/<uuid>`,
  formats jpg/png/webp or mp4, resize 1920, timestamp); folders by role (reports: resident, dispatch: tanod, avatars: any signed-in,
  ids/selfies: signed-in or, before an account exists, 10 per hour per address). ids/ and selfies/ are uploaded as Cloudinary
  `authenticated` (0117); viewing them needs a signed link that sign-upload makes only for the owner, an admin, or the user's own
  profile request. Cloudinary listing needs the API secret (function secret only). The users/profile_requests rows that hold the
  addresses are readable by the owner and admins only (policies `users_self_read`, `profile_requests_read`).
- **media-cleanup:** handles both `upload` and `authenticated` addresses; cron 03:40 with its two Vault secrets (present);
  `media_trash` is empty; last runs succeeded (watch.py).
- **FINDING K-20 (high, privacy, Ace):** **11 of 14 ID photos and 8 of 11 selfies on live are still public Cloudinary `upload`
  assets** (all accounts made 13 Aug-7 Oct, before 0117; the 3 made since are private). 0117 says "Older uploads stay public until
  scripts/privatize-identity-photos.mjs moves them"; it has not been run. Anyone holding one of those addresses can open a
  government ID without signing in. Fix: Ace runs `node scripts/privatize-identity-photos.mjs` (dry run) then `--apply` (it writes
  to Cloudinary and live, so not done here). Counted only; no address or photo was opened.

## 3. Quotas and limits

| item | live now | limit (Free plan, supabase.com/pricing, docs) | at the limit |
|---|---|---|---|
| database size | 60 MB (tables 10, indexes 14; WAL 128 MB) | 500 MB quota; 2 GB disk | quota: 402s; disk 95%: read-only |
| connections | 26 of 60 (authenticator 11, supabase_admin 11) | pooler pool 15, 200 clients | new connections wait/fail |
| cache hit (index / table) | 1.00 / 1.00 | | |
| long-running / blocking queries | 0 / 0 | | |
| Realtime | 2 subscriptions now; slots streaming, lag 0 | 200 peak connections, 2 M messages/month | refused |
| Edge Functions | 6 active | 500,000 invocations/month | could not read counts (needs the Management API's analytics) |
| Render portal (free) | warm GET: ping 0.40 s, login 0.29 s (median of 5/3) | sleeps after 15 min idle | ~50 s first request (ping.php note) |

Growth (live rows): status_logs +45 in 7 days (24,022; the 22,900 old demo repeats, S-02), notifications +269/7 d (837; purge job
on), smart_events +12/7 d, portal_uptime 144/day (4,315; no failure in 1,008 checks in 7 days; portal memory peak 80 of 512 MB),
cron history ~4,900 runs/day kept ~7 days (7 MB; purge job on), reports +7/7 d (84). At this rate the 500 MB quota is years away.
**Where the time goes** (pg_stat_statements, 18 days): the cron jobs are 74% of all database time; `_smart_snapshot_refresh`
(every minute) alone 42% (20,235 calls, 94 ms avg), `sweep_awaiting_units` 17%, `smart_watch` 11% (94 ms avg; 51 s at 250x
locally: **K-22**). 179 of 309 indexes unused so far (normal at this size; not a finding). Cold start: **could not prove** — the
keep-awake job pings every 10 min, so the instance never sleeps; measuring it would mean stopping that job (a write).

## 4. Backup restore drill — `tools/sweep/restore_drill.py`

A fresh dump of live (the CLI's own `db dump --dry-run` scripts, run with a PostgreSQL 17.11 pg_dump because the CLI's needs Docker):
roles 0.4 KB, schema 1.0 MB, data 11.3 MB, **~12 min from this PC** (pg_dump makes one round trip per function over a ~40 ms link).
Restored into a throwaway PostgreSQL 17.11 + PostGIS 3.7 with the stub of Supabase's roles/auth/vault (as CI uses): **restore 3 s,
whole proof ~2.5 min** (timings in `out/restore_drill.json`).

- **Rows:** 107/107 tables (every public table + auth.users, auth.identities, cron.job) came back with every dumped row; live
  changed in 1 table meanwhile (portal_uptime). Statements that did not apply are Supabase's own machinery (3 extensions and
  schemas a plain PostgreSQL lacks, 31 data blocks for its internal tables).
- **What a dump does not bring back** (drift check on the copy, before the post-restore steps): the **2 auth.users triggers** and
  **all 21 cron jobs**. Grants come back **open**: signed-out callers could run **415 functions instead of 19** (live's default
  privileges revoke PUBLIC, so pg_dump writes no revoke; the move to Singapore hit the same, 383). Realtime tables came back (10/10)
  because the publication existed.
- **Post-restore steps** (OPERATIONS Restore 4-5: `grants.sh apply`, 0193): then grants match all 540 objects, auth triggers pass,
  policies 167/167, functions 415/415, triggers, tables, realtime: PASS. Cron jobs stay a by-hand step at a cutover.
- **Hash chain:** `verify_report_trail` on all **84 cases, 24,022 entries: 0 broken**.
- **supabase/tests on the copy:** 394 ok, 121 failing: 10 need the cron jobs; the rest are in scripts written for an empty database
  built from the migrations (they count rows, "told once") and meet live's real rows. **Could not prove** each of those is only
  data-dependent; the same scripts pass in CI on the migrations.
- **Nightly backup** (`backup.yml`): last 12 runs all **success** (latest 25 Nov 02:41 UTC; GitHub starts the 18:30 UTC schedule
  5-10 h late). Artifact = roles.sql + schema.sql + data.sql, AES-256 gpg, kept 30 days; its own drill checks row counts and the
  live grants. It passed every night through 23-24 Nov: it cannot see auth triggers or cron jobs (**K-21**). The passphrase is not
  available to this sweep and was not sought; its archives were not opened.
- Tool fix: `supabase/tools/grants.sh` reported every line as different on Windows (psql writes CRLF); it now strips `\r`.

Restore procedure, exact: `docs/OPERATIONS.md` → Backups and restore, steps 1-7 (step 5 now lists the auth.users triggers and
realtime tables; step 7 = `drift_check.py` must end `0 FAIL`).

## 5. SMART at today's size + Singapore latency — `tools/sweep/live_timing.py`

One read-only psql session from this PC to the Singapore database (IPv6 direct), each query 7x as each test role.
**Round trip `select 1`: median 41 ms, fastest 37 ms**; random single stalls of ~250 ms (and up to 1.3 s) hit about one query in
40 — network, not database (they move between queries run to run). Database time at live size (fastest run − fastest round trip):

| ms | super | captain | Kagawad | staff | resident | tanod |
|---|---|---|---|---|---|---|
| smart_queue() | 16 | 17 | 65 | 45 | - | - |
| smart_module() | 21 | 20 | 22 | 21 | - | - |
| cases.php list / committee counts | 1 / 4 | 3 / 6 | 5 / 6 | 4 / 5 | 5 | 5 |
| notifications / users / dispatches | 3 / 2 / 2 | 3 / 2 / 3 | 6 / 7 / 8 | 4 / 4 / 5 | 3 / 4 / 2 | 1 / 1 / 3 |

So at live size a page's database time is dominated by round trips (a 42-request page ≈ 42 × 41 ms if sequential), not by the
queries. Calibration: laptop 1x smart_queue 50-104 ms vs live 16-65 ms (live ≈ 0.3-0.6x the laptop's 1x numbers).

## 6. Realtime per role — `tools/sweep/realtime_check.py`

Live: 10 published tables, all RLS on (none forced), one SELECT policy each; replica identity default except `reports` (full).
`realtime.apply_rls` on live (read): per change and per subscriber it `set_config`s role + JWT claims in the same session and runs
a prepared `select … where pk = $1` under RLS; **DELETE events skip RLS and carry only the primary key**; with RLS on, old_record
is cut to the key, so `reports`' full replica identity does not leak old values. The 0189-0191 helpers are STABLE, keyed on
`auth.uid()`, keep no session state (the `set_config` calls in 0191 are transaction-local flags inside write functions).

REALTIME_RESULT

Needs a live write to prove end to end (a change pushed to real subscribers): not done.

## 7. Daily watch — `tools/sweep/watch.py`

`python tools/sweep/watch.py` (read-only, ~4 s, exit 1 if a line is `!!`). First run 25 Nov 07:30 UTC: auth triggers 2/2, 0
sign-ups without a users row, 0 unconfirmed phone addresses, 0 portal errors and 0 mail errors in 24 h, no SMART notice/engine
errors, 21 cron jobs all last-run OK, backup 5 h old success; **!! 18 reports pending review for more than 3 days (oldest 96
days)** — test cases, most likely; Ace to judge.

## New ledger rows (round 3)

| id | severity | status | gap |
|---|---|---|---|
| K-19 | critical | fixed live 24-25 Nov (Ace) | the sign-up drift (above) |
| K-20 | high | open (Ace) | 11 ID photos + 8 selfies still public on Cloudinary (pre-0117); run the privatize script |
| K-21 | medium | open (decision) | the nightly restore drill checks only row counts: add `drift_check.py --local` after its restore (+ 0193 and `grants.sh apply`) so a lost trigger or open grants fail the night |
| K-22 | medium | open (decision) | smart_watch 0.4 s → 9.6 s → 51 s at 1x/50x/250x (every 5 min); `_smart_snapshot_refresh` every minute = 42% of live DB time |
| K-23 | medium | open (decision) | super/captain cases.php committee-tab counts scan reports through the `case_committee()` computed column: 3.2 s per load at 250x (live ~4 ms) |
| K-24 | low | fixed in this PR | grants.sh false failure on Windows (CRLF); probe_db.sh skipped the probers when its dump was clean |
| K-25 | info | accepted (Supabase design) | realtime DELETE events reach every subscriber of the table with the primary key only |
