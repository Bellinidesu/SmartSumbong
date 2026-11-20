# B-dead-code: functions, tables and kinds nothing uses (one decision per group; nothing applied)

Evidence: `tools/sweep/callgraph.py` (every function in grants.txt against all callers) and detector D2.

- **28 API-callable functions have no caller of any kind.** Groups: the Inbox suite (`send_mail`, `mail_*`, `mark_mail_read`, `mail_recipients`: the backend exists, no screen), SMART screens
  not built (`smart_read`, `smart_duplicates`, `smart_similar_cases`, `smart_verify`, `smart_verify_queue`), case actions with no button (`reopen_report`, `release_case`,
  `answer_reroute_question`, `set_report_deadline` is a dead trigger function), admin tools (`reset_admin_password`, `places_status`, `assignable_tanods`, `audit_integrity`,
  `command_suggest`, `assert_not_client`, `admin_sees_category`).
- 3 tables are written and never read: `mail_state`, `smart_overrides`, `tanod_committee_log`.

| Option | What changes | Cost | Per role |
|---|---|---|---|
| 1. Wire a screen (when the page is built) | nothing in the database | a front-end change (class C) | the role the function is gated to gets the feature |
| 2. Revoke the right now, grant again when a screen exists | one migration of `revoke`s (generator: `fix/gen_revoke_unused.py` extended) | trivial, reversible | nobody loses anything today (nobody calls them) |
| 3. Drop the function/table | migration + data loss for the tables | cheap, not reversible | none today |

**Recommended**: 2 for functions parked on purpose (Inbox, SMART screens), 1 for `reopen_report` (see K-01), 3 only after the barangay confirms a feature is dead.
Retention: `status_logs` is 95% one historic burst (22,910 rows, 7 cases); it is append-only by design, so nothing to prune, but cap new system remarks like 0139 did.
