-- =============================================================
-- SmartSumbong -- 0051 Surface id_type and suspended_reason through
--                     account_directory()
--
-- Two real gaps in the portal, both closed by exposing columns that
-- already exist on public.users -- no new schema, purely widening what
-- account_directory() (0013, extended by 0039/0040/0050) returns.
--
-- 1. id_type. The applicant's own selected document type (0019) has
--    been sitting on public.users the whole time, but account_directory()
--    never returned it -- includes/accounts.php's OCR Triage card could
--    only ever show what OCR *detected*, never what was actually picked
--    at signup, so there was no way to see a true selected-vs-detected
--    comparison side by side (flagged as a known gap in that file's own
--    comments since 5 Sep 2026).
--
-- 2. suspended_reason. set_account_suspension() (0013) has always taken
--    and stored a reason -- an admin cannot even submit a suspension
--    without one -- but account_directory() never returned it either.
--    The result: admin/includes/accounts.php's suspended-account panel
--    reads $p['rejection_reason'] instead (a copy-paste of the *denial*
--    panel just above it, which is a different column for a different
--    decision), so the reason an admin typed in has never actually been
--    shown back to them once saved. This also means self-service account
--    deletion (0045), which suspends the account and sets a specific,
--    recognisable suspended_reason ("Account deleted by the resident...")
--    so a reviewer could tell it apart from an ordinary suspension, has
--    never had anywhere to actually display that distinction -- a
--    self-deleted account and an admin-suspended one have looked
--    identical in the portal since 0045 shipped.
--
-- Same drop-first requirement 0039/0040/0050 all hit -- CREATE OR REPLACE
-- cannot add a column to an existing RETURNS TABLE function.
-- =============================================================

set search_path = public, extensions;

drop function if exists public.account_directory(user_role);

create or replace function public.account_directory(p_role user_role)
returns table (
  id                      uuid,
  full_name               text,
  email                   text,
  mobile_number           text,
  role                    user_role,
  verification_status     verification_state,
  is_suspended            boolean,
  duty_status             duty_state,
  id_image_url            text,
  selfie_url              text,
  rejection_reason        text,
  submitted_at            timestamptz,
  due_at                  timestamptz,
  minutes_left            integer,
  is_overdue              boolean,
  holding_incident        boolean,
  created_at              timestamptz,
  ocr_detected_type       id_document_type,
  ocr_flags               text[],
  ocr_extracted_name      text,
  ocr_extracted_number    text,
  abuse_strike_count      integer,
  ocr_processed_at        timestamptz,
  ocr_rescan_requested_at timestamptz,
  id_type                 id_document_type,
  suspended_reason        text)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name, u.email, u.mobile_number, u.role,
         u.verification_status, u.is_suspended, u.duty_status,
         u.id_image_url, u.selfie_url, u.rejection_reason,
         u.verification_submitted_at,
         u.verification_due_at,
         case when u.verification_status = 'pending' and u.verification_due_at is not null
              then (extract(epoch from (u.verification_due_at - now())) / 60)::integer
         end,
         u.verification_status = 'pending'
           and u.verification_due_at is not null
           and u.verification_due_at < now(),
         exists (select 1 from public.dispatches d
                  where d.tanod_id = u.id and d.state in ('assigned', 'accepted')),
         u.created_at,
         u.ocr_detected_type,
         u.ocr_flags,
         u.ocr_extracted_name,
         u.ocr_extracted_number,
         (select count(*)::integer from public.status_logs sl
           join public.reports r2 on r2.id = sl.report_id
          where r2.resident_id = u.id
            and sl.is_abusive = true
            and sl.new_status = 'rejected'),
         u.ocr_processed_at,
         u.ocr_rescan_requested_at,
         u.id_type,
         u.suspended_reason
    from public.users u
   where u.role = p_role
   order by (u.verification_status = 'pending') desc,
            cardinality(u.ocr_flags) > 0 desc,
            u.verification_due_at nulls last,
            u.full_name
$$;

revoke execute on function public.account_directory(user_role) from public, anon;
grant  execute on function public.account_directory(user_role) to authenticated;

comment on function public.account_directory(user_role) is
  'Residents / Personnel list. Pending first, then flagged-by-OCR first '
  'within that, soonest deadline after. Carries id_type (what the '
  'applicant selected at signup, for a true selected-vs-detected compare '
  'against ocr_detected_type) and suspended_reason (what an admin typed '
  'when suspending, or the fixed self-service-deletion message from '
  '0045) alongside the OCR/abuse columns added by 0039/0040/0050.';

-- Verification. Run separately.
--
--   select proname, pg_get_function_result(oid)
--     from pg_proc where proname = 'account_directory';
--
--   -- confirm a self-deleted resident's reason reads distinctly:
--   select full_name, is_suspended, suspended_reason
--     from public.users where suspended_reason like 'Account deleted by the resident%';
