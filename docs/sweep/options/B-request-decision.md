# B-request-decision: requests with a missing answer, deny or notice (decision per request)

Evidence: probe.py (who can request, who can decide, who is told back) and detector D3.

| Request | Asked by (probe) | Decided by (probe) | Requester told back? | Gap |
|---|---|---|---|---|
| reopen | resident | `reopen_report` (Kagawad, staff handling it, super; resolved and closed) and `admin_set_status` (resolved only) | `admin_set_status` tells the resident; `reopen_report` tells nobody | no decline; nothing calls `reopen_report`; see K-01 |
| appeal | resident | `appeal_report` (Kagawad, staff, super) | yes (resident) | the request notice has no report_id (0185) |
| more details | Kagawad, staff, super, tanod | the resident (`submit_additional_details`) | the asking admin and the tanod are told | no way to withdraw the request |
| forward flag | staff | `forward_case` (Kagawad, super) tells the receiving committee; `dismiss_forward_flag` not exercised by the fixtures | staff told on dismiss (from migration 0152 text, not probed) | none proven |
| retirement | tanod (and, oddly, staff: `request_retirement` succeeded for stf1/stf2) | `finalize_retirement` (super) tells the tanod; `endorse_retirement` not exercised | yes | confirm staff should not be able to request (a tanod function) |
| escalation | tanod | `approve_escalation` / `deny_escalation` (Kagawad, staff, super) | yes (tanod, resident on approval) | none |
| profile change | resident | `decide_profile_request` (super only) tells the resident | yes | the request function could not be probed (argument shapes), nothing found |
| ocr rescan | super only (`request_ocr_rescan`) | none (the resident re-uploads) | resident sees a banner | by design; a Kagawad cannot ask |

Options per row: (1) leave, (2) add the missing notice only (class A once the kind and wording exist), (3) add a decline/withdraw function (migration + a button: class C).
**Recommended**: reopen/appeal as K-01; the rest leave.
