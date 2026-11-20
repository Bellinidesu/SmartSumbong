# B-role-symmetry: pages that open for a rung whose actions are refused (decision per item)

Evidence: probe.py role x action matrix against `admin/includes/access.php` and docs/ROLES_AND_PAGES.md; loadcost.py replay (refused calls per role).

- Kagawad and staff pages call `smart_deadline_risk` (and four other `smart_*` reads) that are refused to them on 20+ pages; each is an optional call so nothing breaks, but it is a wasted
  request per page (briefing.php, dashboard.php, spatial.php). Options: (1) stop requesting them unless the tier is super/captain (portal change, class C-ish: no visual change);
  (2) let committees read their own slice (new function: product decision).
- Case page: committee may open it but `flag_case_for_forward` is refused (a Kagawad forwards directly); staff cannot assign/forward/take/take over: by design (doc 0175) and the page hides them.
- Doc contradictions the probe found are listed in the baseline report; each is either a doc fix (class A) or a rule change (needs Ace).
