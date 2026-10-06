-- 0103 — Remove the "Tanod Kim" test account (Rose, 7 Oct 2026).
--
-- Its history is part of the tamper-checked trail, so the account is
-- archived the same way a deleted account is (0045/0089): signed out for
-- good and hidden from Personnel, its past entries kept. Its one live
-- dispatch was on a complaint already removed; it is closed first.
-- account_directory() now leaves out removed accounts.

alter table public.users add column if not exists removed_at timestamptz;

do $$
declare v uuid := 'cf9067fd-9c49-4067-a39e-2ee84999bf9d';
begin
  update public.dispatches set state = 'rerouted', rerouted_at = now(), reroute_reason = 'Account removed by the barangay'
   where tanod_id = v and state in ('assigned', 'accepted');
  update public.users
     set is_suspended = true,
         suspended_reason = 'Test account removed by the barangay.',
         duty_status = 'offline',
         removed_at = now()
   where id = v and full_name = 'Tanod Kim';
  update auth.users set banned_until = 'infinity' where id = v;
  delete from public.device_tokens where user_id = v;
end $$;

CREATE OR REPLACE FUNCTION public.account_directory(p_role user_role)
 RETURNS TABLE(id uuid, full_name text, email text, mobile_number text, role user_role, verification_status verification_state, is_suspended boolean, duty_status duty_state, id_image_url text, selfie_url text, rejection_reason text, submitted_at timestamp with time zone, due_at timestamp with time zone, minutes_left integer, is_overdue boolean, holding_incident boolean, created_at timestamp with time zone, ocr_detected_type id_document_type, ocr_flags text[], ocr_extracted_name text, ocr_extracted_number text, abuse_strike_count integer, ocr_processed_at timestamp with time zone, ocr_rescan_requested_at timestamp with time zone, id_type id_document_type, suspended_reason text, is_retired boolean, retired_at timestamp with time zone, avatar_url text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
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
     and u.removed_at is null
   order by (u.verification_status = 'pending') desc,
            cardinality(u.ocr_flags) > 0 desc,
            u.verification_due_at nulls last,
            u.full_name
$function$;
