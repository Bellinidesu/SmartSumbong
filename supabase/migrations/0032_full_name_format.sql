-- =============================================================
-- SmartSumbong — 0032 full_name must be "Last Name, First Name"
--
-- Jericho's note during the QA exchange (26 Aug 2026): with no enforced
-- order, a name typed free-form could cause a problem later — and
-- confirmed by Ace: require Last Name, First Name at signup.
--
-- SIGNUP ONLY. full_name is closed to editing after registration —
-- guard_privileged_user_fields() (0026) already blocks a resident from
-- rewriting the name an admin checked against a government ID, and the
-- only path to change it afterwards is request_profile_change(), a
-- notification to the barangay that changes nothing by itself. So this
-- format check only has one place to live: the signup trigger. Existing
-- accounts are untouched — this is an INSERT-time trigger check, not a
-- table CHECK constraint, so it says nothing about a row that already
-- exists.
--
-- THE RULE, deliberately loose. At least one comma, with something on
-- both sides of the first one — "Dela Cruz, Juan", "Dela Cruz, Juan
-- Miguel", "Dela Cruz, Juan, Jr." all pass. What fails is no comma at
-- all, a comma with nothing before it, or a comma with nothing (or only
-- whitespace) after it. Anything stricter risks rejecting a real name
-- shape this project has not seen yet; anything looser would not be
-- "Last Name, First Name" any more.
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

  -- "Last Name, First Name" — see this migration's header for exactly
  -- what passes and what doesn't. Mirrors _looksLikeLastFirst() on the
  -- client (register_screen.dart); enforced here too because the client
  -- is not a guarantee and an admin will compare this name to an ID.
  v_comma_pos := position(',' in v_full_name);
  if v_comma_pos <= 1
     or length(trim(substring(v_full_name from v_comma_pos + 1))) = 0 then
    raise exception 'full_name must be in the form Last Name, First Name';
  end if;

  if v_mobile is null then
    raise exception 'mobile_number is required at signup';
  end if;

  -- Philippine mobile numbers: +639 followed by nine digits. Enforced
  -- here as well as on the client, because the client is not a
  -- guarantee and this value determines the account's identity.
  if v_mobile !~ '^\+639[0-9]{9}$' then
    raise exception 'mobile_number must be in the form +639XXXXXXXXX';
  end if;

  -- The auth address must be the one derived from this number. A client
  -- that signs up with a mismatched pair would create an account that
  -- can never be signed into, because login recomputes the address from
  -- the number typed.
  if new.email is distinct from public.auth_email_for(v_mobile) then
    raise exception 'auth identity does not match mobile_number';
  end if;

  -- An account cannot register itself as staff. Admin promotes later.
  if v_role not in ('resident', 'tanod') then
    raise exception 'role must be resident or tanod at signup';
  end if;

  -- Identity evidence: all three or no account (0019).
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

  -- contact_email is optional and arrives in metadata, not from
  -- new.email — new.email is the synthetic identity and must never be
  -- stored as a way to reach anyone.
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
  'id_type, id_image_url and selfie_url, and refuses any role other than '
  'resident or tanod. Runs in the same transaction as the auth.users '
  'insert, so a rejected application leaves no credential behind.';

-- Verification. Run separately — expect the first two to raise, the
-- third to be unaffected by this migration (comma present, both sides
-- non-empty):
--
--   select public.handle_new_auth_user(); -- not directly callable; test
--   -- via actual signups instead, or:
--   select case when 'Juan Dela Cruz' !~ '.' then null end; -- n/a, see below
--
--   -- Reproduce the trigger's own check standalone:
--   select case when position(',' in 'Juan Dela Cruz') <= 1
--               then 'REJECT (no comma)' else 'ok' end;
--   select case when position(',' in 'Dela Cruz, Juan') <= 1
--               then 'REJECT' else 'PASS' end;
--   select case when position(',' in 'Dela Cruz,') <= 1
--                    or length(trim(substring('Dela Cruz,' from
--                        position(',' in 'Dela Cruz,') + 1))) = 0
--               then 'REJECT (nothing after comma)' else 'PASS' end;
