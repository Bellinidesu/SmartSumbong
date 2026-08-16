-- =============================================================
-- SmartSumbong — 0026 The number that is your identity is not yours to
--                     retype
--
-- guard_privileged_user_fields() stops a resident changing their role,
-- verification status or suspension. It does not stop them changing
-- mobile_number — and since 0021 that is their login identity.
--
-- The failure is quiet and complete. A resident edits their number in
-- the profile screen, public.users updates, and auth.users.email still
-- holds the address derived from the old number. Nothing errors. They
-- close the app, come back, type the new number, and the account they
-- just edited does not exist. No message can help them, because from
-- the client's side the credentials are simply wrong.
--
-- Repairing it needs an update to auth.users, which needs the service
-- role, which is not in this app and should not be. So the field is
-- closed, and changing it becomes what it already is in practice: a
-- counter transaction at the barangay hall, where somebody looks at an
-- ID. That is the same shape as reopening a case and as tanod approval
-- — the resident asks, the barangay decides, and the decision is made
-- by a person who can see them.
--
-- full_name is closed for a different reason. It is the name an admin
-- compared against a government ID during verification. A resident who
-- can rewrite it afterwards makes that check worth nothing.
--
-- What a resident may still change on their own: email, which is
-- contact-only since 0021 and carries no authority.
-- =============================================================

set search_path = public, extensions;

create or replace function public.guard_privileged_user_fields()
returns trigger language plpgsql as $$
begin
  -- auth.uid() is null only for service_role / backend contexts, which
  -- bypass RLS anyway; an unauthenticated client never reaches this row.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if new.role                   is distinct from old.role
     or new.verification_status is distinct from old.verification_status
     or new.is_suspended        is distinct from old.is_suspended
     or new.verified_by         is distinct from old.verified_by
     or new.verified_at         is distinct from old.verified_at
     or new.rejection_reason    is distinct from old.rejection_reason then
    raise exception
      'Only an administrator may change account role, verification, or suspension state';
  end if;

  -- The login identity is derived from this. Changing it here without
  -- also changing auth.users.email locks the account, silently.
  if new.mobile_number is distinct from old.mobile_number then
    raise exception
      'Your mobile number is how you sign in. Please ask the barangay to change it.';
  end if;

  -- The name the barangay checked against an ID.
  if new.full_name is distinct from old.full_name then
    raise exception
      'Please ask the barangay to change the name on your account.';
  end if;

  return new;
end $$;

comment on function public.guard_privileged_user_fields() is
  'Stops a resident editing fields that are not theirs to edit: role, '
  'verification and suspension (an admin''s), mobile_number (their login '
  'identity, derived in auth.users and only repairable with the service '
  'role) and full_name (what an admin compared against a government ID). '
  'Email remains theirs — it is contact-only since 0021.';

-- ---------- asking the barangay for a change ------------------

create or replace function public.request_profile_change(
  p_field  text,
  p_value  text,
  p_reason text default null
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_name text;
begin
  if p_field not in ('mobile_number', 'full_name') then
    raise exception 'That field can be changed in the app';
  end if;
  if nullif(trim(p_value), '') is null then
    raise exception 'Please enter the new value';
  end if;

  -- Same normalisation as signup, so an admin is not asked to approve a
  -- number in a shape the identity derivation would reject.
  if p_field = 'mobile_number' and trim(p_value) !~ '^\+639[0-9]{9}$' then
    raise exception 'Enter a mobile number like 09171234567';
  end if;

  select full_name into v_name from public.users where id = auth.uid();
  if v_name is null then
    raise exception 'Not signed in';
  end if;

  insert into public.notifications (user_id, kind, message)
  select a.id, 'status_change',
         v_name || ' asked to change their '
           || case p_field
                when 'mobile_number' then 'mobile number'
                else 'name'
              end
           || ' to ' || trim(p_value)
           || coalesce(' — ' || nullif(trim(p_reason), ''), '')
    from public.users a
   where a.role = 'admin'
     and not a.is_suspended;
end $$;

comment on function public.request_profile_change(text, text, text) is
  'Notifies admins that a resident wants their number or name changed. '
  'Changes nothing: both fields require a person to check an ID, and '
  'mobile_number additionally requires a service-role update to '
  'auth.users that no client should be able to make.';

revoke all on function public.request_profile_change(text, text, text)
  from public, anon;
grant execute on function public.request_profile_change(text, text, text)
  to authenticated;

-- Verification. Run separately.
--
--   select 'guard blocks mobile' as part,
--          case when prosrc like '%how you sign in%' then 'OK' else 'MISSING' end
--     from pg_proc where proname = 'guard_privileged_user_fields'
--   union all
--   select 'request_profile_change',
--          case when exists (select 1 from pg_proc
--                             where proname = 'request_profile_change')
--          then 'OK' else 'MISSING' end;
--
-- Then, as a signed-in resident, an attempt to change your own
-- mobile_number should raise. There is no admin path for actually
-- applying one of these requests yet — an admin has to update both
-- public.users and auth.users by hand. That belongs in the admin portal
-- and in turnover.md until it exists.
