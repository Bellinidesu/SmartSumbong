# SMART on screen: what to add, and where

This is the screen side of the SMART engine (`docs/SMART.md`). The engine
lives in the database; nothing below exists on screen yet. Each item
gives where it goes, what it shows, the function or table it reads, and
what it must not do.

## Rules for every SMART screen

- **Reasons always beside the result.** A level or score never appears
  without its reasons (`report_triage.reasons`, the `reasons` of a
  ranking). The reasons are the feature: they are what makes the result
  defensible to a resident, the barangay or the panel.
- **People decide.** SMART recommends; nothing on screen dispatches,
  merges or rejects by itself. Every dispatch stays the admin's (0070).
- **No tracking.** Show the age of a tanod's last location reading, never
  a live position (live tracking was removed, 0072).
- **Admins only**, except the resolution-time estimate. Residents and
  tanods never see scores, levels or rankings.
- Every label in both English and Tagalog (`t('…', '…')` in the portal,
  `i18n.dart` in the app; CI checks the portal's pairs).
- Levels use one colour each, the same everywhere, with the word always
  next to the colour: **Urgent** red, **High** orange, **Normal** blue,
  **Low** grey. Colour alone never carries the meaning.
- Touch targets of at least 44 px, as in the rest of the portal and app.

## Portal

### 0. Case Reports (`cases.php`): the **Next up** view (0129)

This is the admin's work list, from `smart_queue(stage, 50)`, and is
meant to be the first tab of Case Reports.

- One row per case, highest priority first: tracking ID, subject, level
  badge, the **next action** as the row's button ("Assign a tanod",
  "Reply to the resident", "Approve or return the resolution"), and
  "waiting 3 h".
- The priority as a small bar, with its parts on hover or tap:
  "Urgent 75 · waiting +12 · overdue +20".
- Stage chips to narrow the list: Review, Assign, Approve, Reply,
  Escalation, Waiting for accept, Follow up. Each shows its count.
- The existing date-sorted list stays as the second tab.

### 1. Case Reports (`cases.php`): urgency in the list

- A **SMART** column: the level badge with the score as small text
  ("Urgent · 75"). If an admin overrode it, show the admin's level with a
  small "set by admin" mark.
- Sort option **"Most urgent first"**: `effective_level`, then `score`,
  then oldest first. Keep the current order as the default until the
  barangay asks for this one.
- A **"Possible duplicate"** chip when `possible_duplicates > 0`.
- Reads: `report_triage` (`effective_level`, `score`,
  `possible_duplicates`) joined on `report_id`.

### 2. Case detail (`case.php`): the SMART card

A card near the top of the case, above the timeline:

- **Level and score**: "Urgent · 75". Under it the reasons, one line each
  with its points: "Fire ("sunog") +30", "Child mentioned +10",
  "NOAH flood zone, high +15", "2 other residents reported this within 150 m +16".
- **Change level**: a small button that opens level choices (Low, Normal,
  High, Urgent, or Use computed) and a required reason box, 3 to 300
  characters. It calls `smart_override(report, level, reason)`. After an
  override the card shows both levels: "Set to High by Admin Santos:
  'already handled by BFP' · computed: Urgent 75".
- **Possible duplicates**: up to 5 rows from `smart_duplicates(report)`,
  each with tracking ID (a link), distance ("40 m away"), "5 hours
  earlier", status, and how alike the words are (Very alike / Alike). No
  merge button: the admin opens the other case and decides.
- **Usually resolved in**: "about 7 hours (most within 20)" from
  `smart_eta(category)`, or "target: 48 hours" when the basis is `target`.
- **Similar past cases** (0127): up to 3 rows from the card's `similar`.
  Each has the tracking ID as a link, "120 m away", "resolved in 2 days",
  and how it ended (referred to …, the closing remark, or the tanod's
  field report). Above them, the card's `referral` line if there is one:
  "Usually referred to City Veterinary Office (3 of 3)."
- **Deadline risk** (0127): if the card's `deadline_risk` is set, a line
  in the risk's colour: "Likely to miss its deadline: 5 h left, such
  cases usually take 48 h."
- One call fills the card: `smart_case_card(report)` (0124, extended in 0127).

### 3. Case Assign (`case.php`, the roster): who to send

- Order the roster by `smart_tanod_ranking(report)` and mark the first
  one **Recommended**.
- Under each name, the four reasons in one line: "320 m · 1 job in hand ·
  3 cases closed nearby · last reading 6 min ago".
- The admin still picks anyone and presses Dispatch as today. If they
  pick someone other than the recommended tanod, nothing is asked; it is
  their call.

### 4. Spatial Distribution (`spatial.php`): recurring problems

- Reuse the hotspot panel, dock button and map layer that are already
  there behind `HOTSPOTS_ENABLED`, feeding them from `smart_patterns()`
  instead of `report_hotspots`, and name them **Recurring problems /
  Paulit-ulit na problema**. Use a panel, not the checkbox Rose asked to
  remove (2 Oct 2026).
- Each item: the kind of problem, "6 reports from 5 residents over 4
  weeks, 2 still open", the hazard zone if any, and the latest tracking
  IDs as links. Clicking one centres the map on it.

### 5. Dashboard (`dashboard.php`): two tiles

- **Urgent, waiting for a tanod**: the count of `effective_level` urgent
  or high reports in `pending_review` or `validated` with no live
  dispatch; it links to Case Reports sorted most urgent first.
- **Recurring problems**: the count from `smart_patterns()`; it links to
  Spatial Distribution with the panel open.
- One call fills both: `smart_summary()` (0124).
- Two more tiles (0127): **Likely to miss the deadline** (the count of
  `smart_deadline_risk()` with risk high; links to a list), and
  **Spikes** (`smart_spikes()`: "Animal welfare: 6 this week, usually
  0.5, mostly Purok 3").
- **Storm mode banner**: while `smart_rules.storm_mode` is on, a banner at
  the top of every portal page says "Storm mode until Oct 12 18:00:
  PAGASA orange rainfall warning", with a button to end it.

### 6. Settings → SMART (`settings.php`, a new section)

- **Rules**: a table of the points per kind of complaint; the word groups
  (label, points, words) as rows; the hazard points, nearby-report radius
  and hours, night points, level cut-offs, duplicate and
  recurring-problem settings, and the watcher's minutes. **Save** writes
  `smart_rules`; **Re-score open reports** calls `smart_retriage()`.
- **Try it**: a kind, a sentence and a map pin; it shows the score, level
  and reasons it would get, without saving anything:
  `smart_preview(category, subject, description, lat, lng)` (0124). This
  lets the barangay check a rule change before saving it.
- **How the rules are doing**: two small tables from
  `smart_calibration(90)` (per level: reports, raised, lowered, time to
  dispatch, time to resolve) and `smart_factor_stats(90)` (per factor).
  One sentence above them: "If admins often lower reports with a factor,
  it may be worth fewer points."

### 6b. Settings → SMART: storm mode and the digest (0127)

- **Storm mode**: a switch, a required reason, and hours (default 24).
  It calls `smart_storm_mode(on, reason, hours)`. Show what it does in
  one sentence: "Flood zones and flood, live-wire and collapse reports
  count double until it ends."
- **Morning digest**: an on/off switch (`smart_rules.digest_enabled`)
  and a preview box showing `smart_digest_preview()`.

### 6c. Settings → SMART: words to learn (0128)

- A list from `smart_word_suggestions(30)`. Each row has the word, how many
  reports, its usual kind ("100% public safety"), an example subject, and
  "likely a spelling of basura" when there is one.
- Buttons per word: **Means…** (pick a known word; spelling, synonym or
  form), **Word for…** (pick a kind), **Urgent word for…** (pick a group),
  and **Not a word to learn**. Each calls `smart_teach_word`.

### 6d. Dashboard: scorecard and the week (0128)

- **Scorecard**: one row per kind from `smart_sla_scorecard()`, with
  on-time %, last month's %, an up or down arrow with the change, and
  overdue now.
- **When complaints come in**: the top rows of `smart_time_patterns(90)`,
  for example "Peace and order · Saturday 21:00–00:00 · Purok 2 · 8×
  usual". Personnel can use it to plan duty.
- **Quiet cases**: a tile with the count of `smart_stuck_cases()`, which
  links to the list (tracking ID, days quiet, last update).

### 7. Residents and Personnel (`residents.php`, `personnel.php`): ID checks

Only once the barangay turns ID reading back on (`ID_OCR_ENABLED`):

- In the pending list, a level badge from `smart_verify_queue(role)`
  (**Problem**, **Check**, **Ready**, **No reading**), with problems
  sorted first.
- On the account, the reasons one per line next to the ID photo and
  what was read: "Name on the ID: SANTOS, MARIA. Not found: REYES, ANA."
  A reused number links to the other account.
- **Quick Verify** only for **Ready**, and only with the ID photo on
  screen. It replaces `account_ocr_is_clean()` and the client's flags.
- Add labels for the two new flags in `ocr_flag_label()`:
  `number_format` ("ID number has the wrong shape" / "Mali ang anyo ng
  numero ng ID") and `number_reused` ("ID number is on another account" /
  "Nasa ibang account ang numero ng ID").

### 8. Notifications (portal bell)

The watcher's messages already arrive as notifications; an urgent one is
linked to its report. Only check that the bell opens the case.

## Resident app

### 9. Report view (`report_view_screen.dart`) and Report submitted (`report_submitted_screen.dart`)

- One line under the status: "Similar complaints are usually resolved in
  about 7 hours" / "Karaniwang naaayos ang ganitong sumbong sa loob ng
  mga 7 oras", from `smart_eta(category)`. Show nothing when the basis is
  `target` and there are no cases yet, rather than promising the SLA.
- Never the score or level: a resident whose complaint is "low" must not
  be told so.

## Tanod app

- Nothing for now. If the barangay wants it later, an **Urgent** label on
  a ticket (the effective level only, no score or reasons) is the most to
  show. Tickets could also be sorted urgent first when a tanod has
  several, using the same effective level.

## Next ideas (not built)

- **Report completeness (resident app)**: before sending, a gentle nudge
  when a report is thin: a very short description, no photo for a kind
  that usually has one, or no landmark. These are plain rules on the
  form; the resident can still send.
- **Duty coverage (Personnel)**: when and where reports come in (hour of
  day, area), set against who is on duty then, to plan shifts. Plain
  counts, a heat table.
- **Feedback mood (Dashboard)**: positive and negative words in
  residents' ratings, using an English and Tagalog word list (salamat,
  mabilis, wala pa rin, bagal), beside the stars, to see what people
  praise and what they complain about.

## Build order

1. Case detail SMART card (2) and the roster recommendation (3). This is
   where the engine changes decisions.
2. Case Reports column and sort (1), and the dashboard tiles (5).
3. Settings → SMART (6), so the barangay can tune the rules itself.
4. Recurring problems on the map (4).
5. The resident's estimate (9).
6. ID checks (7), when the barangay turns ID reading back on.
