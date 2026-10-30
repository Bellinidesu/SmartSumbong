-- =============================================================
-- SmartSumbong — 0154 account_directory: the committee check once per call
--
-- 0153 scoped account_directory() to a committee's tanods with
-- `not public.admin_scoped()` in the WHERE clause, which Postgres ran once
-- per account: the resident directory went from under the 300 ms budget to
-- about a second (CI's query budget caught it). Wrapped in a sub-select, the
-- check and the caller's committee are worked out once per call.
-- =============================================================

set search_path = public, extensions;

create or replace function public.account_directory(p_role public.user_role)
returns table (id uuid, full_name text, email text, mobile_number text, role public.user_role, verification_status public.verification_state,
               is_suspended boolean, duty_status public.duty_state, id_image_url text, selfie_url text, rejection_reason text,
               submitted_at timestamptz, due_at timestamptz, minutes_left integer, is_overdue boolean, holding_incident boolean,
               created_at timestamptz, ocr_detected_type public.id_document_type, ocr_flags text[], ocr_extracted_name text,
               ocr_extracted_number text, abuse_strike_count integer, ocr_processed_at timestamptz, ocr_rescan_requested_at timestamptz,
               id_type public.id_document_type, suspended_reason text, is_retired boolean, retired_at timestamptz, avatar_url text)
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
     and u.removed_at is null
     and (not (select public.admin_scoped())
          or (u.role = 'tanod' and exists (select 1 from public.tanod_committees tc
                                            where tc.tanod_id = u.id
                                              and tc.committee = (select me.committee from public.users me where me.id = (select auth.uid())))))
   order by (u.verification_status = 'pending') desc,
            cardinality(u.ocr_flags) > 0 desc,
            u.verification_due_at nulls last,
            u.full_name
$$;
