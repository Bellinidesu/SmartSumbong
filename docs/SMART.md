# SMART: how SmartSumbong decides what is urgent

SMART is rule-based, not AI. It follows fixed rules that the barangay can
read and change, and every result lists the reasons behind it. Nothing
learns or changes on its own. The rules live in one database row
(`smart_rules`); the code is `supabase/migrations/0122_smart_triage.sql`.

Status (10 Oct 2026): database only (migrations 0121–0129), tested, not
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

### Reading the words (0125)

SMART reads complaints the way residents write them, using Tagalog grammar
and a word list, not a model. Each word goes through these steps:

1. **Known word**: it is in the rules' word lists.
2. **Word list** (`smart_lexicon`, admins edit it):
   - a texting spelling: snog → sunog, kuryinte → kuryente;
   - the same meaning: garbage → basura, drainage → kanal, fire → sunog;
   - a form the grammar steps miss: nangangagat → kagat.
3. **Grammar**: prefixes (na-, nag-, ma-, naka-…), the infixes -um- and
   -in-, the suffixes -an and -in, a repeated first syllable, and the
   linker -ng are taken off. The result only counts if it is a known word:
   nasusunog → sunog, binaha → baha, sinaksak → saksak, duguan → dugo,
   batang → bata.
4. **Guess**: one letter away from exactly one known word of five letters
   or more (kurynte → kuryente). If two words are that close, nothing is
   guessed.

**Negation.** walang, wala, hindi, di, huwag, no, not, never and without
cancel the next two words (ignoring little words like na, ng, po, ang).
They stop at a comma or full stop and at pero / but. "Walang sunog,
nag-iihaw lang" is not counted as a fire; "Hindi sunog, pero may usok na
makapal" still counts the smoke. A cancelled word shows in the reasons as
"not counted".

**Phrases.** A rule word with a space ("live wire", "walang helmet") is
matched as written, so a negation word inside it is part of the phrase.

**Limits.** SMART does not understand sentences. "Usok lang galing sa
ihawan" (just smoke from a grill) still counts the smoke. That is why the
reasons are shown and admins can change the level.

The reasons say how each word was read: "nasusunog → sunog (grammar)",
"snog → sunog (spelling)". `smart_read(text)` shows the whole reading,
word by word, for Settings → SMART → Try it.

## 2. Possible duplicates

These are earlier open reports of the same kind, filed within 100 m and
72 hours, that are either worded alike (text similarity of 0.3 or more,
using PostgreSQL's `pg_trgm`) or within 25 m of each other. "Worded alike"
compares the words as written and also the words as SMART reads them
(0125), so "garbage sa drainage" and "basura sa imburnal" are found as the
same problem. The admin sees
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

## 9. Category hint

Sometimes a resident picks the wrong kind of complaint. Each kind has a
list of words (`smart_rules.category_words`). When none of the chosen
kind's words appear but another kind's do, SMART suggests that kind and
shows the words: "counterflow" and "tricycle", filed as Other, suggest
Traffic violation. It is a suggestion on the case card; the admin changes
the kind, and the score is not affected.

## 10. SMART Verify: ID checks (0126)

The line SMART draws for OCR is that a model may read, but rules decide.

- **Reading (on the phone).** When the barangay turns ID reading back on
  (`ID_OCR_ENABLED`, `kIdOcrEnabled`; off since Rose, 27–30 Sep 2026), the
  app reads the ID photo with Google ML Kit on the phone. That is offline
  and free, and the photo does not leave the phone for it. The app sends
  only what it read: the ID type it recognised, the name and the number.
- **Deciding (on the server).** `submit_id_reading` stores the reading and
  works out the checks itself:

| Check | Result |
|---|---|
| The card reads like the ID type chosen | ok, or **check** if not |
| Name on the ID covers the registered name: every surname word and one given-name word, exact or one letter off, with OCR's digit-for-letter slips fixed (CRU2 is read as CRUZ) | ok; **check** if partly; **problem** if none of it |
| ID number shape for the type: PhilSys 16 digits, LTO licence one letter and ten digits, passport P1234567A or EB1234567 | ok, or **check**; other ID types have no fixed shape to check |
| The same ID number on another account | **problem**, naming that account |
| Nothing could be read | **check** |

Each account gets a level: **problem**, **check**, **ready**, or **no
reading**. The admin sees the reasons beside the photo.

**Why the server.** Before 0126 the app worked out the flags itself and
wrote them to the account, so a modified app could look "clean". Now only
`submit_id_reading` can change the reading, and the server computes the
flags. The phone could still misreport what it read, so **a reading never
verifies anyone**: the admin always looks at the ID photo, and "ready"
only means nothing looked wrong.

Real government verification (PSA, LTO) is not available for free (see
0039), and SMART does not claim it.

## 11. Storm mode (0127)

This is one switch for a typhoon signal or heavy-rainfall warning. An
admin turns it on with a reason ("PAGASA orange rainfall warning") for a
number of hours (24 by default, a week at most). While it is on, hazard
zone points and the flooding, live-wire and collapse words count double
(`storm_multiplier`, `storm_labels`), and the word cap rises with them.
Every open report is scored again when it starts and when it ends, and
the admins are told both times. It ends on its own when its hours are
up. A flood report in a high flood zone goes from 55 (high) to 85
(urgent).

## 12. Deadline risk (0127)

These are cases with a deadline that will probably miss it, flagged
before it happens:

- **High:** even a typical case of this kind here would not finish in the
  time left.
- **Medium:** a slow one would not (80th percentile), or the tanod has 3
  or more jobs in hand.

The typical and slow times come from section 4 (the barangay's own closed
cases, or the SLA target). The watcher tells the admins once about each
high-risk case: "BRG-2026-0412 will probably miss its deadline (5 h left;
such cases usually take 48 h)."

## 13. Spikes (0127)

A spike is a kind of complaint well above its usual week: at least 4 in
the last 7 days, at least double the weekly average of the 8 weeks
before, and at least 3 standard deviations above it (Poisson). The most
common place label is given for context: "6 animal welfare reports in
the last 7 days, 12 times the usual week; mostly Purok 3." The admins are
told once per kind per week.

## 14. Similar past cases and the usual office (0127)

The case card shows up to 3 finished cases of the same kind from the last
year that are most like this one: the same words as SMART reads them, or
close by. Each shows how it ended: the outside office it went to, the
closing remark, the tanod's field report, and the days it took. If one
office took at least 3 of this kind and at least 40% of those referred,
the card says so: "Usually referred to City Veterinary Office (3 of 3
referred cases this year)." This is the barangay's own memory, read back
to it; nothing is invented.

## 15. Morning digest (0127)

One message to the admins at 07:00 (Manila). It says what is open,
waiting for a tanod (urgent and high), overdue, due today, likely to miss
its deadline, filed yesterday and recurring, plus the top spike and
whether storm mode is on. It can be switched off (`digest_enabled`).

## 16. SMART learns new words (0128)

This is how the rules grow without AI. SMART lists words residents keep
using (in at least 3 reports in the last 30 days) that it does not know:
not a rule word, not in the word list, not reachable by grammar, and not
a common word like "ang", "kanto" or "bahay". For each it shows the kind
of complaint they mostly come with ("nagliliyab: 3 reports, 100% public
safety") and, when there is one, a known word one or two letters away
("basuraa: likely basura"). An admin teaches the word in one step:

- as a **spelling**, **synonym** or **form** of a known word, which goes
  into the word list (nagliliyab → sunog);
- as a word of a **kind** of complaint, for the category hint;
- as an **urgent** word of a group, such as fire;
- or **dismisses** it, so it is not suggested again.

Open reports are scored again at once. A person approves every word; the
morning digest says how many are waiting.

## 17. Quiet cases (0128)

These are open cases with no update of any kind (status, tanod step or
note, message, dispatch, detail request) for 3 days (`stuck_days`), even
when no deadline has passed. The watcher tells the admins once per quiet
spell: "BRG-2026-0388 has had no update for 5 days (last: status:
validated)." The digest counts them.

## 18. The week (0128)

`smart_time_patterns(days, kind)` shows when each kind comes in, by
weekday and 3-hour block (Manila time), where a block has at least 5
reports and at least twice the kind's average block, with the most common
place. For example, "Peace and order: Saturday 21:00–00:00, 6 reports,
8.4 times usual, Purok 2." This is for planning patrols and duty.

## 19. Scorecard (0128)

`smart_sla_scorecard(month)` gives, per kind, the cases finished that
month, how many were within their deadline (or the SLA target when there
was none), the share, last month's share and the change, plus open cases
overdue now. Referred cases are left out, since another office finished
them.

## 20. SMART routing of the system's own dispatches (0128)

When the system dispatches by itself (an admin sends a dispatch "back to
the system", or a sweep retries), it now takes SMART's first choice
instead of only the nearest tanod. The tanods it can choose from are
exactly the same as before. Only the order changes: distance, jobs in
hand, cases closed nearby and location age (section 3). The tanod's
instructions say why: "Automatic dispatch — SMART pick: 330 m from the
incident, 0 job(s) in hand, 2 case(s) closed nearby." The resident's
timeline is unchanged. `smart_rules.smart_routing` switches it off, back
to nearest-only. Admins' own dispatches are untouched.

## 21. The SMART queue (0129)

Every open case goes in one order, by what it needs and how badly, with
the reasons.

**Next action.** Each case is at one stage:

- decide an escalation request;
- approve or return a tanod's resolution;
- review the complaint;
- assign a tanod;
- wait for the tanod to accept;
- reply to the resident (their message is the last one);
- follow up.

**Priority:**

| Part | Points |
|---|---|
| Urgency | the SMART score; an admin's level counts as low 10, normal 35, high 55, urgent 80 |
| Waiting at this stage | 1 an hour, 40 at most (`queue_aging_minutes`, `queue_aging_cap`) |
| Past its deadline | +20 |
| Likely to miss it (section 12) | +15 |
| Quiet for days (section 17) | +10 |

Waiting time is what makes it fair: a low case gains a point an hour,
so it never waits forever, but the cap keeps a fresh urgent case ahead
of it. A fire just filed (75) comes before a stabbing (60), which comes
before a clearance request waiting 50 hours (10 + 40), which comes
before fresh rubbish (25).

**The dispatch waiting line.** When no tanod is free, reports wait and the
system tries again every two minutes. Before, the next free tanod went to
whichever report had waited longest. Now they go to the report highest
in this queue, so a fire filed 20 minutes ago goes before a cedula
request waiting 3 hours. `smart_rules.smart_queue` switches the waiting
line back to first come, first served.

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
| Case card, everything included | 52 ms |
| Morning digest | 76 ms (211 ms with quiet cases and new words) |
| New words to learn, 30 days | 49 ms |
| Quiet cases | 101 ms |
| The queue, 25,000 open cases at once | 419 ms (a few ms at the barangay's real size) |

All SMART functions run with JIT off: they are short queries, and JIT
compiling cost about 55 ms a call for nothing.

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
| `smart_case_card(report)` | admins | the case page's SMART card in one call |
| `smart_summary()` | admins | the dashboard tiles |
| `smart_preview(kind, subject, description, lat, lng)` | admins | the score a complaint would get; saves nothing |
| `smart_read(text)` | admins | how SMART reads a text, word by word |
| `smart_lexicon` (table) | admins read and edit | spellings, synonyms and forms |
| `submit_id_reading(type, name, number)` | the app, for the signed-in account | stores what OCR read; flags worked out here |
| `smart_verify(user)` | admins | an account's ID checks: level, flags, reasons, what was read |
| `smart_verify_queue(role)` | admins | pending accounts, problems first |
| `smart_storm_mode(on, reason, hours)` | admins | storm mode on or off; open reports re-scored |
| `smart_deadline_risk()` | admins | open cases likely to miss their deadline |
| `smart_spikes()` | admins | kinds of complaint well above their usual week |
| `smart_similar_cases(report)` | admins | similar finished cases and how they ended |
| `smart_digest_preview()` | admins | the morning digest as it would read now |
| `smart_morning_digest()` | pg_cron, 07:00 Manila | sends the digest |
| `smart_word_suggestions(days)` | admins | words to learn, with their kind and a likely spelling |
| `smart_teach_word(word, as, target)` | admins | teach (spelling, synonym, form, category, urgent) or dismiss |
| `smart_stuck_cases()` | admins | open cases with no update for `stuck_days` |
| `smart_time_patterns(days, kind)` | admins | weekday and hour blocks well above usual |
| `smart_sla_scorecard(month)` | admins | on-time share per kind, against last month |
| `smart_queue(stage, limit)` | admins | open cases by priority, with stage, next action and reasons |

What the screens show, and where, is in `docs/SMART_SCREENS.md`.
| `smart_rules` (table) | admins read and update | the rules |

The hazard zones (`hazard_zones`, from `admin/assets/map/hazards.geojson`)
are generated by `supabase/tools/gen_hazard_zones.sh`.
