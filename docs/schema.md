# SmartSumbong — Schema Reference

Mirrors `supabase/migrations/`. If the manuscript's Data Dictionary and this
file disagree, one of them is wrong — fix both in the same sitting.

Actor naming is **`tanod`** throughout, per the panel revision. The string
"responder" should not appear anywhere in this codebase.

---

## Tables

All thirteen exist in `supabase/migrations/`. The right-hand column tracks the
manuscript's Data Dictionary, which still documents only four of them — that gap
is a writing task, not a build task.

| Table | Purpose | In the manuscript DD? |
|---|---|---|
| `users` | Accounts, roles, verification, duty status, last position | Yes — DD lacks the verification, duty and location columns |
| `reports` | Complaints, location, SLA, escalation | Yes — DD lacks `due_at`, `escalated_at`, `escalation_level`, `reopened_count`, `geom`, `awaiting_unit_since`, `dispatch_attempts` |
| `report_media` | Resident photos (multiple, 10 MB combined) | **No — add** |
| `dispatches` | Assignment, accept/reroute, field report | Yes — DD lacks the accept clock and reroute columns |
| `dispatch_media` | Tanod photo proof | **No — add** |
| `status_logs` | Append-only audit trail | Yes |
| `feedback` | Post-resolution rating | **No — add** |
| `attendance` | Tanod duty logging | **No — add** |
| `notifications` | In-app alerts (`is_read`, not a `read_at` timestamp) | **No — add** |
| `sla_policies` | Per-category response windows, plus `auto_dispatch_on_file` | **No — add** |
| `sla_extensions` | Audited deadline extensions | **No — add** |
| `barangay_boundary` | OSM relation 2988704 as a PostGIS polygon, for jurisdiction checks | **No — add** |
| `operational_settings` | Single row: attempt cap, location freshness, awaiting-unit alert. Barangay-owned, not developer-owned | **No — add** |

Nine of thirteen tables are absent from the current Data Dictionary. That is what
Austria's comment ("ensure all tables are included in the ERD") actually requires.

`emergency_alerts` is deliberately **not** present. The emergency feature was cut
from scope by unanimous panel direction. Do not reintroduce it.

---

## Functions the portal calls

Every state change goes through one of these rather than a bare `UPDATE`, so the
status, the audit trail and the notification move in one transaction. Most are
`security definer` because `notifications` has no insert policy by design —
nobody writes their own alerts.

| Function | Migration | Used by |
|---|---|---|
| `review_report(report, decision, remark)` | 0011 | Accept / Deny on the case screen |
| `set_resolution_target(report, due)` | 0011 | "Target date resolution" field |
| `tanod_roster(report)` | 0011 | The assign list — everyone, with ONLINE/OFFLINE |
| `assignable_tanods(report)` | 0009 | Authoritative "who may take this" |
| `admin_dispatch(report, tanod, instructions)` | 0009 | Dispatch button |
| `auto_dispatch(report)` | 0005/0007 | Fires on filing for flagged categories |
| `accept_dispatch` / `reroute_dispatch` / `submit_field_report` | 0002/0006/0008 | Tanod mobile app |
| `dashboard_metrics(from, to)` | 0012 | Every figure on the dashboard, one call |

`dashboard_metrics` is deliberately **not** definer: it runs with the caller's
rights, so RLS still decides which reports are counted.

---

## Use case → schema coverage

| Use case | Backed by |
|---|---|
| Register Account | `users`, `verification_status`, `id_image_url` |
| Verify User Account | `verification_submitted_at`, `verification_due_at` (**2 h max**), `verified_by` |
| Manage User Account | `is_suspended`, `suspended_reason` |
| Submit Complaint Report | `reports`, `report_media`, `is_anonymous`, `geom` |
| Track Complaint Status | `status_logs` timeline, `deleted_at` soft delete |
| View Geospatial Heatmap | `reports.geom` + GiST index |
| View Statistical Dashboard | `escalation_level`, `resolved_at`, `category` |
| Update Resolution Status | `reports.status`, `status_logs` |
| **Assign Tanod** | `dispatches.assigned_by`, `assigned_at`, `admin_instructions` |
| **Receive Dispatch Ticket** | `accept_due_at`, `accepted_at`, `is_primary` |
| **Accept Dispatch** | `accept_dispatch()` |
| **Reroute Dispatch** | `reroute_dispatch()`, `reroute_reason`, `rerouted_to` |
| **Update Availability Status** | `duty_status`, `is_dispatchable`, `attendance` |
| Upload Report Status | `field_report_text`, `dispatch_media`, `submit_field_report()` |
| View Ticket Details | `admin_instructions`, `due_at` |
| **Manage SLA Deadline Extension** | `sla_extensions` |
| View Report Summary | `status_logs`, `attendance`, `feedback` |
| Escalated: Reopened Cases (Fig 18) | `reopened_count`, `reopen_report()` |
| Escalated: Missed Deadline (Fig 19) | `due_at`, `escalated_at`, `sweep_overdue_reports()` |

Bold rows exist in the updated use case diagrams but **not** in the Chapter III
Data Dictionary. They are the gap between the diagrams and the manuscript.

---

## The three SLA clocks

| Clock | Column | Limit | Swept by |
|---|---|---|---|
| Account verification | `users.verification_due_at` | **2 hours** (panel: Mandigma) | `sweep_overdue_verifications()` every 10 min |
| Dispatch acceptance | `dispatches.accept_due_at` | `sla_policies.accept_minutes` | `sweep_unaccepted_dispatches()` every 5 min |
| Complaint resolution | `reports.due_at` | `sla_policies.resolution_hours` | `sweep_overdue_reports()` every 15 min |

Windows live in `sla_policies` as data, so the barangay can tune them without a
migration. **The seeded values are placeholders and need barangay sign-off.**
The captain's 30–45 days refers to Katarungang Pambarangay mediation, not to
digital response targets — do not conflate them.

---

## Deliberate design decisions

**Soft delete only.** `reports.deleted_at` instead of `DELETE`. An accountability
system whose audit trail has holes cannot substantiate its own claims.

**Enums over free TEXT.** Category and status are enumerated types, so the seven
documented categories are enforced by Postgres rather than by convention.

**Tanod act through functions, not UPDATE.** `accept_dispatch()`,
`reroute_dispatch()` and `submit_field_report()` are `SECURITY DEFINER`. A tanod
cannot silently rewrite a dispatch row; every transition writes a `status_logs`
entry in the same transaction.

**Reroute cannot exist without a reason.** Enforced by CHECK constraint, matching
the UI's "This action cannot be undone and will be logged."

**`geom` is generated.** Derived from `latitude`/`longitude`, so the two can never
drift apart. `FLOAT8` alone cannot serve `ST_DWithin` or the heatmap.

---

## Known mismatches to resolve

1. **Ticket format.** Mockups show `# 42345`; the DD specifies `BRG-YYYY-NNNN`.
   The migration implements `BRG-YYYY-NNNN`. The UI needs updating, or the DD does.
2. **Category naming.** Mockups show "Stray Animals"; Scope defines
   "Animal Welfare". The enum uses `animal_welfare`.
3. **Manuscript lag.** Chapter III documents 9 use cases; the current diagrams
   have 14. The manuscript understates the system.
4. **UC report PDF** still says "Barangay Responder" in its first three tables
   while every later table says "Barangay Tanod".
