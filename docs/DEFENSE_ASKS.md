# What the capstone panel asked for

The panel's requests at the Project Capstone Tool Defense of 7 September 2026
(Group 12; panel: Mr. Mandigma, Ms. Usero, Mr. Austria), and where each
stands. Migration 0130 and the portal work of 14 October answer most of them.
Check new work against this list: these are the conditions for the final
defense.

Status as of 17 October 2026.

| # | The panel asked | Status | Where |
|---|---|---|---|
| 1 | **Case Reports lists only real cases**, not general notifications (a filter or a separate tab) | Done | Case Reports' tabs; notifications have their own page |
| 2 | **Pagination everywhere** ("no scroll scroll"): case reports, the activity timeline, the report ledger, the map's sample lists | Done | the pager on Case Reports, Activity, Report Summary, the case page, Residents, Personnel |
| 3 | **Several categories per report** (e.g. Barangay service: delayed response *and* duty negligence), also when a case is raised again, each resolved or reviewed on its own | Done | `report_concerns`, `add_report_concern`, `set_concern_status` (0130); the case page |
| 3a | …and filtering by the specific type under a category (e.g. under Street obstruction) | Open | |
| 3b | …and the resident seeing each concern's own status in the app | Open | the app shows the complaint's status |
| 4 | **Anonymous reports**: the resident stays identifiable to the barangay, and the barangay can still talk to them | Open | the case page shows "Anonymous"; whether admins see the identity is the barangay's call |
| 5 | **Name changes by request only** (anti-tampering), and a **feedback form after completion** | Done (both existed) | `profile_requests` (0086); `feedback` |
| 6 | **Layered escalation**: Tanod → Kagawad (by committee) → Chairman, with the organisational structure defined first; the secretary operates the portal (the barangay has no IT admin); Kagawad and Chairman have accounts | Done | official roles and committees, `escalate_in_barangay` and `return_from_official` (0130); Settings → Administrators |
| 6a | Dispatch optional, never automatic | Done | every dispatch is the admin's (0070) |
| 6b | Sensitive cases (VAWC, domestic violence) need elevation and a female tanod option | Done | `set_case_sensitive`, designated women responders (0130) |
| 7 | Notify residents from the heat map? (today only the admin sees it) | To ask the barangay | |
| 8 | Meet the barangay captain after the defense | To schedule | |

Related work since, which the panel did not ask for but which supports items
3 and 6: the SMART engine (urgency, duplicates, routing, the queue;
[SMART.md](SMART.md)) and its screens on the case page, Case Reports, the
dashboard, the roster, the map, Notifications and Settings
([SMART_SCREENS.md](SMART_SCREENS.md), which also lists what is not on screen
yet).

When an item changes, update its row here in the same pull request.
