# SmartSumbong — Schema Reference

Mirrors `supabase/migrations/` (0001–0107; there is no 0048, the number was
skipped). The tables and functions below were last checked against 0087
(5 October 2026), plus the 0107 additions. If the manuscript's Data Dictionary and this file
disagree, one of them is wrong — fix both in the same sitting.

Actor naming is **`tanod`** throughout, per the panel revision.

---

## Tables (28)

| Table | Purpose | Since |
|---|---|---|
| `users` | Accounts, role, verification, suspension, retirement, duty status, last known location | 0001 |
| `reports` | Complaints: category, place (`geom`), status, admin-set `due_at`, referral (`referred_to`…), follow-ups, resolution awaiting approval, `is_public` | 0001 |
| `report_media` | Resident photos and video | 0001 |
| `status_logs` | Append-only, hash-chained audit trail (0015); one writer per complaint, checked with `verify_report_trail` (0082) | 0001 |
| `feedback` | Post-resolution rating and comment | 0001 |
| `attendance` | Tanod duty logging | 0001 |
| `notifications` | In-app alerts, pushed to phones (`is_read`) | 0001 |
| `sla_policies` | Per-category guide hours and the tanod's accept window | 0001 |
| `dispatches` | Assignment, accept, reroute, step (On the way / Arrived), field report | 0002 |
| `dispatch_media` | Tanod photo/video proof; `update_id` tags photos sent in the thread (0069) | 0002 |
| `sla_extensions` | Audited deadline extensions | 0002 |
| `barangay_boundary` | OSM relation 2988704 as a PostGIS polygon | 0005 |
| `operational_settings` | Single row: attempt cap, location freshness, alert thresholds | 0010 |
| `account_audit` | Hash-chained log of account changes | 0014 |
| `hotline_groups`, `hotline_numbers` | The resident app's emergency hotline list | 0025 |
| `login_attempts` | Lockout after repeated failures | 0031 |
| `login_failure_sources` | Failed sign-ins reported per network address, 15-minute window; past 20 they stop counting toward a lockout | 0107 |
| `device_tokens` | FCM push tokens | 0035 |
| `retirement_requests` | A tanod's request to retire, and the admin's decision | 0052 |
| `detail_requests` | "More details needed" asked of the resident, and the answer | 0065 |
| `dispatch_updates` | The dispatch window's thread: tanod notes, admin replies, steps | 0069 |
| `report_messages` | "Ask the barangay": a complaint's resident ↔ barangay thread | 0072 |
| `escalation_requests` | A tanod's request to escalate, and the admin's decision | 0073 |
| `password_otps` | SMS reset codes, hashed (0085; sending is switched off until Semaphore credits) | 0085 |
| `case_handler_log` | Admins taking, releasing and taking over cases (Activity page) | 0087 |
| `profile_requests` | A resident's or tanod's name change or new ID photo, and the admin's decision | 0086 |
| `report_evidence` | Photos the barangay attaches from the portal: with an update, or when it resolves | 0079 |

Removed: `tanod_locations` (live tracking history, dropped in 0072), the
public transparency functions (0043 → removed). `emergency_alerts` was never
built: the emergency feature is out of scope by panel direction.

---

## Functions, by who calls them

Every state change goes through a function rather than a bare `UPDATE`, so the
status, the audit trail and the notification move in one transaction. Most are
`security definer` because `notifications` has no insert policy by design.

**Admin portal**

| Function | Latest | Does |
|---|---|---|
| `review_report(report, decision, remark, abusive)` | 0040 | Validate / Reject Report |
| `admin_dispatch(report, tanod, instructions)` | 0071 | Assign a tanod — requires a target date and instructions |
| `set_resolution_target(report, due, reason)` | 0079 | Set the target date; the resident is told it. Moving it later is an extension: needs a reason, recorded in `sla_extensions`, capped by `max_deadline_extensions` (2) |
| `hand_to_higher_official(report, official, note)` | 0079 | Once the extensions are used up: hand the case to a barangay official; any tanod stands down; a fresh allowance starts |
| `admin_barangay_update(report, body, media)` | 0079 | An update with photos to the timeline and the resident, no tanod needed |
| `admin_reroute_dispatch(dispatch, reason, to)` | 0070 | Move a live dispatch to a tanod or back to the system |
| `approve_resolution(report)` / `reject_resolution(report, reason)` | 0073 | Approve the tanod's resolution, or return it |
| `admin_set_status(report, status, remark, media)` | 0079 | In Progress / Offline Investigation / Resolved, with proof photos |
| `refer_report(report, office, note)` | 0073 | Escalate to an outside office (closes the case here) |
| `approve_escalation` / `deny_escalation` | 0073 | Decide a tanod's escalation request |
| `set_report_public(report, public)` | 0073 | Show on residents' map |
| `post_dispatch_update` / `post_report_message` | 0069 / 0072 | Reply to the tanod / to the resident |
| `request_additional_details(report, message)` | 0065 | Ask the resident for more |
| `appeal_report(report, remark)` / `reopen_report(report, reason)` | 0071 | Grant an appeal / reopen — both clear the date |
| `verify_user_account`, `set_account_suspension`, `admin_reset_password`, `admin_update_user` | 0013–0073 | Accounts |
| `finalize_retirement` | 0052 | Retirement requests |
| `promote_to_admin`, `step_down_as_admin`, `cancel_admin_handover` | 0014–0055 | Admin succession (portal switch off: `ADMIN_SUCCESSION_ENABLED`) |
| `account_directory`, `tanod_roster`, `dashboard_metrics`, `report_hotspots`, `resident_abuse_reports`, `retirement_requests_queue` | — | Reads for the screens |

**Tanod (app)**

| Function | Latest | Does |
|---|---|---|
| `accept_dispatch` / `reroute_dispatch` | 0002 / 0034 | Accept, or hand back with a reason |
| `set_dispatch_step(dispatch, step)` | 0069 | On the way / Arrived — logged and told to the resident |
| `post_dispatch_update(dispatch, body, media)` | 0069 | A note (with photos) in the window's thread |
| `request_escalation(dispatch, reason, office)` | 0073 | Ask the admin to escalate |
| `submit_field_report(dispatch, text)` | 0073 | Resolve — waits for the admin's approval |
| `update_my_location(lat, lon)` | 0072 | One fix at key moments only; no history kept |
| `request_retirement` | 0052 | — |

**Resident (app)**

| Function | Latest | Does |
|---|---|---|
| `file_report(…)` | 0066 | File a complaint (safe to resend from the offline outbox) |
| `cancel_report`, `request_reopen`, `request_appeal`, `submit_additional_details` | 0023–0065 | — |
| `follow_up_report(report, message)` | 0072 | Follow up once the date has passed; once a day |
| `post_report_message(report, body)` | 0072 | Ask the barangay |
| `public_incidents()` | 0073 | Published incidents: category, status, place only |

**Scheduled (pg_cron)**

| Job | Every | Does |
|---|---|---|
| `sweep_overdue_verifications()` | 10 min | Flags registrations past the 2-hour review window |
| `sweep_unaccepted_dispatches()` | 5 min | A dispatch not accepted in time goes back to the system |
| `sweep_awaiting_units()` | 2 min | Retries the system's reroute when no tanod was free |
| `sweep_overdue_reports()` | 15 min | One "overdue" alert per missed admin date — no automatic escalation (0072) |

`dashboard_metrics` is deliberately **not** definer: RLS still decides which
reports are counted.

---

## The rules behind the schema

- **Every dispatch is the admin's** (0070). Nothing is dispatched at filing.
  The system only re-offers a job when a tanod hands it back, does not accept
  in time, or retires (`redispatch_report` → `auto_dispatch`).
- **One handler per case** (0087). The first admin to act on a case (or Take this case) handles it; only the handler can act until they release it or another admin takes it over with a reason. Enforced by triggers on everything an admin action writes; residents, tanods and the scheduled jobs are untouched. `reports.version` lets the portal stop an action from a stale page.
- **Extensions are capped** (0079). The date can move later only `max_deadline_extensions` times, each with a reason; then the case goes to a higher official.
- **The admin sets the deadline** (0071). No date exists until the admin
  assigns; the category's `resolution_hours` is only a guide on the form.
- **A resolution waits for approval** (0073). `submit_field_report` finishes
  the tanod's dispatch; the complaint stays In Progress until
  `approve_resolution`.
- **Escalation means going outside** (0072/0073): VAWC desk, PNP, DSWD… by the
  admin directly or on a tanod's request. The complaint closes here with
  `referred_to` set.
- **No live tracking.** A tanod's location is taken at key moments only (going
  on duty, returning to the app, each dispatch step, navigation start).
- **Photos stay in their folder** (0083): complaint photos in `reports/`, tanod proof in `dispatch/`, the barangay's in `barangay/`.
- **Soft delete only.** `reports.deleted_at`, never `DELETE`.
- **`geom` is generated** from `latitude`/`longitude`.

Switched off, kept for later: OCR ID triage (`ID_OCR_ENABLED` in
`admin/includes/accounts.php`, `kIdOcrEnabled` in
`mobile/core/lib/src/id_ocr.dart`) and admin succession
(`ADMIN_SUCCESSION_ENABLED` in `admin/includes/retirement.php`).

---

## Use case → schema coverage

The use cases in the project document are the spec.

| Use case | Backed by |
|---|---|
| Register Account | `users`, `handle_new_auth_user()`, `id_image_url` |
| Verify User Account | `verify_user_account()`, `verification_due_at` (2 h) |
| Manage User Account | `set_account_suspension()`, `admin_update_user()`, `admin_reset_password()` |
| Submit Complaint Report | `file_report()`, `report_media`, `is_anonymous` |
| Track Complaint Status | `status_logs`, `report_messages`, `follow_up_report()` |
| View Geospatial Incident Heatmap | `reports.geom`, `report_hotspots()` |
| View Statistical Analytics Dashboard | `dashboard_metrics()` |
| Update Resolution Status | `admin_set_status()` |
| Upload Report Status to Admin | `post_dispatch_update()`, `set_dispatch_step()`, `submit_field_report()` |
| Update Availability Status | `users.duty_status`, `is_dispatchable`, `attendance` |
| Receive Dispatch Ticket | `dispatches`, `accept_dispatch()`, `reroute_dispatch()` |
| View Ticket Details | `admin_instructions`, `due_at`, `report_media` |
| View Report Summary | `status_logs`, `dispatches`, `referred_to` |
| Validate Report | `review_report()` |
| Monitor Real-Time Map (admin) | `reports` realtime, `report_hotspots()` |
| Approve Complaint Resolution | `approve_resolution()`, `reject_resolution()` |
| Monitor Complaint Status | `due_at`, `overdue_notified_at` |
| Manage Escalation Request | `escalation_requests`, `approve_escalation()`, `deny_escalation()` |
| Submit Feedback | `feedback` |
| View Emergency Service Hotline List | `hotline_groups`, `hotline_numbers` |
| Monitor Real-Time Map (resident) | `is_public`, `public_incidents()` |
| Log In | `check_login_lockout()`, `login_attempts` |

---

## Known gaps

1. The use-case document's dashboard use case still lists "Export Data to PDF";
   it was removed from the dashboard (Report Summary keeps its PDF).
2. Submit Feedback's "resend after reconnecting" is not built; a failed
   submission asks the resident to try again.
3. The admin ↔ tanod chat is a plan only: `docs/chat/admin_tanod_chat_draft.sql`.
