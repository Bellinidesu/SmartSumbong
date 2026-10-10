# Database checks

Three scripts that walk the whole system through the real database, as each
role (resident, second resident, tanod, admin), and then **roll everything
back** — they end by raising `SWEEP-ROLLBACK`, so nothing they do is saved.

| File | What it covers |
|---|---|
| `01_lifecycle.sql` | 102 checks: filing, review, dispatch, tanod updates, resolution and approval, ratings, reopening, escalation, appeals, cancelling, overdue follow-ups, deadline extensions, hand-ups, row-level security for every role |
| `02_handlers_requests_accounts.sql` | 24 checks: case handlers and take-over, name/ID requests, new admins, account deletion, trail integrity, the keep-awake job |
| `03_hardening.sql` | 44 checks (0114–0120): login lockout and its per-address limit, SMS code tries, cron-only sweeps, the daily filing limit, upload signing limits, private identity photos and their cleanup, notification retention, sign-out on reset/suspension, health alerts, pausing filing, tracking IDs past 9,999 |
| `04_smart.sql` | 17 checks (0121–0122, docs/SMART.md): triage scores and reasons (kind, words, whole-word matching, hazard zones, nearby reports, night, word cap), possible duplicates, residents kept out, rules changed and re-scored, a broken rule never blocks filing, tanod ranking, resolution-time estimate |
| `05_smart_engine.sql` | 14 checks (0123): admin overrides (reason required, kept through re-scoring, logged, cleared), the watcher (urgent reports without a tanod, told once; dispatched ones not), recurring problems (three weeks yes, one burst no, told once), residents kept out, the schedule, calibration |
| `06_smart_screens.sql` | 7 checks (0124): Try it scores without saving, the category hint (and when it stays quiet), the case card (both levels, override, reasons, estimate, duplicates, top tanod), the dashboard tiles, residents kept out |

`perf/query_budget.sql` fills the database with a busy barangay's few
years (2,000 residents, 50,000 complaints, 100,000 notifications) and times
the queries the app and portal run most, as the role that runs them; each
must stay within its budget (CI fails otherwise). Its first run found
tracking IDs breaking at the 10,000th complaint (fixed in 0120).

Regenerate after editing the generators: `python gen_lifecycle.py && python gen_handlers.py && python gen_hardening.py`.

CI runs them locally (see below) on every push, and against a staging
project after a merge when one is configured (`.github/scripts/db-checks.sh`,
which refuses production).
Every line of the raised message must start with `ok`; CI fails on any `FAIL` or `BAD`.

## Locally, without the live project

`bash supabase/tests/local/run-local.sh` builds a throwaway PostgreSQL (16 by
default; `PGVER=17` matches Supabase, as CI does)
(PostGIS and pg_cron), adds the parts of Supabase the migrations rely on
(`local/supabase_stub.sql`: the `auth` schema, API roles, a no-op `net`),
applies every migration in order and runs these checks. Needs
`postgresql-NN postgresql-NN-postgis-3 postgresql-NN-cron` for that version. `KEEP_DB=1`
leaves the database running for poking at.
