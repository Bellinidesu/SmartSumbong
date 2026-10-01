-- 0076 — An "Others" complaint category (Rose, mock defense feedback,
-- 2 Oct 2026). The barangay's Complaint Summary form has an "Others" row
-- and the portal's category dropdowns should offer it; until now a
-- complaint that fit none of the seven had nowhere to go.
--
-- A new enum value cannot be used in the transaction that adds it, so its
-- deadline rule is 0077.

alter type public.complaint_category add value if not exists 'other';
