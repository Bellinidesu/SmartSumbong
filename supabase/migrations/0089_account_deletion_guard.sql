-- 0089 — Account deletion works again for residents who filed complaints
-- (found 6 Oct 2026 while cleaning up test accounts).
--
-- request_account_deletion() (0045) scrubs a resident's name and number in
-- place when they have filed complaints. guard_privileged_user_fields
-- (0026) refuses exactly those changes from a resident, so the scrub
-- failed with "Your mobile number is how you sign in" and the app's Delete
-- account could never finish for anyone who had filed something. The
-- deletion function now marks its own transaction, and the guard lets that
-- one change through. Nothing else about either function changes.

set search_path = public, extensions;

create or replace function public.guard_privileged_user_fields()
returns trigger
language plpgsql
as $$
begin
  -- auth.uid() is null only for service_role / backend contexts, which
  -- bypass RLS anyway; an unauthenticated client never reaches this row.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- The resident's own account deletion (request_account_deletion) scrubs
  -- these fields on purpose.
  if current_setting('smartsumbong.account_deletion', true) = 'on' and new.id = auth.uid() then
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

  if new.mobile_number is distinct from old.mobile_number then
    raise exception
      'Your mobile number is how you sign in. Please ask the barangay to change it.';
  end if;

  if new.full_name is distinct from old.full_name then
    raise exception
      'Please ask the barangay to change the name on your account.';
  end if;

  return new;
end $$;

CREATE OR REPLACE FUNCTION public.request_account_deletion()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_uid         uuid := auth.uid();
  v_role        user_role;
  v_has_reports boolean;
  v_scrub_email text;
  v_scrub_phone text;
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;
  -- 0089: the scrub below changes the name and number, which
  -- guard_privileged_user_fields refuses a resident; this call is allowed.
  perform set_config('smartsumbong.account_deletion', 'on', true);

  select role into v_role from public.users where id = v_uid;
  if v_role is null then
    raise exception 'No such account';
  end if;
  if v_role <> 'resident' then
    raise exception 'Self-service account deletion is currently only available to resident accounts';
  end if;

  select exists(
    select 1 from public.reports where resident_id = v_uid
  ) into v_has_reports;

  if not v_has_reports then
    -- Nothing else in this schema references this account. The caller
    -- hard-deletes auth.users, which cascades everywhere on its own.
    return true;
  end if;

  -- Unique placeholders, not a shared literal â€” public.users.email and
  -- .mobile_number are both `unique`, and a second resident deleting
  -- their account the same day must not collide with the first.
  v_scrub_email := 'deleted+' || replace(v_uid::text, '-', '') || '@smartsumbong.invalid';
  v_scrub_phone := 'deleted-' || left(replace(v_uid::text, '-', ''), 10);

  update public.users
     set full_name        = 'Deleted Resident',
         email             = v_scrub_email,
         mobile_number     = v_scrub_phone,
         id_image_url      = null,
         selfie_url        = null,
         address           = null,
         avatar_url        = null,
         rejection_reason  = null,
         is_suspended      = true,
         suspended_reason  = 'Account deleted by the resident. Their filed reports remain on record.'
   where id = v_uid;

  delete from public.device_tokens where user_id = v_uid;

  return false;
end $function$;
