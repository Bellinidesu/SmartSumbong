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
  Ace's word and a second pair of eyes. **Ace picked B on 20 Nov; drafted as `supabase/drafts/0189_case_rule_at_scale.sql`** (see "Drafted" below).
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

## Drafted 20 Nov 2026 (Ace chose B): `supabase/drafts/0189_case_rule_at_scale.sql`, not applied

**What it is**: 7 small helpers read the caller's facts once per query (`_my_committee`, `_my_categories`, `_my_concern_case_ids`, `_my_handled_case_ids`) and the
case set for the rows hanging off a case (`_my_scoped_case_ids`, `_my_scoped_dispatch_ids`, `_my_scoped_resident_ids`); 22 read policies are rewritten with
`ALTER POLICY` (reports written out on the row; the other 21, users included, as `report_id in (select _my_scoped_case_ids())`). `_user_sees_case` and the per-case functions stay
unchanged: guards, notices and the queue still use them one case at a time. The two INSERT checks are untouched. Undo: `supabase/drafts/0189_undo.sql`
(generated by `tools/sweep/gen_0189_undo.py` from a copy whose 167 policies equal live; restores the 22 policies word for word and drops the helpers).

**Proof** (all on throwaway copies built from migrations 0001-0188; live read only to confirm its policies and rule functions equal the copy):
- **Every (person, row) pair**: `tools/sweep/equiv_case_rule.py fixture`: 28 people (every rung; suspended and retired Kagawad, staff, super; a captain suspended;
  a Kagawad of a switched-off committee and one with none; staff with no committee; a super with no tier; residents incl. a suspended one; 3 tanods; a signed-in
  caller with no account) x the full product of what the rule reads (3 categories incl. one no active committee owns x committee none / A / B / switched-off x
  waiting for placement x 5 handlers x 3 assignments x earlier hands taken / only assigned-declined-released x a concern in another committee's category x deleted;
  5,616 cases) with rows in all 20 tables hanging off a case. **3,912,272 (person, row) pairs; 385,136 rows visible before; symmetric difference 0 after 0189 and 0 after the undo, in every one of the 22 tables**; the case set per person (`_my_scoped_case_ids()` vs `admin_scoped() and admin_sees_report(id)`) 10,098 pairs, 0 differences; after the undo every policy text equals the pristine copy and no helper is left. Reading every table as all 28 people: 1,068 s with the old policies, 32 s with 0189.
- **pgTAP**: all 66 scripts (`supabase/tests/01-67`) give identical results before and after 0189 (493 ok; the one FAIL, 04 "night", fails on both: it depends on the
  hour the suite runs). New 67 passes on both rules and FAILS on each of 5 deliberately broken variants (`equiv_case_rule.py broken`); draft test 68 (in
  `supabase/drafts/tests/`) fails before 0189 and passes after.
- **Probers**: `probe.py` (227 functions x 11 actors x 11 states x 3 variants = 37,642 probes): 37,642 identical before/after (16 probes that hit a parallel-run
  deadlock in either run were re-run one function at a time: identical).
- **Every replayed page request**: `loadcost.py --compare 1,50,250` replays the 2,422 captured portal and app requests as each rung through PostgREST before and
  after 0189 at each scale; every GET answered by both gives the same rows (order-free digest): see the timing table.

**Old behaviour kept identical on purpose in 0189 (items 1-4 were fixed by 0191, applied live 21 Nov; item 5 was fixed in 0189)**:
1. The rows hanging off a **deleted** case (status logs, notices, messages, media, dispatches...) stay readable to the Kagawad/staff who could read the case:
   `admin_sees_report` never looked at `deleted_at` (only `reports` itself hides deleted cases).
2. `_user_sees_case` reads the rung from `users` without the retired check that `admin_tier()` has, so a **retired** (not suspended) Kagawad or staff member still
   passes `_notifications_scope` (notices of their old cases are written to them) and, since `admin_scoped()` is false for them, reads every notice they own.
3. The committee branch does not check that the Kagawad's committee is switched on (cases forwarded to a switched-off committee stay visible to its Kagawad),
   while the category branch does.
4. A case **waiting for placement** is hidden from every Kagawad, even the one handling it, but visible to the staff member assigned to it (the staff branch comes
   before the waiting check).
5. Performance only (now fixed, no visibility change): for residents and tanods the gate `(select admin_tier()) = any(...)` was NULL, not false, so the per-row
   function still ran on every row they scanned (the 7.4 s resident map at 250x).

**Rollout** (when Ace says "apply 0189"): one transaction (`supabase db push` runs the file as one; by hand: `psql -1 -f`). `CREATE FUNCTION` takes no table lock.
Each `ALTER POLICY` takes an ACCESS EXCLUSIVE lock on its table (22 tables) until COMMIT; on 82 cases the whole file runs in well under a second, but a long
query holding any of those tables makes it wait, and reads queue behind it: `lock_timeout = 5s` makes it give up and roll back instead. Apply at a quiet
moment. Afterwards (read-only on live): `pg_policies` shows the new texts, the 7 helpers exist, and the Kagawad/staff case counts on the portal are unchanged;
tests 67 and 68 run on the rebuilt baseline in CI (they roll back). Every rewritten policy is equivalent on its own, so even a partial apply
would not change who sees what (helpers are created first).
**Undo**: `psql -1 -f supabase/drafts/0189_undo.sql` (restores the 22 policies word for word, then drops the helpers; dropping fails if any policy still uses
one, which is the safety check). Tested: apply then undo on the fixture copy gives identical rows for every person and identical policy texts.

**Timings** (laptop PostgreSQL 16 + PostgREST, ms of database time, sum of every request a page makes, replayed as the real rung; `loadcost.py --compare`, then
`--new-only 250` for the final draft; 1x/50x "after" were measured with the first draft, which differs only in being slightly slower):

| page / rung | 1x before -> after | 50x | 250x | 250x after, without the SMART RPCs and `case_committee` |
|---|---|---|---|---|
| cases.php / Kagawad | 683 -> 141 | 19,915 -> 902 | 96,675 -> 3,809 | 398 |
| case.php / Kagawad | 337 -> 187 | 8,782 -> 192 | 44,168 -> 315 | 309 |
| home.php (and 10 more pages) / Kagawad | 431 -> 148 | 12,469 -> 860 | 59,832 -> 3,703 | 304 |
| personnel.php / Kagawad | 388 -> 109 | 12,186 -> 162 | 61,793 -> 275 | 275 |
| cases.php / staff | 391 -> 92 | 10,882 -> 170 | 50,745 -> 449 | 143 |
| case.php / staff | 238 -> 106 | 4,770 -> 123 | 22,898 -> 134 | 129 |
| resident app | 25 -> 11 | 837 -> 14 | 4,312 -> 18 | 18 |
| tanod app | 51 -> 9 | 2,442 -> 20 | 3,055 -> 39 | 39 |
| cases.php / super, captain (not on the case rule) | 137 / 75 -> 91 / 78 | ~700 -> ~630 | 2,726 / 2,689 -> 2,688 / 2,636 | 115 / 108 |

All replayed requests at 250x: 1,995 s -> 70 s of database time. Single queries (`time_0189.py`, warm connection) at 250x, Kagawad: `count(*)` of reports
14,634 -> 18 ms, status_logs count 52,205 -> 28 ms, pending residents 2,455 -> 32 ms; staff 7,161 -> 7 ms. **Still over 200 ms at 250x, and why**: the SMART RPCs
(`smart_module` 3.4 s for a Kagawad: it calls `_user_sees_case` per open case inside the function; the one-line fix is `r.id in (select s.id from
public._my_scoped_case_ids() s(id))`, a separate draft), `case_committee` computed per row on the super/captain cases page (0.5 s, not the case rule), and pages
that add up ~37 requests of 5-60 ms each (Kagawad pages 275-400 ms without SMART). **Got slower**: a one-row read of a table hanging off a case (what Realtime
runs per subscriber per change, and the case page's `status_logs?report_id=eq.X`) builds the caller's case set: Kagawad at 20,000 cases 1.5 -> 19 ms, staff ~2 ms;
at today's 82 cases 1.5 -> 2.8 ms. Cheaper per-row checks (a security-definer view the planner can inline) are possible later if Realtime volume needs it.
