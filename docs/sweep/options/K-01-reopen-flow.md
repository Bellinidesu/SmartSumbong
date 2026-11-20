# K-01: reopen and appeal, three options (nothing applied; Ace picks)

## What the probes proved (throwaway database, real roles; `tools/sweep/probe.py`)

- `request_reopen` (resident, owner only, resolved or closed case) and `request_appeal` insert **one notice per active administrator with no `report_id`**.
  Six admins were told; **four of them cannot open the case** (the other committee's Kagawad, both staff, the captain sees all): `_notifications_scope` only filters
  notices that carry a `report_id`. No Review button for anyone (no case to link).
- `reopen_report(case, reason)` works: a **Kagawad of the case's committee, a staff member handling it, and a super admin** all reopened a *resolved* and a *closed* case
  (status goes to `validated`). **Nothing calls it** (no portal page, no app screen, no function). Resident, tanod, other committee, captain: refused.
- `admin_set_status` refuses closed/archived, so the portal's status control cannot reopen a closed case either.
- The resident gets **no answer**: neither `request_reopen` nor `reopen_report` writes a notice back to the resident (the status change itself notifies them as a normal status
  change, but a *declined* request leaves no trace at all, because no decline path exists). `appeal_report` (rejected -> validated) is the same shape.
- `archived` and `cancelled` are dead ends for everyone (by design for cancelled).

## Option A: fix the notice and the reach, let the existing status control reopen (smallest honest fix)

- **Change**: draft **0185** (already proven): the two request functions carry `report_id`, so only admins who can open the case are told, with a Review link.
  Add to `admin_set_status` the closed -> validated move for the roles `reopen_report` already allows, so the case page's status control can reopen a closed case.
- **Per role**: resident unchanged (asks, waits); Kagawad of the committee, staff handling it, super: get the notice with a Review link, can reopen from the existing status
  control; other committees and unassigned staff: no longer told; captain: told (sees all), cannot act (view-only).
- **Still missing**: a decline/answer to the resident. **Cost**: one small migration; no screen change if the status control already lists the move (else a label: class C).
- **Recommended** only as step 1 of B.

## Option B: a real reopen action with an answer to the resident (complete flow)

- **Change**: 0185 plus: a portal action on the case page "Reopen" / "Decline request" wired to `reopen_report()` and a new `decline_reopen(case, reason)`; both write a notice
  to the resident ("Your request to reopen TRACKING-ID was accepted / declined: reason") with `report_id` so the app opens the case. Same for appeals (`appeal_report`).
- **Per role**: resident gets a visible answer either way; Kagawad/staff/super get a two-button request card on the case page; others unchanged. The decline also closes the
  request (a status-log remark prefix both sides recognise).
- **Cost**: 1 migration (decline function + notice kinds + test) and **a button and a card = a look change = class C** (waits for Rose); the app needs one label per new notice.
- **Recommended**: yes, this is the version a barangay can actually run. Do A now (it is safe and unblocks the notice), B when the front-end sweep reaches the case page.

## Option C: minimal (fix notice and visibility only; no new action)

- **Change**: only 0185. Reopening stays an administrator task done outside the portal (database/support), and the resident is told in the app copy that requests are
  answered at the counter.
- **Per role**: as A without the status-control change; nobody can reopen from the portal.
- **Cost**: nothing more. **Risk**: the request button in the app promises something the portal cannot deliver; requests pile up unanswered.
- **Recommended**: no, except as a stop-gap for the defence.
