-- =============================================================
-- SmartSumbong — 0159 The Barangay Anti-Drug Abuse Council is not created for Barangay 183
--
-- Ace, 1 Nov 2026, from the chairmanship document the barangay gave the team: three committees are active (Peace and Order /
-- Human Rights / Transportation and Communication; Environmental Protection / Barangay Disaster Risk Reduction Management;
-- Health and Sanitation) and the Barangay Anti-Drug Abuse Council is crossed out with the others. 0145 had left it on.
--
-- Switched off, not deleted: "off" is "not created" (0145), so nobody can be put in it, it leaves every list and chip, and
-- anything already filed with it keeps its name. A super admin switches it back on in Administrative Services > Committees.
-- Idempotent: running it again changes nothing.
-- =============================================================

update public.committees
   set active = false, updated_at = now()
 where key = 'anti_drug' and active;
