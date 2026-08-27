-- =============================================================
-- SmartSumbong — 0036 selfie is resident-only at signup
--
-- Figma parity audit (27 Aug 2026): Sign Up as Responder (2613:921)
-- has no selfie step and no Email Address field. Email was already
-- optional in handle_new_auth_user() (arrives in metadata, never
-- required by the trigger), so that half was a client-only fix
-- (register_screen.dart). The selfie was not — 0032/0021 raise
-- "selfie_url is required at signup" unconditionally, with no role
-- exemption, so no client change could match Figma without this.
--
-- WHY THIS IS SAFE TO DROP FOR A TANOD SPECIFICALLY. The selfie exists
-- to match an anonymous self-registering resident to the ID they
-- photographed — there is otherwise nothing tying the account to a
-- real person the barangay has actually met. A tanod is a different
-- case: 0019's own rationale for id_document_type notes the document
-- was "never the real control for staff accounts" — the control is an
-- admin checking the submitted ID against the barangay's own roster of
-- known tanods by name before approving. Selfie-to-ID matching adds
-- nothing on top of a roster check the admin is already doing by hand.
--
-- id_type and id_image_url stay required for every role — the tanod
-- app's register_screen.dart still asks for one, just without the
-- dropdown (see that file's client-side header comment on why the
-- Barangay-Appointment option was dropped rather than kept in a
-- one-tap-upload UI).
--
-- Existing accounts are untouched — this only changes what a NEW
-- signup requires, same as 0032's full_name rule.
-- =============================================================

set search_path = public, extensions;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');
  v_mobile    text := nullif(trim(new.raw_user_meta_data ->> 'mobile_number'), '');
  v_email     text := nullif(trim(new.raw_user_meta_data ->> 'contact_email'), '');
  v_role      text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'role'), ''), 'resident');
  v_id_type   text := nullif(trim(new.raw_user_meta_data ->> 'id_type'), '');
  v_id_image  text := nullif(trim(new.raw_user_meta_data ->> 'id_image_url'), '');
  v_selfie    text := nullif(trim(new.raw_user_meta_data ->> 'selfie_url'), '');
  v_comma_pos int;
begin
  if v_full_name is null then
    raise exception 'full_name is required at signup';
  end if;

  -- "Last Name, First Name" — see 0032 for exactly what passes.
  v_comma_pos := position(',' in v_full_name);
  if v_comma_pos <= 1
     or length(trim(substring(v_full_name from v_comma_pos + 1))) = 0 then
    raise exception 'full_name must be in the form Last Name, First Name';
  end if;

  if v_mobile is null then
    raise exception 'mobile_number is required at signup';
  end if;

  if v_mobile !~ '^\+639[0-9]{9}$' then
    raise exception 'mobile_number must be in the form +639XXXXXXXXX';
  end if;

  if new.email is distinct from public.auth_email_for(v_mobile) then
    raise exception 'auth identity does not match mobile_number';
  end if;

  if v_role not in ('resident', 'tanod') then
    raise exception 'role must be resident or tanod at signup';
  end if;

  -- Identity evidence. id_type and id_image_url are required for both
  -- roles; selfie_url is required for a resident only (see this
  -- migration's header for why a tanod is a different case).
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
  if v_role = 'resident' and v_selfie is null then
    raise exception 'selfie_url is required at signup';
  end if;

  if v_email is not null and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'contact_email is not a valid address';
  end if;

  insert into public.users (
    id, full_name, email, mobile_number, role,
    id_type, id_image_url, selfie_url,
    verification_status, verification_submitted_at
  )
  values (
    new.id, v_full_name, v_email, v_mobile, v_role::user_role,
    v_id_type::id_document_type, v_id_image, v_selfie,
    'pending', now()
  );

  return new;
end $$;

comment on function public.handle_new_auth_user() is
  'Signup bridge. The auth address is synthetic and derived from '
  'mobile_number; contact_email is optional and arrives in metadata. '
  'Requires full_name (as "Last Name, First Name", 0032), mobile_number, '
  'id_type and id_image_url for every role; selfie_url is required for '
  'a resident but optional for a tanod (0036) — a tanod is matched to '
  'the barangay''s roster by an admin instead. Refuses any role other '
  'than resident or tanod. Runs in the same transaction as the '
  'auth.users insert, so a rejected application leaves no credential '
  'behind.';

-- Verification — reproduce the branch standalone:
--   select case when 'tanod' = 'resident' then 'REQUIRE' else 'OPTIONAL' end;
--   -- => OPTIONAL
--   select case when 'resident' = 'resident' then 'REQUIRE' else 'OPTIONAL' end;
--   -- => REQUIRE
