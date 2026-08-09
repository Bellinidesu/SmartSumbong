-- =============================================================
-- SmartSumbong — 0019 Identity evidence at signup
--
-- Three changes, all driven by the registration screen in the mobile
-- design and by what the admin actually needs in order to verify.
--
-- 1. ID TYPE HAD NOWHERE TO LIVE.
--    The design asks the applicant to choose an ID type from a
--    dropdown, then photograph it. public.users stored the photo and
--    discarded the type. That left the verifying admin looking at a
--    picture with no label — and "does this look like a genuine Postal
--    ID" is a different check from "does this look like a genuine
--    passport". The type is part of the evidence, not chrome.
--
-- 2. SELFIE WAS NEVER COLLECTED.
--    0013 added users.selfie_url and said, in as many words, that
--    populating it was a change to the Flutter registration flow. This
--    is that change.
--
--    Why it matters: the ID photograph proves a document exists. It
--    does not prove the person submitting it is the person on it.
--    Without a selfie, anyone holding a photo of a neighbour's Barangay
--    ID can register as that neighbour, and the admin has no way to
--    see it. The Verify User Account use case has the admin confirming
--    the applicant resides in Barangay 183; they can confirm the ID
--    says so. Three artefacts — ID, face, typed name — make that a real
--    reconciliation instead of a document review.
--
-- 3. THE THREE ARE NOW REQUIRED AT SIGNUP.
--    Enforced in handle_new_auth_user(), which already raises on a
--    missing full_name or mobile_number, rather than as NOT NULL
--    columns. Two reasons: existing pending rows legitimately have
--    nulls and must not be invalidated, and a raise can name the
--    missing field where a column constraint can only name itself.
--
--    An account created without identity evidence can never be
--    approved. It would sit in the verification queue forever as a row
--    the admin keeps skipping. Better to refuse it at creation, where
--    the applicant is still on the screen and can retry.
--
-- ON TANODS. A tanod is a resident and carries the same Barangay ID.
-- Nothing printed on it says "tanod", so for staff accounts the
-- document was never the real control — a barangay has a few dozen
-- tanods and the admin knows them by name. role arrives in
-- client-supplied metadata and anyone can claim 'tanod'; what stops
-- them is the admin recognising the name, not the upload. That belongs
-- in manual.md, because an admin who treats tanod approval as a
-- document check is performing the wrong check. barangay_appointment
-- is included below for the barangays that do issue a separate
-- appointment order.
-- =============================================================

set search_path = public, extensions;

-- ---------- id type ------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'id_document_type') then
    create type id_document_type as enum (
      'barangay_id',
      'drivers_license',
      'passport',
      'philsys',
      'postal_id',
      'barangay_appointment'
    );
  end if;
end $$;

alter table public.users
  add column if not exists id_type id_document_type;

comment on column public.users.id_type is
  'Which document id_image_url photographs. Chosen by the applicant at '
  'signup and shown to the admin during verification — the check differs '
  'by document, so the label is part of the evidence. Null on accounts '
  'created before 0019.';

-- ---------- signup now requires identity evidence -------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');
  v_mobile    text := nullif(trim(new.raw_user_meta_data ->> 'mobile_number'), '');
  v_role      text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'role'), ''), 'resident');
  v_id_type   text := nullif(trim(new.raw_user_meta_data ->> 'id_type'), '');
  v_id_image  text := nullif(trim(new.raw_user_meta_data ->> 'id_image_url'), '');
  v_selfie    text := nullif(trim(new.raw_user_meta_data ->> 'selfie_url'), '');
begin
  if v_full_name is null then
    raise exception 'full_name is required at signup';
  end if;
  if v_mobile is null then
    raise exception 'mobile_number is required at signup';
  end if;

  -- An account cannot register itself as staff. Admin promotes later.
  if v_role not in ('resident', 'tanod') then
    raise exception 'role must be resident or tanod at signup';
  end if;

  -- Identity evidence. All three or no account: an application without
  -- them can never be approved, and a row that can never be approved
  -- only clutters the queue the admin has to work through.
  if v_id_type is null then
    raise exception 'id_type is required at signup';
  end if;
  if not exists (select 1 from unnest(enum_range(null::id_document_type)) e
                  where e::text = v_id_type) then
    raise exception 'id_type % is not a recognised document type', v_id_type;
  end if;
  if v_id_image is null then
    raise exception 'id_image_url is required at signup';
  end if;
  if v_selfie is null then
    raise exception 'selfie_url is required at signup';
  end if;

  -- Both URLs are CHECKed by users_id_image_url_pinned and
  -- users_selfie_url_pinned (0018). A URL that is not in the barangay's
  -- own Cloudinary fails the insert, so a forged address produces no
  -- account rather than an account the admin's browser would fetch.
  insert into public.users (
    id, full_name, email, mobile_number, role,
    id_type, id_image_url, selfie_url,
    verification_status, verification_submitted_at
  )
  values (
    new.id, v_full_name, new.email, v_mobile, v_role::user_role,
    v_id_type::id_document_type, v_id_image, v_selfie,
    'pending', now()
  );

  return new;
end $$;

comment on function public.handle_new_auth_user() is
  'Signup bridge. Requires full_name, mobile_number, id_type, '
  'id_image_url and selfie_url in raw_user_meta_data; refuses any role '
  'other than resident or tanod. Runs in the same transaction as the '
  'auth.users insert, so a rejected application leaves no credential '
  'behind. The Flutter client must upload both photos before calling '
  'signUp(), so that a failed signup costs the applicant nothing but a '
  'retry.';

-- Verification. Run separately.
--
--   select column_name, data_type
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'users'
--      and column_name in ('id_type','id_image_url','selfie_url');
--
--   select unnest(enum_range(null::id_document_type))::text as id_types;
