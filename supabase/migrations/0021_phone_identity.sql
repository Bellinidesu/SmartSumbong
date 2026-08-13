-- =============================================================
-- SmartSumbong — 0021 Phone number is the identity
--
-- WHY THIS EXISTS.
--
-- The Register Account use case collects Full Name, Email Address and
-- Mobile Number, and its alternative flow A1 treats a duplicate *mobile
-- number* as the collision that stops registration. Rose's login screen
-- asks for Phone Number and Password. Both point the same way: in this
-- barangay, the phone number is who you are.
--
-- The interview said so too. A resident reporting a broken streetlight
-- has a phone number. She may have no email at all, or one a relative
-- made for her years ago that she cannot get into. Requiring an email to
-- register excludes exactly the resident this system exists to serve —
-- and public.users.email was `not null unique`, so she could not
-- register at all.
--
-- HOW IT WORKS.
--
-- Supabase Auth requires an email. So the auth identity is *derived*
-- from the normalised mobile number:
--
--     +639171234567  ->  639171234567@auth.smartsumbong.local
--
-- The client computes this locally at both signup and login. There is no
-- lookup endpoint, which is the point: an RPC that turned a phone number
-- into an email address would have to be callable by `anon`, and would
-- then hand a resident's real email to anyone who guessed their number,
-- while confirming which numbers are registered. This design has nothing
-- to enumerate.
--
-- The resident's real email, when they have one, lives in
-- public.users.email as a contact detail. It is not a credential.
-- Changing it does not change how they sign in. Changing their phone
-- number does — see the note on that below.
--
-- .local is reserved by RFC 6762 and is not resolvable, so these
-- addresses cannot receive mail. That is deliberate: nothing should ever
-- try to send to them. Password reset goes by OTP to the phone
-- (Semaphore), which is the path every resident can use.
--
-- WHAT THIS COSTS, stated plainly for turnover.md:
--
--   * auth.users.email will be full of synthetic addresses. That is not
--     a fault. Real contact addresses are in public.users.email.
--   * Supabase's built-in password reset mails the auth address and will
--     therefore go nowhere. Reset is OTP-by-SMS; do not enable the
--     built-in flow.
--   * Changing a resident's phone number changes their login identity.
--     It requires updating auth.users.email as well, which needs the
--     service role. There is no admin path for it yet.
--   * A resident who loses their SIM and has no email has no self-serve
--     way back in. The barangay admin resets them by hand. For a system
--     where an admin already verifies every account in person, that is
--     arguably the right answer, but it is a real dependency on the
--     admin being reachable.
-- =============================================================

set search_path = public, extensions;

-- ---------- email becomes optional ----------------------------

alter table public.users
  alter column email drop not null;

comment on column public.users.email is
  'Contact address, not a credential. Optional: many residents do not '
  'have one. Sign-in identity is derived from mobile_number — see '
  'public.auth_email_for(). Postgres allows multiple NULLs under a '
  'unique constraint, so the uniqueness of real addresses still holds.';

comment on column public.users.mobile_number is
  'The identity. Normalised to +639XXXXXXXXX at signup, unique, and the '
  'basis of the synthetic auth address. Changing it changes how the '
  'resident signs in.';

-- ---------- the derivation, in one place -----------------------
-- Mirrored by AuthService.authEmailFor() in
-- mobile/core/lib/src/auth.dart. If either changes, both must.

create or replace function public.auth_email_for(p_mobile text)
returns text
language sql
immutable
parallel safe
as $$
  select regexp_replace(p_mobile, '[^0-9]', '', 'g')
         || '@auth.smartsumbong.local'
$$;

comment on function public.auth_email_for(text) is
  'The synthetic Supabase Auth address for a mobile number. Digits only, '
  'so +639171234567 and 09171234567 must already have been normalised to '
  'the same form by the client before they reach here.';

-- ---------- signup ---------------------------------------------

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
begin
  if v_full_name is null then
    raise exception 'full_name is required at signup';
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
  'Requires full_name, mobile_number, id_type, id_image_url and '
  'selfie_url, and refuses any role other than resident or tanod. Runs '
  'in the same transaction as the auth.users insert, so a rejected '
  'application leaves no credential behind.';

-- Verification. Run separately.
--
--   -- email is now optional, mobile is not
--   select column_name, is_nullable
--     from information_schema.columns
--    where table_schema='public' and table_name='users'
--      and column_name in ('email','mobile_number');
--
--   -- the derivation
--   select public.auth_email_for('+639171234567') as derived,
--          case when public.auth_email_for('+639171234567')
--                  = '639171234567@auth.smartsumbong.local'
--               then 'PASS' else 'FAIL' end as result;
--
--   -- existing accounts still have real addresses in auth.users and
--   -- will not be able to sign in through the new path. Either
--   -- re-register them or update auth.users.email by hand:
--   select u.full_name, u.mobile_number, a.email as auth_email,
--          public.auth_email_for(u.mobile_number) as should_be
--     from public.users u join auth.users a on a.id = u.id;
