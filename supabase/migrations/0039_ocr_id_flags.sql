-- =============================================================
-- SmartSumbong — 0039 OCR as a verification flagger
--
-- Real government-database verification of a Philippine ID is not a
-- technology gap this project can close for free: PSA's everify.gov.ph
-- is a manual, staff-typed lookup with no SLA, and automated checks
-- require a BSP-licensed paid API partner. Nothing here claims to
-- verify that an ID is genuine or belongs to the applicant.
--
-- What IS free and genuinely useful: on-device OCR (google_mlkit_text_
-- recognition, run in the Flutter app right after the applicant
-- photographs their ID) reading back what TYPE of document it looks
-- like and what it says, so the admin opens the verification queue
-- already told "the applicant picked Postal ID but this reads like a
-- Driver's License" or "couldn't read this ID at all" instead of
-- discovering that themselves after opening the photo. A flagger, not
-- a verifier — the admin still makes every decision, this just tells
-- them where to look first.
--
-- 0019 already has id_type: the type the applicant SELECTED at signup.
-- These columns hold what OCR independently READ off the photograph,
-- so a mismatch between the two is itself the first, cheapest flag.
-- Nullable throughout: OCR runs client-side after 0019's evidence is
-- already captured, can fail or be skipped by an older app build, and
-- an account must remain approvable even when OCR has nothing to say.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists ocr_detected_type id_document_type;

alter table public.users
  add column if not exists ocr_flags text[] not null default '{}';

alter table public.users
  add column if not exists ocr_extracted_name text;

alter table public.users
  add column if not exists ocr_extracted_number text;

alter table public.users
  add column if not exists ocr_processed_at timestamptz;

comment on column public.users.ocr_detected_type is
  'ID type OCR read off the photograph itself (header/keyword match), '
  'independent of id_type which is what the applicant selected in the '
  'dropdown. The two disagreeing is a flag, not an error — see ocr_flags.';

comment on column public.users.ocr_flags is
  'Machine-generated triage flags from the Flutter client''s on-device '
  'OCR pass, e.g. type_mismatch, unreadable, name_mismatch, no_id_number. '
  'Advisory only: never gates verify_user_account, only orders/labels the '
  'admin''s queue. Empty array means OCR ran and raised nothing, NOT that '
  'OCR never ran — check ocr_processed_at for that.';

comment on column public.users.ocr_extracted_name is
  'Name OCR read off the ID photo, for the admin to eyeball against '
  'full_name. Not normalised, not used in any automated comparison beyond '
  'the name_mismatch flag the client itself may set.';

comment on column public.users.ocr_extracted_number is
  'ID number OCR read off the photo (e.g. license or PhilSys number), '
  'shown to the admin for their own manual cross-check. Never validated '
  'against any external registry — see this file''s header.';

comment on column public.users.ocr_processed_at is
  'When the client''s OCR pass ran. Null means it never ran (older app '
  'build, permission denied, or skipped) — distinct from it having run '
  'and found nothing to flag.';

-- ---------- surface it to the admin portal --------------------
-- account_directory (0013) is the one function both residents.php and
-- personnel.php read the queue through. Same signature otherwise; three
-- columns appended at the end so existing positional callers (there are
-- none outside includes/accounts.php, which selects by name) still work.

create or replace function public.account_directory(p_role user_role)
returns table (
  id                  uuid,
  full_name           text,
  email               text,
  mobile_number       text,
  role                user_role,
  verification_status verification_state,
  is_suspended        boolean,
  duty_status         duty_state,
  id_image_url        text,
  selfie_url          text,
  rejection_reason    text,
  submitted_at        timestamptz,
  due_at              timestamptz,
  minutes_left        integer,
  is_overdue          boolean,
  holding_incident    boolean,
  created_at          timestamptz,
  ocr_detected_type   id_document_type,
  ocr_flags           text[],
  ocr_extracted_name  text,
  ocr_extracted_number text)
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
         u.ocr_extracted_number
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
  'within that, soonest deadline after — the two-hour window and the OCR '
  'flags are the ordering, not columns the admin has to hunt for.';

-- Verification. Run separately.
--
--   select column_name, data_type
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'users'
--      and column_name like 'ocr_%';
--
--   select proname, pg_get_function_result(oid)
--     from pg_proc where proname = 'account_directory';
