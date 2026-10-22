# Changelog

What changed in SmartSumbong, milestone by milestone, newest first. Dates are
when the work reached `main`; pull request numbers are in brackets. Migration
numbers (`0132`) point to `supabase/migrations`. The full detail of each change
is in its commit and pull request.

## Unreleased

Changes on `main` not yet deployed belong here.

**Changed (Rose's notes on the portal, 21 Oct)**
- Sign-in: the appearance and language options are back on the sign-in page;
  signing in lands on Notifications first.
- Dashboard: "Resolution status report" is now "Complaint status".
- Report Summary: the period chips sit on the same line as Report Period; the
  case-timeline list is paged like the ledger, escalations and tanod activity,
  and every pager keeps you at its own section.
- Spatial Distribution: the floating tab can be locked open and remembers it;
  the Layers tile stays at the map's bottom-left, with its row of pictures
  (the layers were briefly moved into the tab, and put back); the heatmap is drawn in each complaint kind's own
  legend colour; safe points are white signs instead of coloured beads, so they
  no longer look like complaints; the buttons at the bottom right are squircles
  at rest and widen to show their words while the mouse is on them; a recurring problem you
  click in the SMART drawer glows on the map and in the list.
- Case Reports: the "Needs attention", "Assigned to me", "Unassigned" and
  "Overdue" filters are removed; the search bar takes the rest of its row;
  "Open now" and the Review button are centred under their headings; a
  sensitive complaint reads in its own colour in the list.
- Sensitive cases have their own status: a plum **Sensitive** pill with a
  shield beside the case's progress (Case Reports, the case page and its map
  panel, Report Summary, Spatial Distribution's case sheet), and **Sensitive**
  in the Status filter. It sits beside the lifecycle status rather than
  replacing it, because a sensitive case still goes through every step. The
  resident never sees it.
- App: a tanod's dispatch order shows a plum **Sensitive case · handle with care**
  pill when the barangay marked the case sensitive, so the designated woman
  responder handles it discreetly. Residents never see it.

**Added (open-source data, 21 Oct)**
- Flood watch shows PAGASA's Metro Manila advisories, read from its NCR
  desk's page: the thunderstorm advisory while it is current, saying whether
  Pasay is named, and any rainfall advisory.

**Fixed (21 Oct)**
- Typhoon watch: PAGASA lists a storm's wind signals under the storm's own name,
  so the signal was never read and the Signal 3 alarm could not fire. The
  signal now shown is the one over Metro Manila; when there is none, Typhoon
  watch says so and names the highest signal and where it is (found with
  Super Typhoon Rosal live on 21 Oct: Signal 2, Batanes; none here).
- Spatial Distribution: the storm notice no longer takes height from the map
  (which hid the bottom of it, the Layers row included, while storm mode was
  on); it floats above the Layers tile as a slim pill.

**Polish (a look at every page, 21 Oct)**
- The search box takes the rest of its row on every page's band (Residents,
  Personnel, Extra Administrative Services, Notifications), not only Case Reports.
- Dashboard: Spikes and When complaints come in stack in one column, level with
  the On-time table, so no card is left with an empty half; the weekly table's
  times and places stay on one line.
- Personnel: the email column has room for a whole address.
- Settings: the map credits run the width of their card.
- Edit Profile: an empty mobile number reads "Not set".
- Workspace: the widget rail fades at its foot while more widgets wait below it;
  the board fades at its right edge while more stages wait beyond it.

**Added (SMART screens, 21 Oct)**
- Storm mode shows as a banner at the top of every portal page, with **Manage**
  and **End it**, not only on the dashboard.
- Settings → SMART: **Words to learn** (`smart_word_suggestions`): each word with
  its reports, usual kind and an example; teach it as a spelling, synonym or
  form, as a word of a kind, as an urgent word, or dismiss it. A person approves
  every word.
- Dashboard: **When complaints come in** (`smart_time_patterns`): the weekday
  and three-hour blocks well above usual for each kind, with the place.

**Added (open-source data, 21 Oct)**
- Earthquakes: PHIVOLCS, the official list, read first; USGS fills in what
  PHIVOLCS has not posted and stands in when it cannot be read. A quake both
  list shows once, with the USGS magnitude beside it.

**Changed (SMART reads more word forms, 0133, 21 Oct)**
- The reader knows the present tense (bumabaha, sinusunog, kinakagat), doubled
  words (sunog-sunog), stretched letters (sunoooog) and English endings
  (fires, wires, stabbing, crashed). Rules still decide; a form counts only
  when it ends at a word SMART knows.

**Changed (SMS codes, 21 Oct)**
- SMS codes go by Semaphore's OTP route instead of its bulk one, and carry
  the barangay's sender name once `SEMAPHORE_SENDER_NAME` is set (both found
  in pravennn08/semaphore-sdk, MIT). SMS stays off until credits are bought.

**Added (22 Oct)**
- Report Summary: **Download spreadsheet**, beside Download PDF Report: the
  same rows as the page (complaints, escalations, tanod activity, case
  timeline) in an Excel file, one sheet each. No complaint text; anonymous
  residents stay anonymous. Made with OpenSpout (MIT), the portal's first
  library through Composer.

**Added (Spatial, 22 Oct)**
- Layers → **Density**: the complaints the filters show, counted in hexagons
  about 66 m across, coloured by count (1, 3, 6, 10 or more); click one for
  its count. It follows the filters and the time slider. Off until switched on.

**Added (printed complaint, 22 Oct)**
- The printed Barangay Complaint carries a QR code at the bottom left, level
  with "Requested by": staff scan the paper to open that case in the portal
  (it only works for a signed-in administrator). Made on the server with
  chillerlan/php-qrcode (MIT/Apache-2.0); a reader decodes it from a screenshot.

**Added (SMART, Iteration 2: explaining itself and being measured, 22 Oct)**
- The database side (0140). SMART's rank of the tanod an admin chooses is
  saved with the dispatch, with the reasons, and the top-pick rate can be
  read. Resolving a case asks the resident "Naayos na ba? / Was it fixed?";
  "not fixed" tells the admins and queues the case for a recheck until the
  barangay reopens it or answers. A plain sentence on why a report is where it
  is, in English and Tagalog, for the resident. Engine health. One event log
  for all of it. The portal and phone screens for these follow.

**Added (SMART in the app, Iteration 2, 22 Oct)**
- Tanod: a "Why you" card on the dispatch window. SMART's rank among the tanods
  it could have sent, and why (how near, how busy, who knows the area), in
  English and Filipino. Kind words: second place is no fault of the tanod.
- Resident: "Naayos na ba? / Was it fixed?" on a resolved report (Yes, or Not
  yet with a line for what is still wrong), and a "Why this order" row on an
  open report, in words and never a score.
- Sign-up: a quiet line under the ID photo ("SMART is reading your ID…", read,
  or "a person will check it").
- Settings: the build name ("SmartSumbong • D · v…") and "Powered by SMART".
- All of it is optional on the phone: an older database or a failed request
  never blanks a screen.

**Added (SMART, Iteration 3: rule versions, rollback, replay, 22 Oct)**
- Every change to SMART's scoring rules or word list is now a numbered
  version with who, when and why; each score remembers the version that made
  it. A change can be tried on the last 90 days of reports first ("this would
  move 6 reports from normal to high") without making it, and any version can
  be rolled back, as one new version, with the open reports re-scored (0141).
  The portal screens for these follow.

**Changed (the engine on the phone, 22 Oct)**
- ID reading is back, on the phone, with open-source PaddleOCR (PP-OCRv6
  small on ONNX Runtime, via the paddle_ocr_native plugin) instead of Google
  ML Kit. The same reader logic as the server engine, in Dart. Phones older
  than Android 8 skip it (a person checks the ID, as before). On invented
  cards: 48/48 clean, 42/48 good, 48/48 poor, 32/48 heavily blurred. The app
  grows from 55 to 107 MB (budget 120). The portal shows the readings again
  (ID_OCR_ENABLED). A reading never verifies anyone.

**Added (the panel's open asks, 22 Oct)**
- 3a: Case Reports can be filtered by the specific issue under a category
  (the Issue filter appears once a category is chosen).
- 3b: the resident's report screen shows each concern in the report and
  whether it is resolved, when there is more than one.
- 2, in the app: My reports shows twenty at a time, with a Show more button.
- 4: on an anonymous report the barangay sees who filed it (tagged
  "Anonymous to others") and can write to them; tanods, lists, the map and
  the printouts still do not show the name.

**Fixed (the reroute queue, 22 Oct)**
- The auto reroute and its waiting line cannot log without end any more. Two
  old test reports had written "No tanod available" about 13,000 and 9,500
  times; an earlier fix stopped that, and this closes the rest: a reroute
  that finds no one waits in line for a day at most and never past the cap on
  offers; "gave up" and its notice to the administrators are written once; an
  administrator's reroute starts a fresh run; and a system line identical to
  one just written on the same report is not written again (0139).

**Added (server memory, 22 Oct)**
- Settings → System status → Server memory: how much of its memory the
  portal's server uses now, at most this week, and on average. Render's free
  plan hides its metrics, so the portal reports its own with each 10-minute
  check (0138). It decides what the engine can run on the free server.

**Added (the engine, 22 Oct)**
- The engine: heavy work runs on the server, not the phone (Ace: the
  portal's features and labs run as engine functions). Its first job reads
  each new sign-up's ID photo with PaddleOCR (the OCR lab's pick): the card's
  type, the name and the number, judged by the same checks as before (0126).
  On invented cards: 48/48 clean, 42/48 good photos, 48/48 poor, 32/48 badly
  blurred; about 220 MB of memory at its peak. The app no longer needs an OCR model. The engine is its own small
  service (`engine/`) with no database or Cloudinary key; the database queues
  the photos, signs one link each, and files the answers every minute (0137).
  Settings → System status shows it. A reading never verifies anyone.

**Added (alerts, 22 Oct)**
- Alerts that each person sets up (Profile → Alerts): which kinds (overdue
  cases, SMART warnings, things to do, dispatch changes, personnel), every
  case or only the ones they handle, quiet hours with urgent cases let
  through or not, and a test button. The same choices hold for the app on
  their phone. The inbox in Notifications always keeps everything (0136).
- Browser alerts: an alert reaches the portal's staff even with the portal
  closed, and a click opens the case. Encrypted for that one browser (RFC
  8291) and signed with our own key (RFC 8292), written with the standard
  Web Crypto API and no library; free, no Google account. Works in Chrome,
  Edge and Firefox; on an iPhone, once the portal is on the Home Screen.

**Changed (search, 22 Oct)**
- Spatial's search finds places the way Google Maps does: every named place
  and street in and around the barangay from OpenStreetMap, refreshed every
  six hours, and the barangay's own places; it forgives slips and shorthand
  ("brgy hall", "villamor air bse"), groups a chain ("Watsons, 2 branches"),
  shows each place's kind and distance from the hall, and offers one-tap
  kinds (Health, School, Church, Police and fire, Food, Shop, Transport).
  Tagalog words for a kind work too (botika, simbahan, palengke) (0134).
- App: the address field on a new report suggests the same places first,
  then Photon's, as before.
- The barangay names its own places: right-click a spot on Spatial (or press
  and hold) and choose "Add a place here"; Settings > Appearance lists them to
  rename, re-kind, give other names ("brgy hall") or remove. Search finds them
  first, in the portal and the app. Places only, never a home; within 5 km of
  the hall; administrators only (0134).

**Removed**
- The SMART drawer's "Show on the map" switches (rings, pulses, outlines).

**Checked (open-source data, 21 Oct)**
- The barangay boundary against the official PSA/NAMRIA line
  (docs/BOUNDARY.md, `tools/boundary_compare.py`): they agree on every place
  people live and every complaint so far; ours adds 2.39 km² of NAIA airside.
  OpenStreetMap's line stays; our PSGC code `1381100183` is the current one.

## 2026-10-17 — Workspace widgets; house clean

The full record, with what was checked and what is still open:
[docs/changes/2026-10-17.md](docs/changes/2026-10-17.md).

**Added**
- The Workspace becomes each staff member's own screen: a slim rail of
  widgets chosen from a library of 120 (cases, team, weather and hazards,
  tools, apps, RSS, minigames), 12 by default, each previewable before adding
  (0132, #131–#136; contract in docs/WIDGETS.md).
- Flood and Typhoon watch from PAGASA and GDACS, read in parallel with the last
  good copy standing in; weather, air, tides and quakes fall back to the browser
  when the server's request is refused (#133).
- The app on tablets: it may turn, and shows in a phone-width column (#137).
- Documentation: ARCHITECTURE, SMART_ENGINE, CONTRIBUTING, SECURITY,
  DEFENSE_ASKS and this changelog; README, DEPLOY, OPERATIONS and the schema
  reference rewritten (#141, #143).

**Changed**
- `main` carries no 3D City view code; it lives on `bellinist` only (#138).
- flutter_local_notifications 22.3.2 (#139).

**Removed**
- Unused images (2 portal, 13 app) and packages (`exif`, `device_info_plus`) (#138).

**Security**
- Clickable rows follow only links inside the portal; CodeQL at zero open
  alerts (#140). Dependabot alerts and security updates, secret scanning with
  push protection, and private vulnerability reporting switched on.

## 2026-10-14 to 10-16 — The panel's asks, SMART on screen, the look

**Added**
- The defense asks (0130, #31, #32): the barangay's structure (secretary,
  kagawad by committee, chairman), the escalation ladder up and back down,
  several concerns per report, sensitive cases and designated women
  responders, paging on every long list, Case Reports showing only cases.
- SMART on every screen it serves: the case card, dashboard tiles, roster,
  map drawer, Settings → SMART; the engine's logo (#36).
- Notifications rebuilt: the briefing, three lanes, a feed by day; three
  briefings a day (0131, #37).
- The work board in the Workspace, closer to Trello within the barangay's
  rules: a panel per card, glide between columns.
- Spatial Distribution for `main`: search, time slider, saved views, layers
  (transit, air quality, safe points), Look around and Send to tanod (#28).
- Case map sidebar with a street-view snapshot (#92).

**Changed**
- A look pass over every page: orange bands, Residents and Personnel as a
  people directory, Material light mode, the sign-in rail in dark mode, Report
  Summary tiles, a measured light and dark contrast sweep, a symmetry sweep
  (#53–#126).

## 2026-10-10 — The SMART engine; backend review

**Added**
- SMART, rule-based with reasons for everything: triage scores, duplicates,
  tanod ranking and resolution estimates (0121–0122); overrides, the watcher,
  recurring problems (0123); the screens' calls (0124); reading Taglish (0125);
  ID checks on the server (0126); storm mode, deadline risk, spikes, case
  memory and the morning digest (0127); learning words, quiet cases, weekly
  patterns, the scorecard, routing to free tanods (0128); the priority queue
  (0129). Explained in docs/SMART.md.
- Hardening (0114–0120): per-address sign-in limits and SMS code tries,
  cron-only sweeps, a daily filing limit, signed uploads with limits, private
  identity photos and their cleanup, notification retention, sign-out on reset
  or suspension, health alerts, pausing filing, tracking IDs past 9,999.
- Optional Turnstile bot check on sign-in, sign-up and reset links.
- Edge Function tests (a `handler.ts` per function), performance budgets, a
  query budget at 50,000 complaints, accessibility (44 px targets, WCAG AA).

**Changed**
- Cloudinary signatures use SHA-256 everywhere.
- Android API 37 toolchain; Flutter packages to their latest compatible versions.
- CI's database checks on PostgreSQL 17, as Supabase runs.

**Fixed**
- Tracking IDs broke at the 10,000th complaint (0120).

## 2026-10-06 to 10-07 — Industry passes; Singapore

**Added**
- CI on every push (PHP and JS parse, a portal smoke test with CSP and nonce
  checks, Flutter analyze and test, database checks), security scanning, an
  encrypted nightly backup, a Deploy workflow.
- Security headers, a strict nonce Content-Security-Policy, secure cookies.
- Portal uptime record, error tracking and outage alerts (0096–0098).
- A tanod can hold up to five dispatches (0100–0101).

**Changed**
- The portal moved to Render Singapore (`smartsumbong-ph`); the old address
  forwards. Kept awake by the database (0091, 0094). OPcache, gzip, one pooled
  HTTP/2 connection to the database.
- The resident's timeline reads BARANGAY for admin entries and hides staff-only
  notes (0099).

**Security**
- `send-dispatch-push` only sends notifications as stored in the database.

## 2026-10-04 to 10-05 — The app rebuilt (branch D); case handlers

**Added**
- Every app screen rebuilt from the app preview on one design system
  (`lib/d`), with a preview mode on demo data.
- One handler per case, enforced in the database, with take, release and take
  over, and the Activity page (0087).
- New administrators get a one-time password, then choose their own by an
  emailed link; a branded reset email.
- Forgot password by SMS code through Semaphore (0085; switched off until
  credits are bought); changing one's number by code (0104).
- Admin profile photos; media folder pins (0083).

**Security**
- Location and camera data stripped from photos uploaded through the portal.

## 2026-09-26 to 10-03 — One app; the refined portal

**Added**
- One app for residents and tanods (branch C): the tanod app folded in, its
  role chosen at sign-in.
- Maps on MapLibre with OpenFreeMap vector tiles and our own styles, 38
  curated landmarks, purok zones; the case preview on the same map.
- The portal in Tagalog, every screen and message; fitted to the screen.
- The refined portal look (1 Oct); day and night, EN and PH, the contour
  texture, flood watch (3 Oct).

**Changed**
- Tanod location at key moments only: no background tracking.

## 2026-09-23 to 09-25 — Figma 1:1; sweeps; offline

**Added**
- Every resident and tanod screen matched to the Figma file.
- A tanod can ask the resident for more details (0065).
- The report outbox: filing with no signal queues the complaint (0066).
- Screens open on their last saved copy and work without signal.
- A daily GitHub Actions ping so the free Supabase project never pauses.

**Fixed**
- Portal, resident, tanod and core sweeps: an XSS on the spatial map, double
  submits, unmounted state, offline sign-in misreported, push token unregistered
  before sign-out; RLS policies evaluated once per query (0061).

## 2026-09-05 to 09-15 — Ready for the first defense

**Added**
- On-device OCR triage of ID photos (now switched off), field reports,
  feedback and the video viewer in the portal.
- Appeals for rejected complaints.
- A Docker image and deploy for the defense; vendored frontend libraries.

**Removed**
- The public transparency dashboard.

## 2026-08-02 to 08-30 — The apps and the trail

**Added**
- The resident app: registration with ID evidence (0019), sign-in by mobile
  number, reports, the map, the emergency directory, settings, notifications,
  onboarding.
- The tanod app: duty status, dispatches, reports.
- Push notifications, crash reporting, secure session storage, biometric
  unlock, dark mode and Tagalog in the apps.
- The tamper-evident audit trail: append-only, hash-chained `status_logs` and
  `account_audit`.
- Password recovery at the barangay counter (0028–0029); the resident abuse
  strikes; hotspot analytics.
- EXIF stripped on the phone before upload.

## 2026-07-31 to 08-01 — Foundation

**Added**
- The schema, dispatch and deadline rules, row-level security, PostGIS and
  the barangay boundary.
- The admin portal: sign-in, Case Reports, case review and assignment, the
  tanod roster, the dashboard, account verification and suspension, Spatial
  Distribution, Report Summary with its PDF, Edit Profile.
