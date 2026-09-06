-- =============================================================
-- SmartSumbong -- 0050 Admin-requested OCR re-check for pre-existing
--                     accounts
--
-- Client-side OCR (0039, id_ocr.dart) only ever runs once: at the
-- moment a new account registers and its ID photo is first captured.
-- Every account created before that code existed (5 Sep 2026) -- and
-- any account whose first OCR read something worth a second look --
-- has no way to get a fresh reading, because ML Kit runs on-device
-- and there is no server-side equivalent this project can call
-- instead (real cloud OCR needs a paid API partner -- see 0039's own
-- header for why that path was ruled out).
--
-- What this adds is a flag, not a scan. An admin marks an account
-- "please re-check"; the resident's own app quietly re-downloads its
-- own already-uploaded ID photo (id_image_url -- a barangay Cloudinary
-- address, not a Supabase Storage object, so a plain HTTPS GET is all
-- that's needed) next time it's open, runs the exact same on-device
-- OCR pass registration already runs, and clears the flag itself when
-- it writes the new result. Advisory only, same framing as the rest
-- of this feature: nothing here blocks or changes verification, and a
-- resident who never reopens the app simply leaves the flag pending.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists ocr_rescan_requested_at timestamptz;

comment on column public.users.ocr_rescan_requested_at is
  'Set by request_ocr_rescan() when an admin asks for a fresh OCR read '
  'on this account''s already-uploaded ID photo. Cleared by the '
  'resident''s own app (AuthService.submitIdOcrResult) once it has '
  're-run on-device OCR and written a new result. Null means no '
  're-check is pending.';

-- ---------- admin: ask for a re-check ---------------------------

create or replace function public.request_ocr_rescan(p_user uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user public.users%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may request an ID re-check';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.id_image_url is null then
    raise exception 'This account has no ID photo on file to re-check';
  end if;

  update public.users
     set ocr_rescan_requested_at = now()
   where id = p_user;

  insert into public.notifications (user_id, kind, message)
  values (p_user, 'status_change',
    'The barangay asked to re-check your uploaded ID. Open the app to complete it.');
end $$;

revoke execute on function public.request_ocr_rescan(uuid) from public, anon;
grant  execute on function public.request_ocr_rescan(uuid) to authenticated;

comment on function public.request_ocr_rescan(uuid) is
  'Admin-only. Flags an account for the resident''s own app to silently '
  're-run on-device OCR against its already-uploaded ID photo next time '
  'it opens. Does not run OCR itself -- there is no server-side OCR in '
  'this project, see 0039''s header.';

-- ---------- surface it to the admin portal ----------------------
-- account_directory (0013; extended by 0039 for OCR, by 0040 for
-- abuse_strike_count) -- two more columns appended at the end, same
-- reasoning 0039/0040 already gave: includes/accounts.php selects by
-- name, so appending rather than reordering keeps every existing
-- caller working untouched.
--
-- Same drop-first requirement 0039/0040 both hit -- CREATE OR REPLACE
-- cannot add a column to an existing RETURNS TABLE function.
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
  ocr_rescan_requested_at timestamptz)
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
         u.ocr_rescan_requested_at
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
  'within that, soonest deadline after. Now also carries ocr_processed_at '
  '(distinguishes never-ran from ran-clean) and ocr_rescan_requested_at '
  '(a pending admin-requested re-check) alongside the original OCR '
  'columns and abuse_strike_count.';

-- Verification. Run separately.
--
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'users'
--      and column_name = 'ocr_rescan_requested_at';
--
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname = 'account_directory';
--
--   select proname from pg_proc where proname = 'request_ocr_rescan';
