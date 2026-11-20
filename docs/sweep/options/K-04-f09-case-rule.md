# K-04 / F09: the Kagawad and staff case rule at scale (options with timings; nothing applied)

**The problem**: `reports_resident_read` calls `admin_sees_case` -> `_user_sees_case` once per row; each call re-reads the case and the user (security definer, several lookups).
A Kagawad's `select count(*) from reports` over 20,000 cases is **15 s**, staff **7 s**; every portal page runs several such queries. Live data matters: **80 of 82 live cases have
`committee` null** (only forwarded cases get one), so the slow branch is the category branch (`_user_sees_category` + concerns), not the committee branch.

**How measured**: `tools/sweep/exp_case_rule.py`. Throwaway copy of the 250x database; each option built in place, queried as the real role (RLS on) and torn down;
the copy is shrunk to 4,000 (50x) and 82 (1x) cases. Every option was first checked to show **exactly the same cases** as today (count and id hash) for a Kagawad and a staff
member at 250x. Laptop PostgreSQL: read the ratios. Milliseconds of database time:

| Option | Kagawad count / list / pending (250x) | staff count / list / pending (250x) | 50x Kagawad count | 1x Kagawad count | Same cases | One-off cost |
|---|---|---|---|---|---|---|
| A today (per-row function) | 15,082 / 89 / 9,236 | 7,268 / 178 / 4,492 | 3,006 | 97 | yes | none |
| B inline policy, caller facts read once per query | **38 / 23 / 31** | **19 / 8 / 14** | 32 | 31 | yes | none (a policy and 3 helpers) |
| C materialised visibility table (user, case) kept by triggers | 21 / 9 / 16 | 19 / 8 / 14 | 15 | 14 | yes | 25 s to build at 250x, plus trigger maintenance |
| D partial indexes only | 14,409 / 90 / 8,875 | 7,519 / 183 / 4,559 | 3,108 | 93 | yes | 0.2 s |
| E B + the partial indexes | 38 / 25 / 33 | 19 / 8 / 14 | 34 | 28 | yes | 0.3 s |

## Options, what each changes, per role

- **B (recommended)**: replace the policy's per-row call with set-based facts read once per query (`_my_committee()`, `_my_categories()`, `_my_concern_reports()` as stable
  security-definer helpers, and `admin_tier()`/`is_full_viewer()` already are). Kagawad and staff pages go from seconds to tens of milliseconds at 250x, and are *faster than today at 1x*
  too (97 -> 31 ms). Super/captain/resident/tanod: unchanged results (they short-circuit before the helpers). Cost: one migration rewriting one policy + 3 small functions + the
  existing pgTAP checks (26, 53, 57, 58) re-run as the equivalence proof; risk is low because the id set is proven identical, but it is the **core visibility rule**, so it needs
  Ace's word and a second pair of eyes. Not drafted into `supabase/drafts` for that reason; the exact SQL is in `exp_case_rule.py` (option B).
- **C materialised table**: as fast, but every change of a case's committee/handler/assignment/category, of a user's committee/role/suspension, of a handler-log row and of a concern
  must update `case_visibility` (4 triggers + backfill), and a missed trigger silently hides or leaks a case. More moving parts for no gain over B at this size. Keep for when the
  rule gets too complex for a policy expression (e.g. per-case sharing lists).
- **D indexes only**: no effect (the cost is the per-row function, not the scan). Do not bother.
- **A (do nothing)**: fine at today's 82 cases (97 ms), unusable around 4,000 (3 s per query, several per page) and not at 20,000.

## Still to do under any option (not measured here)

The same per-row pattern sits in the policies of the tables a case page and the lists read: `users` (the Kagawad's pending-residents count was 71 ms -> **8.9 s** at 250x),
`dispatches` embedded in lists (86 ms -> 24 s), `status_logs`, `report_concerns`, and the resident public-map read (`is_public`, 10 ms -> 7.4 s as a resident). Each needs the same
treatment, and recursion between policies (a child policy asking `reports`, whose policy asks the child) must be avoided with a security-definer set helper, as B does
for concerns (the first attempt at B hit "infinite recursion detected in policy" and was fixed that way).

## Decision for Ace

Pick B (and say 'apply' for the reports policy first; the child tables follow the same recipe, one migration each), or C if you want the visibility to be queryable data.
