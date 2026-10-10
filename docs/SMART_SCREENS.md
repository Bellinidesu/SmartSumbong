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
- One call fills the card: `smart_case_card(report)` (0124).

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

### 7. Notifications (portal bell)

The watcher's messages already arrive as notifications; an urgent one is
linked to its report. Only check that the bell opens the case.

## Resident app

### 8. Report view (`report_view_screen.dart`) and Report submitted (`report_submitted_screen.dart`)

- One line under the status: "Similar complaints are usually resolved in
  about 7 hours" / "Karaniwang naaayos ang ganitong sumbong sa loob ng
  mga 7 oras", from `smart_eta(category)`. Show nothing when the basis is
  `target` and there are no cases yet, rather than promising the SLA.
- Never the score or level: a resident whose complaint is "low" must not
  be told so.

## Tanod app

- Nothing for now. If the barangay wants it later, an **Urgent** label on
  a ticket (the effective level only, no score or reasons) is the most to
  show.

## Build order

1. Case detail SMART card (2) and the roster recommendation (3). This is
   where the engine changes decisions.
2. Case Reports column and sort (1), and the dashboard tiles (5).
3. Settings → SMART (6), so the barangay can tune the rules itself.
4. Recurring problems on the map (4).
5. The resident's estimate (8).
