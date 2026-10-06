# Database checks

Two scripts that walk the whole system through the real database, as each
role (resident, second resident, tanod, admin), and then **roll everything
back** — they end by raising `SWEEP-ROLLBACK`, so nothing they do is saved.

| File | What it covers |
|---|---|
| `01_lifecycle.sql` | 102 checks: filing, review, dispatch, tanod updates, resolution and approval, ratings, reopening, escalation, appeals, cancelling, overdue follow-ups, deadline extensions, hand-ups, row-level security for every role |
| `02_handlers_requests_accounts.sql` | 24 checks: case handlers and take-over, name/ID requests, new admins, account deletion, trail integrity, the keep-awake job |

Regenerate after editing the generators: `python gen_lifecycle.py && python gen_handlers.py`.

Run against the linked project: `supabase db query --linked -f supabase/tests/01_lifecycle.sql`.
Every line of the raised message must start with `ok`; CI fails on any `FAIL` or `BAD`.
