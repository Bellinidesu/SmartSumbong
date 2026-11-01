# SmartSumbong — Schema Reference

What the migrations in `supabase/migrations/` add up to: 128 files, 0001–0135
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
| `reports.committee`, `reports.awaiting_placement` | The committee a case was forwarded to (null: its category's committee), and whether a Kagawad handed it to the super admins to place; changed only by forwarding (0152) | 0152 |
| `case_forwards` | Every forward, staff flag and dismissed flag of a case: from and to which committee, the note, who, when; append-only. The view `case_forward_flags` lists the flags still open | 0152 |
| `committees` | The barangay's committees, made and edited by a super admin; switched off = not created (0145). For 183: Peace and Order, Environment and Disaster Risk, Health and Sanitation (the Anti-Drug Abuse Council is off, 0159) | 0145 |
| `committees.colour` | Each committee's colour, chosen by a super admin; its admins' sidebar wears it; no two active committees, and no committee and the super admins, may be close (0150) | 0150 |
| `committee_categories` | The categories each committee sees (the super admin's ticks) | 0145 |
| `app_releases` | Published versions of the app for the self-updater (https link, SHA-256, notes in English and Tagalog, must update, active); read only by a super admin, written only by the release functions | 0161 |
| `preview_sessions`, `preview_attempts` | A super admin's pairings with a phone (the code kept hashed, a secret channel, an expiry) and the wrong codes a person has tried; written only by the preview functions | 0160 |
| `committee_for_category` | The committee that usually takes each kind of complaint (editable defaults) | 0130 |
| `barangay_profile.super_colour` | The one colour every super admin's sidebar wears, branding blue by default (0150) | 0150 |
| `wording` | The barangay's own wording for a label of the portal or the app, keyed by the English text the code carries (null keeps the code's own); read before signing in, edited by a super admin in Settings > Wording | 0149 |
| `barangay_profile` | The barangay's name, place and seal (null: the one shipped), one row edited by a super admin in Settings > Appearance; readable before signing in | 0148 |
| `complaint_categories` | The complaint categories, edited by a super admin: English and Tagalog names, colour, map symbol, order, on or off; each key is a value of the `complaint_category` type | 0146 |
| `complaint_options` | The options residents pick under each category (the one picked lands in `reports.subject`); switched off, never deleted | 0146 |
| `look_shares` | "Look around" sent to a tanod: a note, the street image, which way the spot lies | 0107 |

### People and accounts

| Table | Purpose | Since |
|---|---|---|
| `users` | Accounts, role, official role and committee (0130), an administrator's tier (super, committee, moderator since 0151, captain) and developer mark (0145), verification, suspension, retirement, duty status, last known location | 0001 |
| `account_audit` | Hash-chained log of account changes | 0014 |
| `attendance` | Tanod duty logging | 0001 |
| `tanod_committees` | The committees a tanod belongs to: proposed by a Kagawad or approved by a super admin, with the committee's own role for them; written only by the functions. `tanod_committee_log` keeps every change (append-only) | 0153 |
| `inbox_messages` | The portal's Inbox: one row per recipient (a batch per message sent), from a person or the system (sender null), optionally about a case; read by its sender and recipient only | 0155 |
| `reroute_questions` | A reroute that found none of the case's committee's tanods free asks its Kagawad: open until answered, timed out or no longer needed | 0155 |
| `users.banner_preset`, `banner_colour`, `banner_url`, `banner_y` | An administrator's profile banner: sidebar colour, contour, a colour, the committee's, or their own picture and its framing | 0157 |
| `retirement_requests.endorsed_by`, `endorsed_at`, `endorse_note` | The tanod's Kagawad endorses a retirement request to the super admins, who decide | 0157 |
| `admin_punches` | When a Kagawad or staff member signed in to and out of the portal, for the punch card; append-only | 0153 |
| `device_tokens` | FCM push tokens | 0035 |
| `web_push_subscriptions` | Browsers with alerts on: push service address and keys, one row per browser, ten per person | 0136 |
| `engine_jobs` | Work handed to the engine (`engine/`): ID photos to read, with tries and the last error | 0137 |
| `smart_events` | What SMART decided and what people did with it: picks, "was it fixed?" questions and answers; kept 180 days | 0140 |
| `command_modes`, `command_tags`, `command_words`, `command_checklist`, `command_place_kinds` | The command center's four modes, what each reads (depth on MMDA's flood gauge, fire and damage words), each mode's checklist, and the places a quake check or fire surroundings names | 0143 |
| `feature_switches` | Parts of the system that can be switched off without removing them (the Workspace and the command center ship off). Written only by `feature_set()` | 0144 |
| `command_sessions` | One command-center mode at a time: who turned it on (or SMART, by the auto switch), why, and the closing note | 0143 |
| `command_checks`, `command_place_checks`, `command_handovers` | Checklist ticks, places checked, and handovers (a note with the counts) of a session | 0143 |
| `command_state`, `command_reads`, `command_display_links` | The auto switch and "not now"; each report's reading, kept; hall display links (a hash of the secret only) | 0143 |
| `smart_work_orders` | A recurring problem kept as one permanent-fix item for the council, with its reports as evidence | 0142 |
| `smart_rule_versions` | Every version of SMART's scoring rules and word list, with who, when and why | 0141 |
| `resolution_checks` | "Naayos na ba? / Was it fixed?" asked of the resident when a case is resolved, and the answer | 0140 |
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
| `portal_uptime` | Every 10-minute check of `/admin/ping.php`, whether it answered, and the container's memory it reported (0138) | 0096 |
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
| `places` | Places and streets the portal and app search: OpenStreetMap (refreshed every 6 h) and the barangay's own; places only, never homes | 0134 |
| `place_kinds` | Kinds of place and the English and Tagalog words for each (botika, simbahan, palengke) | 0134 |
| `places_refresh` | The OpenStreetMap refresh's state: last request, mirror, last good count, last error | 0134 |
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
| `smart_read` | 0133 | How SMART read a text (word forms, spellings, negation); 0133 added the present tense, doubled words, stretched letters, English endings |
| `search_places(q, lat, lng, limit)` | 0135 | Places for what was typed: forgives shorthand, slips and accents; kind words list that kind nearest first; chains counted once |
| `place_save` / `place_remove` | 0134 | Admins: the barangay's own places (within 5 km of the hall) |
| `smart_verify`, `smart_verify_queue` | 0126 | ID checks on what was read from the ID (by the engine since 0137) |
| `engine_status` | 0137 | The engine: set up or not, read and waiting, could not read |
| `confirm_fix(report, fixed, note)` | 0140 | The resident answers "Was it fixed?" once, within 14 days; "no" tells the admins and queues a recheck |
| `smart_why_order(report)` | 0140 | A plain sentence (English and Tagalog) on why a report is where it is; the owner or an admin |
| `command_board`, `command_feed`, `command_suggest` | 0143 | The board of a mode (one envelope for all four), what happened, and SMART's suggestion with its reason |
| `command_start`, `command_handover`, `command_end`, `command_check`, `command_place_check`, `command_dismiss`, `command_set_auto` | 0143 | Turn a mode on (a reason) or off (a note), hand over, tick, mark a place, put a suggestion off, the auto switch |
| `admin_tier`, `is_super_admin`, `is_full_viewer`, `admin_can_write`, `admin_sees_category`, `admin_sees_case`, `admin_sees_report`, `admin_sees_dispatch` | 0145 | What the signed-in administrator may see and do (used by the access rules and the functions) |
| `committee_save`, `committee_set_categories`, `set_admin_access` | 0145 | A super admin makes or changes a committee, ticks the categories it sees, and sets an administrator's tier, committee and developer mark |
| `complaint_catalogue` | 0146 | The categories and their options, in order, for the app and the portal (`p_all`: a super admin also gets the ones switched off) |
| `propose_tanod_committee`, `decide_tanod_committee`, `remove_tanod_committee`, `tanod_pick_list`, `personnel_committees`; `account_directory` (scoped) | 0153 | A tanod's committees: a Kagawad proposes, a super admin approves; names to propose from; each tanod's committees as the caller may see them and the committee of the case they are on; a committee's admins list only their tanods |
| `latest_app_release`, `app_release_publish`, `app_release_set_active` | 0161 | The self-updater: everyone asks for the newest active release, a super admin publishes (link, SHA-256, notes, must update) or withdraws one; switch `app_updates` turns the offers off |
| `preview_start`, `preview_pair`, `preview_end` | 0160 | Live preview on a phone (developer mode, switch `live_preview`, off by default): a super admin gets a one-time code, the phone trades it for a secret channel, five wrong codes lock a person out for 15 minutes |
| `purge_old_records` | 0158 | The nightly retention purge (cron only) |
| `set_my_banner`, `endorse_retirement`; `retirement_requests_queue` (now with the endorsement) | 0157 | An administrator sets their banner; a Kagawad endorses their committee's tanod's retirement. A new Inbox message raises an `inbox_mail` alert |
| `dashboard_committees`, `dashboard_slice`, `smart_chart_notes`; `notification_committee(notification)` | 0156 | The Dashboard's super admin module, the box beside the donuts and the brain buttons; the committee of the case a notification is about, as a column. `_notifications_scope` keeps system alerts from a committee's admins |
| `send_mail`, `mail_recipients`, `mark_mail_read`; `answer_reroute_question`, `sweep_reroute_questions` (every minute) | 0155 | Mail along the ladder; a Kagawad picks a tanod for a reroute, or nobody answers in time and the nearest from any committee is sent. `auto_dispatch` tries the case's committee's tanods first on a reroute |
| `punch`, `punch_cards` | 0153 | The portal punches a Kagawad or staff member in and out; the cards the caller may see (sign-ins, sign-outs, cases touched per day) |
| `forward_case`, `flag_case_for_forward`, `dismiss_forward_flag`; `case_committee(report)` | 0152 | Forward a case (a super admin to a committee; a Kagawad to another committee or to the super admins), flag one for forwarding (staff, with the reason), keep it here; the committee a case is with, as a column the list can filter on |
| `admin_scoped`; `admin_can_write`, `set_admin_access`, `set_official_role` (positions set the tier) | 0151 | The moderator tier (staff, scoped to a committee); a position sets its tier; the decision functions refuse a moderator |
| `committee_save` (now with a colour), `_colour_clash`, `_committee_free_colour` | 0150 | A committee's colour, and what a colour is too close to; the triggers on `committees` and `barangay_profile` refuse a clash |
| `catalogue_fill` | 0147 | Gives every category a deadline and a first committee (copied from Others); the portal calls it right after making a category |
| `category_save`, `option_save` | 0146 | A super admin makes or changes a category (a new one is added to the `complaint_category` type) or an option |
| `feature_on`, `feature_set` | 0144 | Whether a part is on; an administrator turns one on or off. The command center's functions answer "off" when it is switched off |
| `command_hall`, `command_display_link_create`, `command_display_link_revoke`, `command_now` | 0143 | The hall display (counts only, by a link; anon may call it with a live link), its links, and the app's banner |
| `smart_roster_suggestion`, `smart_forecast`, `smart_fairness` | 0142 | Duty roster suggested by weekday and 3-hour block; the open cases a week ahead and the kinds expected; how the work is shared |
| `smart_workorder_create`, `smart_workorder_set` | 0142 | Open a work order from a recurring problem; move it open, planned, done or dropped |
| `smart_save_rules`, `smart_rollback`, `smart_rule_history`, `smart_replay` | 0141 | Change SMART's rules with a reason; roll back to a version; list the versions; try a change on recent reports without making it |
| `smart_engine_health`, `smart_pick_stats`, `smart_fix_stats` | 0140 | Is it running; how often SMART's top pick was taken; how many fixes residents confirmed |
| `auto_dispatch`, `redispatch_report`, `sweep_awaiting_units` | 0139 | The reroute queue: a reroute that finds no one waits in line (a day at most, and not past the cap on offers); "gave up" is said once; an identical system line within ten minutes is not written again |
| `smart_storm_mode`, `smart_deadline_risk`, `smart_spikes`, `smart_similar_cases` | 0127 | Foresight |
| `smart_word_suggestions`, `smart_teach_word`, `smart_stuck_cases`, `smart_time_patterns`, `smart_sla_scorecard` | 0128 | Learning and the scorecard |
| `smart_queue` | 0129 | Every open case in one order, by urgency plus waiting |
| `smart_digest_send` | 0131 | The morning, afternoon and night briefings |

**Admin portal: Workspace widgets** (contract in [WIDGETS.md](WIDGETS.md)):
`workspace_save`, `workspace_numbers`, `workspace_risk`, `workspace_team`,
`workspace_activity`, `workspace_find`, `workspace_photos`, `workspace_alarm_db`,
`poll_vote`, `shift_checkin`, `shift_mood_totals`, `record_game_score` (0132).

**Everyone: alerts** (each person's own; they apply to the app and the browser alike)

| Function | Latest | Does |
|---|---|---|
| `set_notification_mute(kind, muted)` | 0044 | One kind of alert off or on (`verification` cannot be muted) |
| `set_push_choices(scope, quiet_from, quiet_to, quiet_urgent)` | 0136 | Every case or only one's own; quiet hours (Manila) with urgent cases let through or not |
| `web_push_subscribe` / `web_push_unsubscribe` | 0136 | A browser's alerts on or off (push services only) |
| `push_test()` | 0136 | A test alert past every choice, once a minute; not kept in the inbox |
| `push_plan(notification)` | 0136 | Service role only: whether the owner's choices let a push through, and to which phones and browsers (`send-dispatch-push` calls it) |

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
| `purge-old-records` | daily, 03:30 Manila | Deletes what is past its retention period (`operational_settings.keep_*`, 0158); never the audit trail |
| `sweep-reroute-questions` | every minute | A reroute question past its wait sends the nearest tanod from any committee; one no longer needed closes (0155) |
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
| `engine-tick` | every minute | Files the engine's answers and hands it the next ID photos, with a link signed here (0137); off until Vault has its settings |
| `engine-jobs-purge` | daily 03:50 | Finished engine jobs after 30 days (0137) |

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
