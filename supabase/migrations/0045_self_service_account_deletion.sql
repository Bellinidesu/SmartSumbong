-- =============================================================
-- SmartSumbong — 0045 Self-service account deletion
--
-- No in-app way for a resident to delete their own account and data
-- existed anywhere in this app — flagged during the Figma parity pass
-- (27 Aug 2026) as something Play Store's Data Safety expectations
-- actually ask for, given this app collects ID photos and location. This
-- closes that gap for resident accounts.
--
-- THE HARD PART: reports.resident_id references public.users(id) ON
-- DELETE RESTRICT (migration 0001) — deliberately, so a report can never
-- lose the resident it was filed by out from under it. That is exactly
-- right for the barangay's own case records and exactly wrong for "let
-- someone delete their account" if taken literally: a straightforward
-- cascade delete would either violate that RESTRICT and fail outright
-- for any resident who has ever filed a report, or (worse) would need
-- the RESTRICT loosened, which would let a resident's account deletion
-- silently erase the barangay's record that a complaint was ever made.
--
-- So there are two paths, chosen automatically by whether the resident
-- has ever filed anything:
--
--   Zero reports ever filed: nothing else references this account.
--   request_account_deletion() returns true, and the caller (the
--   delete-account Edge Function) hard-deletes the auth.users row, which
--   cascades to public.users, device_tokens, notifications and
--   everything else naturally.
--
--   At least one report on file: those reports are kept, exactly like
--   reports.deleted_at already keeps a "removed" complaint instead of
--   destroying it (0001's own comment: "never DELETE a report"). This
--   migration extends that same principle to the person who filed it —
--   what actually gets removed is every piece of personally-identifying
--   data on the account and the ability to ever sign back in.
--   request_account_deletion() scrubs public.users in place and returns
--   false, telling the caller to ban the auth user (GoTrue's
--   ban_duration) rather than delete it, since public.users.id is still
--   the foreign key reports.resident_id points at.
--
-- Deliberately NOT deleting auth.users directly from this function, even
-- though a SECURITY DEFINER function owned by the migration role often
-- can: Supabase's GoTrue admin operations (delete, ban) are only
-- reliably reachable through its own Admin API, which needs the service
-- role key — a value that must never be embedded in a database function
-- callable by an authenticated user. This function does everything that
-- belongs in Postgres (the "has reports" check, the scrub, the boolean
-- answer) and leaves the two auth.users-touching calls to the
-- delete-account Edge Function, which holds the service role key the
-- same way send-dispatch-push already does.
--
-- Resident-only for now, guarded explicitly below. A tanod's account
-- carries its own web of references (dispatches, attendance) that this
-- migration has not worked through — extending self-service deletion to
-- tanods is a deliberate follow-up, not an oversight.
-- =============================================================

set search_path = public, extensions;

create or replace function public.request_account_deletion()
returns boolean  -- true: safe to hard-delete auth.users. false: scrubbed
                  -- in place, the caller should ban auth.users instead.
language plpgsql security definer set search_path = public, extensions as $$
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

  -- Unique placeholders, not a shared literal — public.users.email and
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
end $$;

revoke execute on function public.request_account_deletion() from public, anon;
grant  execute on function public.request_account_deletion() to authenticated;

comment on function public.request_account_deletion() is
  'Self-service account deletion, resident-only, called by the '
  'delete-account Edge Function as the resident''s own session. Returns '
  'true when it is safe for the caller to hard-delete auth.users (no '
  'reports on file), false when it has instead scrubbed public.users in '
  'place and the caller should ban the auth user -- reports are never '
  'destroyed, same philosophy as reports.deleted_at.';

-- Verification. Run separately.
--
--   select public.request_account_deletion(); -- as a resident session
--   select full_name, email, mobile_number, is_suspended
--     from public.users where id = '<that resident''s id>';
