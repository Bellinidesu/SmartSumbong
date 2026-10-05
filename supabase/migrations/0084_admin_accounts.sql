-- 0084 — New administrators, Rose's way (5 Oct 2026).
--
-- No sign-up. An admin creates the account in the portal (Settings →
-- Administrators): name, email, mobile number. The database makes the
-- login with a one-time temporary password, shows it once, and flags the
-- account "must change password"; the portal lets the new admin do nothing
-- else until they choose their own (change-password.php, then
-- clear_password_change_flag from 0028). Same temporary-password scheme as
-- the counter reset (0028/0029).
--
--   create_admin_account(email, full_name, mobile) -> temporary password
--   reset_admin_password(user)                     -> temporary password
--
-- Every call is written to account_audit (hash-chained, 0014/0016).

set search_path = public, extensions;

-- The sign-up trigger's rules are for app registrations (synthetic phone
-- identity, ID evidence). An administrator provisioned by
-- create_admin_account() writes its own public.users row instead; only that
-- function sets the flag below, inside its own transaction. GoTrue's
-- sign-ups never do. 0036's body is otherwise unchanged.
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
  if current_setting('smartsumbong.provisioning_admin', true) = 'on' then
    return new;
  end if;

  if v_full_name is null then
    raise exception 'full_name is required at signup';
  end if;

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

-- A temporary password in the counter-reset shape: ABCD-2345-EFG.
create or replace function public._temp_password()
returns text
language plpgsql volatile set search_path = public as $$
declare
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_digit text := '23456789';
  v       text := '';
  i       integer;
begin
  for i in 1..4 loop v := v || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1); end loop;
  v := v || '-';
  for i in 1..4 loop v := v || substr(v_digit, 1 + floor(random() * length(v_digit))::int, 1); end loop;
  v := v || '-';
  for i in 1..3 loop v := v || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1); end loop;
  return v;
end $$;

revoke all on function public._temp_password() from public, anon, authenticated;

create or replace function public.create_admin_account(
  p_email     text,
  p_full_name text,
  p_mobile    text)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_email  text := lower(trim(coalesce(p_email, '')));
  v_name   text := trim(coalesce(p_full_name, ''));
  v_mobile text := trim(coalesce(p_mobile, ''));
  v_id     uuid := gen_random_uuid();
  v_temp   text := public._temp_password();
  v_comma  int;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may add an administrator';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address';
  end if;
  v_comma := position(',' in v_name);
  if v_comma <= 1 or length(trim(substring(v_name from v_comma + 1))) = 0 then
    raise exception 'Write the name as Last Name, First Name';
  end if;
  if v_mobile ~ '^09[0-9]{9}$' then
    v_mobile := '+63' || substr(v_mobile, 2);
  end if;
  if v_mobile !~ '^\+639[0-9]{9}$' then
    raise exception 'Enter the mobile number as 09XXXXXXXXX';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email)
     or exists (select 1 from public.users where lower(email) = v_email) then
    raise exception 'That email already has an account';
  end if;
  if exists (select 1 from public.users where mobile_number = v_mobile) then
    raise exception 'That mobile number already has an account';
  end if;

  perform set_config('smartsumbong.provisioning_admin', 'on', true);

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          extensions.crypt(v_temp, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', v_name), now(), now(), '', '', '', '');

  insert into auth.identities (id, provider_id, user_id, identity_data, provider, created_at, updated_at)
  values (gen_random_uuid(), v_id::text, v_id,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now());

  perform set_config('smartsumbong.provisioning_admin', 'off', true);

  insert into public.users (id, full_name, email, mobile_number, role,
                            verification_status, verified_at, verified_by, must_change_password)
  values (v_id, v_name, v_email, v_mobile, 'admin', 'verified', now(), auth.uid(), true);

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (v_id, auth.uid(), 'admin_created', 'Administrator account created with a temporary password');

  return v_temp;
end $$;

revoke all on function public.create_admin_account(text, text, text) from public, anon;
grant execute on function public.create_admin_account(text, text, text) to authenticated;

create or replace function public.reset_admin_password(p_user uuid)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_temp    text := public._temp_password();
  v_changed integer;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reset an administrator''s password';
  end if;
  if p_user = auth.uid() then
    raise exception 'Change your own password from Set a new password instead';
  end if;
  if not exists (select 1 from public.users where id = p_user and role = 'admin') then
    raise exception 'That account is not an administrator';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(v_temp, extensions.gen_salt('bf')), updated_at = now()
   where id = p_user;
  get diagnostics v_changed = row_count;
  if v_changed <> 1 then
    raise exception 'The password was not changed';
  end if;

  update public.users set must_change_password = true where id = p_user;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'password_reset', 'Temporary administrator password issued');

  return v_temp;
end $$;

revoke all on function public.reset_admin_password(uuid) from public, anon;
grant execute on function public.reset_admin_password(uuid) to authenticated;
