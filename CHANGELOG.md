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
  the layers (heatmap, flood zones, dim outside, transit, air quality, safe
  points) are back inside it; the heatmap is drawn in each complaint kind's own
  legend colour; safe points are white signs instead of coloured beads, so they
  no longer look like complaints; the buttons at the bottom right carry a word
  beside the icon (icons alone while a drawer is open); a recurring problem you
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

**Added (SMART screens, 21 Oct)**
- Storm mode shows as a banner at the top of every portal page, with **Manage**
  and **End it**, not only on the dashboard.
- Settings → SMART: **Words to learn** (`smart_word_suggestions`): each word with
  its reports, usual kind and an example; teach it as a spelling, synonym or
  form, as a word of a kind, as an urgent word, or dismiss it. A person approves
  every word.
- Dashboard: **When complaints come in** (`smart_time_patterns`): the weekday
  and three-hour blocks well above usual for each kind, with the place.

**Removed**
- The SMART drawer's "Show on the map" switches (rings, pulses, outlines).

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
