# SmartSumbong — Schema Reference

What the migrations in `supabase/migrations/` add up to: 125 files, 0001–0132
(numbers 0048 and 0108–0113 are unused; 0108–0113 became 0114–0120 to follow
production's 0107). The exact current schema, every column and grant, is
`supabase/baseline/baseline.sql`; this file is the map. If the manuscript's
Data Dictionary and this file disagree, one of them is wrong: fix both in the
same sitting.

Actor naming is **`tanod`** throughout, per the panel revision.

How the database fits the rest of the system is in
[ARCHITECTURE.md](ARCHITECTURE.md); the SMART engine's rules in
[SMART.md](SMART.md); the Workspace widgets' contract in [WIDGETS.md](WIDGETS.md).

---

## Tables (60)

### Complaints and their work

| Table | Purpose | Since |
|---|---|---|
| `reports` | Complaints: category, place (`geom`), status, admin-set `due_at`, referral (`referred_to`…), follow-ups, resolution awaiting approval, `is_public`, `version` (stale-page guard), sensitivity | 0001 |
| `report_concerns` | One row per concern in a report (the main category included), each open or resolved on its own | 0130 |
| `report_media` | Resident photos and video | 0001 |
| `report_evidence` | Photos the barangay attaches from the portal: with an update, or when it resolves | 0079 |
| `status_logs` | Append-only, hash-chained audit trail (0015); one writer per complaint, checked with `verify_report_trail` (0082) | 0001 |
| `feedback` | Post-resolution rating and comment | 0001 |
| `dispatches` | Assignment, accept, reroute, step (On the way / Arrived), field report | 0002 |
| `dispatch_media` | Tanod photo/video proof; `update_id` tags photos sent in the thread (0069) | 0002 |
| `dispatch_updates` | The dispatch window's thread: tanod notes, admin replies, steps | 0069 |
| `report_messages` | "Ask the barangay": a complaint's resident ↔ barangay thread | 0072 |
| `detail_requests` | "More details needed" asked of the resident, and the answer | 0065 |
| `escalation_requests` | A tanod's request to escalate, and the admin's decision | 0073 |
| `sla_policies` | Per-category guide hours and the tanod's accept window | 0001 |
| `sla_extensions` | Audited deadline extensions | 0002 |
| `case_handler_log` | Admins taking, releasing and taking over cases (Activity page) | 0087 |
| `committee_for_category` | The committee that usually takes each kind of complaint (editable defaults) | 0130 |
| `look_shares` | "Look around" sent to a tanod: a note, the street image, which way the spot lies | 0107 |

### People and accounts

| Table | Purpose | Since |
|---|---|---|
| `users` | Accounts, role, official role and committee (0130), verification, suspension, retirement, duty status, last known location | 0001 |
| `account_audit` | Hash-chained log of account changes | 0014 |
| `attendance` | Tanod duty logging | 0001 |
| `device_tokens` | FCM push tokens | 0035 |
| `retirement_requests` | A tanod's request to retire, and the admin's decision | 0052 |
| `profile_requests` | A resident's or tanod's name change or new ID photo, and the admin's decision | 0086 |
| `login_attempts` | Lockout after repeated failures | 0031 |
| `login_failure_sources` | Failed sign-ins per network address, 15-minute window; past 20 they stop counting toward a lockout | 0114 |
| `password_otps` | SMS codes for password reset and number change, hashed (0085, 0104) | 0085 |

### The barangay and its settings

| Table | Purpose | Since |
|---|---|---|
| `barangay_boundary` | OSM relation 2988704 as a PostGIS polygon | 0005 |
| `operational_settings` | Single row: attempt cap, location freshness, alert thresholds, filing pause, max active dispatches | 0010 |
| `hotline_groups`, `hotline_numbers` | The app's emergency hotline list | 0025 |
| `notifications` | In-app alerts, pushed to phones (`is_read`) | 0001 |
| `hazard_zones` | NOAH flood and storm-surge zones (level 1 low to 3 high), subdivided for fast point lookups | 0121 |

### System health

| Table | Purpose | Since |
|---|---|---|
| `portal_uptime` | Every 10-minute check of `/admin/ping.php` and whether it answered | 0096 |
| `portal_errors` | Portal PHP and browser errors, grouped by message with a count | 0097 |
| `portal_outages` | One row per outage (two missed checks), with how long it lasted | 0098 |
| `system_alerts` | One row per problem the hourly health check watches; open ones show in Settings | 0119 |
| `rate_limit_hits` | Fixed-window counters for Edge Functions (`take_rate_slot`) | 0116 |
| `media_trash` | Identity-photo addresses no longer used, deleted from Cloudinary a week later | 0118 |

### SMART engine

| Table | Purpose | Since |
|---|---|---|
| `smart_rules` | The rules triage follows (points per kind, words, zones, nearby, night, cut-offs); one row, admins change it | 0122 |
| `report_triage` | Each report's score 0–100, level and reasons; written only by `smart_triage()` | 0122 |
| `smart_overrides` | Every admin raise, lower or clear of a level, with the score and reasons of that moment | 0123 |
| `smart_patterns_seen` | What the watcher already told the admins (recurring problems, spikes, deadline risks) | 0123 |
| `smart_lexicon` | Words SMART reads as another word: texting spellings, English–Tagalog synonyms, irregular forms | 0125 |
| `smart_word_decisions` | Words an admin taught SMART or dismissed | 0128 |

### Workspace widgets

| Table | Purpose | Since |
|---|---|---|
| `workspace_prefs` | Each staff member's chosen widgets, open tab, own RSS feeds and watch words, private notes | 0132 |
| `workspace_settings` | The barangay's choices: alarm rules, minigames on or off, shift start hours, fares | 0132 |
| `team_posts`, `team_post_reads` | The Chairman's notice, shift handover, team board and announcements; who has seen each | 0132 |
| `polls`, `poll_votes` | A one-question team poll, one vote per person | 0132 |
| `staff_dates`, `staff_leave`, `staff_credentials` | Birthdays, leave, and trainings/IDs with expiry | 0132 |
| `duty_roster` | Who is on which shift on which day (also what "late" is measured against) | 0132 |
| `patrol_checkpoints`, `checkpoint_scans` | A patrol round's places in order, and who reached each | 0132 |
| `shift_checkins` | A private one-tap check-in per person per day; the lead sees only totals | 0132 |
| `relief_tally` | Relief packs given out during a calamity, per street | 0132 |
| `safe_point_notes` | What OSM does not hold about an evacuation centre: capacity, open or not | 0132 |
| `game_scores` | Each person's best per minigame | 0132 |

Removed: `tanod_locations` (live tracking history, dropped in 0072), the public
transparency functions (0043, removed). `emergency_alerts` was never built: the
emergency feature is out of scope by panel direction.

---

## Functions, by who calls them

Every state change goes through a function rather than a bare `UPDATE`, so the
status, the audit trail and the notification move in one transaction. Most are
`security definer` because `notifications` and `status_logs` have no insert
policy by design. "Latest" is the migration that last redefined it.

**Admin portal: the case**

| Function | Latest | Does |
|---|---|---|
| `review_report(report, decision, remark, abusive)` | 0040 | Validate / Reject Report |
| `admin_dispatch(report, tanod, instructions)` | 0071 | Assign a tanod: requires a target date and instructions |
| `set_resolution_target(report, due, reason)` | 0079 | Set the target date; the resident is told. Moving it later is an extension: needs a reason, recorded in `sla_extensions`, capped by `max_deadline_extensions` (2) |
| `hand_to_higher_official(report, official, note)` | 0079 | Once the extensions are used up: hand the case to a barangay official; any tanod stands down |
| `escalate_in_barangay(report, …)` / `return_from_official(report, …)` | 0130 | Up the ladder (the kagawad of the right committee with the fewest open cases, then the chairman), and back down |
| `add_report_concern`, `set_concern_status` | 0130 | Several concerns in one report, each resolved on its own |
| `set_case_sensitive(report, …)` | 0130 | Mark or unmark a case sensitive (VAWC and the like); sensitive cases stay out of the dispatch waiting line |
| `admin_barangay_update(report, body, media)` | 0079 | An update with photos to the timeline and the resident, no tanod needed |
| `admin_reroute_dispatch(dispatch, reason, to)` | 0070 | Move a live dispatch to a tanod or back to the system |
| `approve_resolution(report)` / `reject_resolution(report, reason)` | 0073 | Approve the tanod's resolution, or return it |
| `admin_set_status(report, status, remark, media)` | 0079 | In Progress / Offline Investigation / Resolved, with proof photos |
| `refer_report(report, office, note)` | 0073 | Escalate to an outside office (closes the case here) |
| `approve_escalation` / `deny_escalation` | 0073 | Decide a tanod's escalation request |
| `set_report_public(report, public)` | 0073 | Show on residents' map |
| `post_dispatch_update` / `post_report_message` | 0069 / 0072 | Reply to the tanod / to the resident |
| `request_additional_details(report, message)` | 0065 | Ask the resident for more |
| `appeal_report(report, remark)` / `reopen_report(report, reason)` | 0071 | Grant an appeal / reopen: both clear the date |

**Admin portal: accounts and the barangay**

| Function | Latest | Does |
|---|---|---|
| `verify_user_account`, `set_account_suspension`, `admin_reset_password`, `admin_update_user` | 0013–0073 | Accounts |
| `set_official_role(user, role, committee)` | 0130 | Secretary, kagawad (with committee) or chairman; designated women responders |
| `finalize_retirement` | 0052 | Retirement requests |
| `promote_to_admin`, `step_down_as_admin`, `cancel_admin_handover` | 0014–0055 | Admin succession (portal switch off: `ADMIN_SUCCESSION_ENABLED`) |
| `account_directory`, `tanod_roster`, `dashboard_metrics`, `report_hotspots`, `resident_abuse_reports`, `retirement_requests_queue` | — | Reads for the screens |

**Admin portal: SMART** (rules and reasons in [SMART.md](SMART.md))

| Function | Since | Does |
|---|---|---|
| `smart_triage`, `smart_retriage` | 0122 | Score a report, with reasons; re-score after a rule change |
| `smart_duplicates_of`, `smart_tanod_ranking`, `smart_eta` | 0122 | Likely duplicates; who to send, best first; resolution-time estimate |
| `smart_override` | 0123 | Raise or lower a level, with a reason |
| `smart_case_card`, `smart_summary`, `smart_preview` | 0124 | The case card, the dashboard tiles, Try it |
| `smart_read` | 0125 | How SMART read a text (word forms, spellings, negation) |
| `smart_verify`, `smart_verify_queue` | 0126 | ID checks on what the phone's OCR read |
| `smart_storm_mode`, `smart_deadline_risk`, `smart_spikes`, `smart_similar_cases` | 0127 | Foresight |
| `smart_word_suggestions`, `smart_teach_word`, `smart_stuck_cases`, `smart_time_patterns`, `smart_sla_scorecard` | 0128 | Learning and the scorecard |
| `smart_queue` | 0129 | Every open case in one order, by urgency plus waiting |
| `smart_digest_send` | 0131 | The morning, afternoon and night briefings |

**Admin portal: Workspace widgets** (contract in [WIDGETS.md](WIDGETS.md)):
`workspace_save`, `workspace_numbers`, `workspace_risk`, `workspace_team`,
`workspace_activity`, `workspace_find`, `workspace_photos`, `workspace_alarm_db`,
`poll_vote`, `shift_checkin`, `shift_mood_totals`, `record_game_score` (0132).

**Tanod (app)**

| Function | Latest | Does |
|---|---|---|
| `accept_dispatch` / `reroute_dispatch` | 0002 / 0034 | Accept, or hand back with a reason |
| `set_dispatch_step(dispatch, step)` | 0069 | On the way / Arrived: logged and told to the resident |
| `post_dispatch_update(dispatch, body, media)` | 0069 | A note (with photos) in the window's thread |
| `request_escalation(dispatch, reason, office)` | 0073 | Ask the admin to escalate |
| `submit_field_report(dispatch, text)` | 0073 | Resolve: waits for the admin's approval |
| `update_my_location(lat, lon)` | 0072 | One fix at key moments only; no history kept |
| `request_retirement` | 0052 | — |

**Resident (app)**

| Function | Latest | Does |
|---|---|---|
| `file_report(…)` | 0066 | File a complaint (safe to resend from the offline outbox) |
| `cancel_report`, `request_reopen`, `request_appeal`, `submit_additional_details` | 0023–0065 | — |
| `follow_up_report(report, message)` | 0072 | Follow up once the date has passed; once a day |
| `post_report_message(report, body)` | 0072 | Ask the barangay |
| `submit_id_reading(…)` | 0126 | Send what the phone's OCR read from the ID (the server judges it) |
| `request_account_deletion()` | 0045 | Delete one's own account (finished by the `delete-account` function) |
| `public_incidents()` | 0073 | Published incidents: category, status, place only |

---

## Scheduled jobs (pg_cron)

Times in UTC; Philippine time is UTC+8.

| Job | Schedule | Does |
|---|---|---|
| `sweep-overdue-verifications` | every 10 min | Flags registrations past the 2-hour review window |
| `sweep-unaccepted-dispatches` | every 5 min | A dispatch not accepted in time goes back to the system |
| `sweep-awaiting-units` | every 2 min | Re-offers jobs that found no free tanod, in SMART queue order (0129) |
| `sweep-overdue-reports` | every 15 min | One "overdue" alert per missed admin date: no automatic escalation (0072) |
| `sweep-admin-handovers` | hourly | Expires unanswered admin handovers (0055) |
| `smart-watch` | every 5 min | Urgent cases nobody dispatched, recurring problems, deadline risk, spikes, quiet cases |
| `smart-morning-digest` | 23:00 (07:00 PH) | The morning briefing to every admin |
| `smart-afternoon-digest` | 06:00 (14:00 PH) | The afternoon briefing |
| `smart-night-digest` | 12:00 (20:00 PH) | The night briefing |
| `system-health` | hourly at :05 | Failed jobs, database past 80% of 500 MB, cleanup misses, function failures → `system_alerts` |
| `keep-portal-awake` | every 10 min | Pings the portal and records uptime; two misses alert every admin |
| `purge-old-notifications` | daily 03:20 | Read notifications after 90 days, any after a year (0115) |
| `media-cleanup` | daily 03:40 | Calls the `media-cleanup` function with the secret from Vault (0118) |

`dashboard_metrics` is deliberately **not** definer: RLS still decides which
reports are counted.

---

## The rules behind the schema

- **Every dispatch is the admin's** (0070). Nothing is dispatched at filing.
  The system only re-offers a job when a tanod hands it back, does not accept
  in time, or retires (`redispatch_report` → `auto_dispatch`), and since 0128
  picks a free tanod over the nearest busy one.
- **One handler per case** (0087). The first admin to act on a case (or Take
  this case) handles it; only the handler can act until they release it or
  another admin takes it over with a reason. Enforced by triggers on everything
  an admin action writes; residents, tanods and the scheduled jobs are
  untouched. `reports.version` stops an action from a stale page.
- **A tanod holds at most five dispatches** (0100/0101, `max_active_dispatches`).
- **Extensions are capped** (0079). The date can move later only
  `max_deadline_extensions` times, each with a reason; then the case goes to a
  higher official.
- **The admin sets the deadline** (0071). No date exists until the admin
  assigns; the category's `resolution_hours` is only a guide on the form.
- **A resolution waits for approval** (0073). `submit_field_report` finishes the
  tanod's dispatch; the complaint stays In Progress until `approve_resolution`.
- **Escalation is layered** (0130). Up the barangay: the kagawad who chairs the
  right committee, then the chairman, each becoming the case's handler; or out
  to another office (VAWC desk, PNP, DSWD…), which closes the case here with
  `referred_to` set (0072/0073).
- **Sensitive cases** (0130). VAWC and domestic-violence complaints are marked
  on filing, kept out of the dispatch waiting line, and can go to a designated
  woman responder. The mark is its own status in the portal, shown
  beside the lifecycle status (`reports.status` is unchanged, so every step
  still applies) and filterable; it is never shown to the resident.
- **No live tracking.** A tanod's location is taken at key moments only (going
  on duty, returning to the app, each dispatch step, navigation start).
- **Photos stay in their folder** (0083): complaint photos in `reports/`, tanod
  proof in `dispatch/`, the barangay's in `barangay/`; identity photos are
  private (0117).
- **Soft delete only.** `reports.deleted_at`, never `DELETE`.
- **`geom` is generated** from `latitude`/`longitude`.
- **SMART only advises.** Its scores, flags and rankings never change a case on
  their own; an admin acts, and overrides are kept with their reasons.

Switched off, kept for later: OCR ID triage (`ID_OCR_ENABLED` in
`admin/includes/accounts.php`, `kIdOcrEnabled` in
`mobile/core/lib/src/id_ocr.dart`), SMS codes (`kSmsResetEnabled` in the app)
and admin succession (`ADMIN_SUCCESSION_ENABLED` in
`admin/includes/retirement.php`).

---

## Use case → schema coverage

The use cases in the project document are the spec.

| Use case | Backed by |
|---|---|
| Register Account | `users`, `handle_new_auth_user()`, `id_image_url`, `submit_id_reading()` |
| Verify User Account | `verify_user_account()`, `verification_due_at` (2 h), `smart_verify()` |
| Manage User Account | `set_account_suspension()`, `admin_update_user()`, `admin_reset_password()`, `profile_requests` |
| Submit Complaint Report | `file_report()`, `report_media`, `report_concerns`, `is_anonymous` |
| Track Complaint Status | `status_logs`, `report_messages`, `follow_up_report()` |
| View Geospatial Incident Heatmap | `reports.geom`, `report_hotspots()`, `hazard_zones` |
| View Statistical Analytics Dashboard | `dashboard_metrics()`, `smart_summary()` |
| Update Resolution Status | `admin_set_status()`, `set_concern_status()` |
| Upload Report Status to Admin | `post_dispatch_update()`, `set_dispatch_step()`, `submit_field_report()` |
| Update Availability Status | `users.duty_status`, `is_dispatchable`, `attendance` |
| Receive Dispatch Ticket | `dispatches`, `accept_dispatch()`, `reroute_dispatch()` |
| View Ticket Details | `admin_instructions`, `due_at`, `report_media`, `look_shares` |
| View Report Summary | `status_logs`, `dispatches`, `referred_to` |
| Validate Report | `review_report()`, `smart_case_card()` |
| Monitor Real-Time Map (admin) | `reports` realtime, `report_hotspots()` |
| Approve Complaint Resolution | `approve_resolution()`, `reject_resolution()` |
| Monitor Complaint Status | `due_at`, `overdue_notified_at`, `smart_queue()` |
| Manage Escalation Request | `escalation_requests`, `approve_escalation()`, `deny_escalation()`, `escalate_in_barangay()` |
| Submit Feedback | `feedback` |
| View Emergency Service Hotline List | `hotline_groups`, `hotline_numbers` |
| Monitor Real-Time Map (resident) | `is_public`, `public_incidents()` |
| Log In | `check_login_lockout()`, `login_attempts`, `login_failure_sources` |

---

## Known gaps

1. The use-case document's dashboard use case still lists "Export Data to PDF";
   it was removed from the dashboard (Report Summary keeps its PDFs).
2. Submit Feedback's "resend after reconnecting" is not built; a failed
   submission asks the resident to try again.
3. The admin ↔ tanod chat beyond a dispatch's own thread is a plan only:
   `docs/chat/admin_tanod_chat_draft.sql`.
4. Panel asks still open (filter by type within a category, the resident app
   showing each concern's status): see [DEFENSE_ASKS.md](DEFENSE_ASKS.md).
