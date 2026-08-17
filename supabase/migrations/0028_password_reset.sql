-- 0028_password_reset.sql
--
-- Gives a locked-out resident or tanod a way back in.
--
-- THE PROBLEM. 0021 made the phone number the login identity and
-- computes the auth address as 639XXXXXXXXX@auth.smartsumbong.local.
-- That domain has no mail server and never will — it exists so that
-- nothing has to be looked up and nothing can be enumerated. The
-- consequence is that Supabase's own recovery flow cannot work: the
-- reset link is sent to an address that does not receive mail. Email on
-- public.users is optional and contact-only, so it cannot be relied on
-- either.
--
-- Until Semaphore is configured, a resident who forgets their password
-- has no route back into the system at all. That is the honest state
-- today and it is not acceptable for a barangay service.
--
-- THE APPROACH. The barangay resets it. The same staff already inspect
-- a government ID against the person's stated details before approving
-- the account (Verify User Account); asking them to do the same before
-- handing over a temporary password is the identity check the system
-- already trusts, applied a second time. It costs nothing to run, works
-- with no SMS credit, and survives the operator turnover the whole
-- design is braced for.
--
-- WHAT THIS IS NOT. It is not better than SMS OTP; it is worse, because
-- it needs a trip to the barangay hall. When Semaphore is funded and a
-- sender name is approved, this becomes the fallback rather than the
-- only path. It is written so that it can stay in place either way — an
-- offline route matters most for exactly the resident least able to
-- receive an SMS.
--
-- ON TOUCHING auth.users. This writes encrypted_password directly,
-- which is Supabase's own table rather than ours. That is a deliberate
-- and slightly uncomfortable choice: the supported alternative is the
-- Admin API from an Edge Function, and no function infrastructure
-- exists in this project. The write is confined to one column, uses the
-- same bcrypt call Supabase does, and is the only place in the schema
-- that reaches into auth. If Supabase changes its password storage this
-- function breaks loudly rather than silently, because the verify block
-- at the bottom checks a real login hash.

begin;

-- ---------- forced change on next sign-in ---------------------
-- Without this the temporary password is permanent, and an
-- administrator would keep working credentials for an account that is
-- not theirs. The column is the record of that obligation.
--
-- NOTE FOR THE APPLICATION: nothing enforces this yet. Both mobile
-- clients must check it after sign-in and route to a change-password
-- screen before anything else. Until they do, this column is a promise
-- the system is not keeping.
alter table public.users
  add column if not exists must_change_password boolean not null default false;

comment on column public.users.must_change_password is
  'Set when an administrator issues a temporary password. The client is '
  'required to force a change before allowing any other action.';

-- ---------- reset -------------------------------------------
create or replace function public.admin_reset_password(p_user uuid)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_user  public.users%rowtype;
  v_temp  text;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ';   -- no I or O
  v_digit text := '23456789';                    -- no 0 or 1
  i       integer;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reset a password';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  -- An administrator resetting another administrator is how one admin
  -- quietly takes over another's portal access. Succession has its own
  -- audited path in 0014 and this is not it.
  if v_user.role = 'admin' then
    raise exception 'Administrator passwords are not reset through this path';
  end if;

  if v_user.is_suspended then
    raise exception 'This account is suspended. Lift the suspension first.';
  end if;

  -- Twelve characters, generated here rather than chosen by the
  -- administrator: a human-chosen temporary password tends to be the
  -- same one every time. Ambiguous glyphs are excluded because this
  -- gets read aloud across a counter and written on paper.
  v_temp := '';
  for i in 1..4 loop
    v_temp := v_temp || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
  end loop;
  v_temp := v_temp || '-';
  for i in 1..4 loop
    v_temp := v_temp || substr(v_digit, 1 + floor(random() * length(v_digit))::int, 1);
  end loop;
  v_temp := v_temp || '-';
  for i in 1..3 loop
    v_temp := v_temp || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
  end loop;

  update auth.users
     set encrypted_password = extensions.crypt(v_temp, extensions.gen_salt('bf')),
         updated_at         = now()
   where id = p_user;

  if not found then
    raise exception 'This account has no sign-in record and cannot be reset';
  end if;

  update public.users
     set must_change_password = true
   where id = p_user;

  -- The password itself is never written here. The audit records that a
  -- reset happened, by whom, and for whom — enough to answer "who let
  -- this person back in" without storing the answer to "as what".
  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'password_reset',
          'Temporary password issued in person');

  return v_temp;
end $$;

comment on function public.admin_reset_password(uuid) is
  'Issues a temporary password for a resident or tanod and returns it to '
  'the calling administrator once. Never stored in plaintext.';

revoke execute on function public.admin_reset_password(uuid) from public, anon;
grant  execute on function public.admin_reset_password(uuid) to authenticated;

-- ---------- change your own password -------------------------
-- The other half. Supabase's updateUser() already handles this from a
-- signed-in client; what it does not do is clear the flag, so the
-- client would loop on the change-password screen forever.
create or replace function public.clear_password_change_flag()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  update public.users
     set must_change_password = false
   where id = auth.uid();
end $$;

revoke execute on function public.clear_password_change_flag() from public, anon;
grant  execute on function public.clear_password_change_flag() to authenticated;

commit;

-- ---------------------------------------------------------------
-- VERIFY. Run all four. "Success. No rows returned" from the migration
-- itself proves only that the SQL parsed.
--
-- 1. The column exists and defaults false:
--
--    select column_name, data_type, column_default, is_nullable
--      from information_schema.columns
--     where table_schema = 'public' and table_name = 'users'
--       and column_name = 'must_change_password';
--
-- 2. Neither function is callable by anon:
--
--    select p.proname,
--           has_function_privilege('anon', p.oid, 'execute') as anon,
--           has_function_privilege('authenticated', p.oid, 'execute') as auth
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in ('admin_reset_password',
--                         'clear_password_change_flag');
--
--    Expect anon false, auth true for both.
--
-- 3. The reset actually changes the login hash. Pick a TEST account —
--    not your own — and confirm the returned password verifies:
--
--    select public.admin_reset_password('<test-user-uuid>');
--    -- copy the returned string, then:
--    select encrypted_password = extensions.crypt('<returned>',
--                                                 encrypted_password)
--             as password_matches
--      from auth.users where id = '<test-user-uuid>';
--
--    password_matches must be true. If it is false, extensions.crypt is
--    not the algorithm Supabase reads with and this function is doing
--    nothing useful — stop and say so rather than shipping it.
--
--    Note: step 3 only works when called as an admin. From the SQL
--    editor auth.uid() is null, so is_admin() is false and it will
--    raise. Call it from the portal signed in as an admin, or
--    temporarily test the update block on its own.
--
-- 4. The flag was set and the audit row written:
--
--    select u.full_name, u.must_change_password, a.action, a.created_at
--      from public.users u
--      left join public.account_audit a on a.subject_id = u.id
--                                      and a.action = 'password_reset'
--     where u.id = '<test-user-uuid>';
-- ---------------------------------------------------------------
