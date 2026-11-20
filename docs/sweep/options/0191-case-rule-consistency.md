# 0191 case_rule_consistency (applied live 21 Nov): the four old behaviours of the case rule

Ace, 21 Nov: "do the recommendation". One migration, `supabase/migrations/0191_case_rule_consistency.sql` (undo: `supabase/drafts/0191_undo.sql`, tested; test `supabase/tests/71_case_rule_consistency.sql`;
updated test `supabase/tests/67_case_rule_equivalence.sql`). The per-case function and the 0189 set helpers move together.

| # | Change | Where |
|---|---|---|
| 1 | Rows hanging off a soft-deleted case are hidden from Kagawad and staff (all tables the 0189 set covers); super admins and captain keep them | `_user_sees_case`, `_my_scoped_case_ids`, `_my_concern_case_ids`, `_my_handled_case_ids` |
| 2 | A retired admin sees nothing as an admin in the rule; case notices addressed to a retired admin are dropped (a notice with no case, e.g. their own retirement, still arrives) | `_user_sees_case`, `_notifications_scope` (0188) |
| 3 | The committee branch needs the committee switched on; a case can no longer be placed with a switched-off committee by assigning it | `_user_sees_case`, `_my_committee`, `assign_case` |
| 4 | The case's own handler keeps seeing it while it awaits placement; other Kagawads still do not | `_user_sees_case`, `_my_scoped_case_ids`, `reports_resident_read` |

## Proof (tools/sweep/equiv_0191.py: exhaustive fixture, 28 people x 5,616 cases x 22 tables, old / new / undo snapshots under row level security)

The expected differences are written as explicit predicates (from the four items, not from the new code); any difference that matches none is a failure, and every pair an item says must change is checked to have changed.

| Item | Per-case function (person, case) pairs | Rows read in the 22 tables | Stored case notices (probe) |
|---|---|---|---|
| 1 deleted | 5,595 lost | 46,344 lost (reports: 0, a deleted case was never in `reports`) | part of 1,592 lost |
| 2 retired | 1,248 lost | 0 (the policies already hid everything from a retired admin: `admin_tier()` is null for them; only the function and the notices differed) | part of the 1,592 |
| 3 committee off | 351 lost | 4,999 lost (reports: 351) | part of the 1,592 |
| 4 awaiting + handler | 1,296 gained | 9,109 gained (reports: 648) | 87 gained |
| anything else | **0 unexpected, 0 expected-but-missing** | **0 unexpected in every table** | **0 unexplained** |

Lockstep after 0191: the set helper `_my_scoped_case_ids()` equals the per-case function for every active Kagawad and staff member (0 / 0 differences). The undo gives snapshots identical to today's (0 differences).
pgTAP: 69 scripts before/after the draft: identical except 67 (its named expectations encode items 1 and 4; the updated copy passes after 0191) and 71 (fails before, passes after);
`04_smart` "night" fails before and after (a time-of-day check, unrelated). Prober (probe.py, 37,642 probes before/after): 37,637 identical; 5 differ only where the fixture
itself failed to build in one of the two runs (fixture errors come and go: 3 on 20 Nov too); 0 behaviour differences.

## forward_case and the other paths that set `reports.committee`
- `forward_case`: already refuses a committee that is not switched on (`No such committee`). `flag_case_for_forward`: same check. No change needed.
- `assign_case` (a super admin giving a case to staff or a Kagawad of ANOTHER committee places the case with that committee, `committee = a.committee`) had no such check: a case could be placed with a
  switched-off committee. Fixed in 0191 with a clear error (`That committee is switched off; choose someone of an active committee`). These are the only two functions that set `reports.committee`.
- Not blocked, by design: switching a committee off while it still holds cases. Under item 3 its Kagawad then stops seeing those cases (super admins still do). Live has 0 cases in the 7 switched-off committees.

## Timing (must not regress vs 0189/0190: 1x / 50x / 250x, database time as the real role, 18 page queries x 5 roles)
Single pass: 282 vs 267 ms total at 1x, 523 vs 471 at 50x, 897 vs 855 at 250x. Three alternating rounds at 250x (median): Kagawad 470 -> 461 ms (-2%), staff 112 -> 141, super 110 -> 136 and
resident 87 -> 102 (these two do not use the helpers at all): the +-25% on small totals is measurement noise, no systematic regression for the roles the draft touches.

## Risks
1. Deleted cases: a Kagawad or staff member can no longer read the audit rows of a deleted case (the intended change); supers and captain still can.
2. Item 3 hides a switched-off committee's existing cases from its own Kagawad (intended; none today).
3. Item 4 also lets that handler pass the guards on their own awaiting case (they handle it).
4. `assign_case` is rewritten as a whole function (one added check); `_user_sees_case` and the helpers are replaced by `create or replace`; `reports_resident_read` by `alter policy` (one lock, 5 s timeout).
5. Retired admins lose case notices only; their notices with no case still arrive.

## Undo
`supabase/drafts/0191_undo.sql` restores `_user_sees_case`, `_my_committee`, `_my_concern_case_ids`, `_my_handled_case_ids`, `_my_scoped_case_ids`, `reports_resident_read`, `_notifications_scope` and
`assign_case` word for word (tested: apply, undo, every definition and the policy text identical to before). No data is changed by 0191 or by the undo.
