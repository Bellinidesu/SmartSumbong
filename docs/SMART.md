# SMART: how SmartSumbong decides what is urgent

SMART is rule-based, not AI. It follows fixed rules that the barangay can
read and change, and every result lists the reasons behind it. Nothing
learns or changes on its own. The rules live in one database row
(`smart_rules`); the code is `supabase/migrations/0122_smart_triage.sql`.

Status (10 Oct 2026): database only (migrations 0121–0123), tested, not
deployed, and not shown in the portal or the app yet.

## 1. Triage: a score from 0 to 100 for every report

Each new report is scored as soon as it is filed. Its open neighbours are
scored again too, since a new report can back them up. The score is the sum
of the points below, capped at 100.

| Factor | Points | Example reason shown |
|---|---|---|
| Kind of complaint | public safety 35, peace and order 30, environment and waste 25, traffic 20, obstruction 20, animals 15, barangay service 10, other 10 | `category: public_safety_infrastructure +35` |
| Words in the subject or description (English and Tagalog), each group once, 45 at most | fire, weapon, injury, gas leak 30; live wire, collapse, accident 25; fight 20; flooding 15; child, elderly, pregnant or PWD 10 | `words: fire ("sunog") +30` |
| Inside a NOAH hazard zone | level 1 +5, level 2 +10, level 3 +15 | `hazard zone: NOAH flood zone, high +15` |
| Other residents reporting the same kind within 150 m and 48 h | +8 each, 24 at most | `nearby reports: 2 other residents reported this within 150 m +16` |
| Filed between 22:00 and 05:00 (safety kinds only) | +5 | `night: filed at 23:00 +5` |

The score sets the level: **urgent** from 70, **high** from 45, **normal**
from 25, otherwise **low**.

Two examples:
- "May sunog sa likod ng bahay, may bata sa loob" (public safety, dry area):
  35 + fire 30 + child 10 = **75, urgent**. Note that "bahay" (house) does
  not count as "baha" (flood): the rules match whole words.
- "Barado ang kanal" (environment) in a high flood zone: 25 + 15 = **40, normal**.

If a rule is ever broken (a mistyped word pattern, for example), the report
is still filed, just not scored. Scoring can never stop a resident from
filing.

## 2. Possible duplicates

These are earlier open reports of the same kind, filed within 100 m and
72 hours, that are either worded alike (text similarity of 0.3 or more,
using PostgreSQL's `pg_trgm`) or within 25 m of each other. The admin sees
up to five, each with distance, hours apart and similarity, and decides
whether they are the same problem. Nothing is merged automatically.

## 3. Which tanod to send

The candidates are the tanods who can take the report, the same list the
portal uses now (`nearest_available_tanod`). Each one starts at 100 points:

- minus 1 for every 20 m of distance (50 at most);
- minus 15 for each job already in hand;
- plus 5 for each case they closed within 300 m in the last 90 days (20 at most);
- minus 10 if their last location reading is older than the barangay's
  freshness setting (15 minutes).

There is no tracking: live tracking was removed at the barangay's request
(0072). The app sends one reading when a tanod goes on duty, opens the app
or takes a dispatch step, and the ranking shows how old it is ("last
reading 6 min ago").

The admin sees the ranking with the four reasons and still chooses.

## 4. How long it usually takes

This is the median and the 80th percentile of the time this barangay took
to resolve the same kind of complaint over the last 180 days. With fewer
than 5 closed cases it shows the SLA target instead and says so. Only
totals are shown, so residents can see it for their own report.

## 5. Admins have the last word

An admin can raise or lower any report's level (`smart_override`) and must
give a reason. The computed score stays visible beside the override, and
re-scoring never undoes it. Every override, including clearing one, is kept
(`smart_overrides`) with the score and reasons of that moment. That record
is what calibration (section 8) reads.

## 6. Recurring problems

These are places where the same kind of problem keeps coming back: at
least 3 reports of one kind within 60 m of each other, filed in at least 2
different weeks, over the last 90 days. Three reports in one afternoon are
one event, not a pattern. Each recurring problem shows how many reports
and residents, how many weeks, how many are still open, whether it is in a
hazard zone, and the latest tracking IDs. A recurring blocked canal in a
flood zone, for example, is a case for a permanent fix rather than another
clean-up.

## 7. The watcher

Every 5 minutes, `smart_watch()` tells the admins, once each, about:
- an **urgent** report with no tanod after 15 minutes, or a **high** one
  after 60 minutes (a notification that opens the case);
- a recurring problem it has not seen before.

## 8. Checking the rules (calibration)

- `smart_calibration(days)` shows, for each computed level, how many
  reports it covered, how many admins raised or lowered, and the median
  time to the first dispatch and to resolution.
- `smart_factor_stats(days)` shows the same for each factor: each kind, each
  word group, hazard zones, nearby reports and night.

If a factor keeps turning up in reports that admins lower, it is worth too
many points; if it keeps turning up in reports they raise, too few. People
change the rule, not the engine.

## Changing the rules

An admin edits `smart_rules`: points, word lists, radii, cut-offs,
duplicate and recurring-problem settings, and the watcher's minutes. Then `select smart_retriage();` scores every open
report again. Residents cannot read scores or change rules; tanods see
nothing new.

## Speed

Tested on 50,000 reports packed into half a square kilometre, much denser
than the barangay really is:

| Action | Time |
|---|---|
| Filing a report, scoring included | 36 ms |
| Urgent and high queue, top 50 | 0.4 ms |
| Possible duplicates | 6 ms |
| Recurring problems, 90 days (the watcher's main step) | 50 ms |
| Calibration, 90 days | 8 ms |

These times are checked against budgets in `supabase/tests/perf/query_budget.sql`.

## Functions

| Function | Who | Returns |
|---|---|---|
| `report_triage` (table) | admins read | score, level, reasons, possible-duplicate count |
| `smart_duplicates(report)` | admins | up to 5 earlier reports |
| `smart_tanod_ranking(report)` | admins | tanods, score, reasons |
| `smart_eta(category)` | signed-in users | median and 80th-percentile hours, case count, basis |
| `smart_retriage(report or null)` | admins | how many were scored |
| `smart_override(report, level or null, reason)` | admins | the triage row |
| `smart_overrides` (table) | admins read | every override |
| `smart_patterns(days)` | admins | recurring problems |
| `smart_calibration(days)`, `smart_factor_stats(days)` | admins | how the rules compare with people's judgement |
| `smart_watch()` | pg_cron, every 5 minutes | messages sent |
| `smart_rules` (table) | admins read and update | the rules |

The hazard zones (`hazard_zones`, from `admin/assets/map/hazards.geojson`)
are generated by `supabase/tools/gen_hazard_zones.sh`.
