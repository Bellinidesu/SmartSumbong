# B-state-machine: statuses with no way in or out (decision, then scripted)

Evidence: `tools/sweep/probe.py` drove every function as every role against fixtures in every state (docs/sweep/BACKEND_SWEEP_2_BASELINE.md has the matrix).

- `report_status 'archived'`: no function by any role moves a case into it or out of it (unreachable and dead end).
- `report_status 'cancelled'`: only the owner can enter it, nobody can leave it (by design: a cancelled report stays cancelled).
- `report_status 'assigned'`: reached only by `finalize_retirement` (a tanod's retirement hands their case back) by super; no case enters it through dispatch any more.
- `ocr rescan` request has no decision path (the admin requests a re-check of a resident's ID; the re-reading is the resident's next upload).

| Option | Meaning | Cost |
|---|---|---|
| 1. Keep as documented dead values | write it in docs/schema.md | none |
| 2. Remove the unused enum values | migration on `report_status` (enum values cannot be dropped simply: recreate type) | medium, risky |
| 3. Give them a path (e.g. archive after N days of closed, cancelled -> reopenable by the owner within 24 h) | new function + cron + tests; product decision | medium |

**Recommended**: 1 for `cancelled`, 3 for `archived` only if the barangay wants an archive; else 1.
