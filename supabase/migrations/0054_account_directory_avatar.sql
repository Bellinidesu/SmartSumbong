-- =============================================================
-- SmartSumbong — 0054 Profile pictures in the admin portal
--
-- Edit Profile (0038) already lets a resident or tanod set
-- users.avatar_url from the mobile app's own camera-icon upload. The
-- portal never showed it anywhere -- Personnel/Residents only ever
-- rendered the verification selfie (selfie_url), a different photo
-- taken once at registration for identity-matching, not the everyday
-- picture someone chose for themselves. account_directory() (0013,
-- last extended 0051/0052) simply never selected avatar_url, so there
-- was nothing for accounts.php to show even if it wanted to.
--
-- Same drop-first requirement every prior extension of this function
-- has hit (0039/0040/0050/0051/0052): CREATE OR REPLACE cannot add an
-- output column to an existing RETURNS TABLE function.
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
  suspended_reason        text,
  is_retired              boolean,
  retired_at              timestamptz,
  avatar_url              text)
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
         u.suspended_reason,
         u.is_retired,
         u.retired_at,
         u.avatar_url
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
  'within that, soonest deadline after. Carries id_type, suspended_reason '
  '(0051), is_retired/retired_at (0052) and now avatar_url (0054) so '
  'Personnel/Residents can show the same profile picture the mobile app '
  'Edit Profile screen lets someone set for themselves.';
