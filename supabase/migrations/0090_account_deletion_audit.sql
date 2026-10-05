-- 0090 — "Delete account" works for residents with no complaints too.
--
-- request_account_deletion (0045) told the delete-account function to
-- hard-delete a resident who had filed nothing. But every verified account
-- has an account_audit entry (the verification), and account_audit refuses
-- to let its subject be deleted, so the hard delete failed for almost
-- everyone. Such an account now takes the same path as one with complaints:
-- its personal data is scrubbed and the sign-in is banned.

set search_path = public, extensions;

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

  -- 0090: an account-change audit entry (every verified account has one)
  -- pins the row just like a filed complaint does, so it is kept and
  -- scrubbed too; a hard delete would be refused by account_audit.
  select exists(select 1 from public.reports where resident_id = v_uid)
      or exists(select 1 from public.account_audit where subject_id = v_uid or actor_id = v_uid)
    into v_has_reports;

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
