-- 0029_reset_requires_auth_row.sql
--
-- Fixes a real fault in 0028, found in testing.
--
-- WHAT HAPPENED. admin_reset_password() was run against Maria Santos.
-- It returned a password, set must_change_password, and wrote an audit
-- row saying a password had been issued. None of that was true: Maria
-- has no row in auth.users at all — she is one of the seeded accounts
-- that only ever existed in public.users — so the UPDATE matched
-- nothing and there was no credential to change.
--
-- The guard was `if not found then raise`. In plpgsql, FOUND after an
-- UPDATE reflects whether rows were affected, but it had already been
-- set true by the preceding SELECT ... INTO, and the intervening checks
-- left it that way. The condition never fired.
--
-- WHY IT MATTERS MORE THAN A TEST FAILURE. The barangay staff member
-- reads that password across the counter to someone who has queued to
-- get it, and it does not work. The person is told to try again. The
-- audit trail says a reset was issued. Nothing in the system indicates
-- a problem. That is the failure mode this project has been trying to
-- avoid everywhere else: an operation that reports success and did
-- nothing.
--
-- THE FIX. Count the affected rows explicitly with GET DIAGNOSTICS,
-- check the auth row exists before touching anything, and do it in that
-- order so the function refuses early rather than half-way through.

begin;

create or replace function public.admin_reset_password(p_user uuid)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_user    public.users%rowtype;
  v_temp    text;
  v_alpha   text := 'ABCDEFGHJKLMNPQRSTUVWXYZ';   -- no I or O
  v_digit   text := '23456789';                    -- no 0 or 1
  v_changed integer;
  i         integer;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reset a password';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.role = 'admin' then
    raise exception 'Administrator passwords are not reset through this path';
  end if;

  if v_user.is_suspended then
    raise exception 'This account is suspended. Lift the suspension first.';
  end if;

  -- Checked before anything is generated or written. An account with no
  -- sign-in record cannot be given a password, and the honest answer is
  -- that it has to be registered through the app first.
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception
      'This account has never signed in and has no credential to reset. '
      'It must be registered through the app.';
  end if;

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

  -- Not `if not found`. FOUND carries over from the SELECT above and
  -- reports true regardless of what this UPDATE did — which is exactly
  -- how 0028 handed out a password for an account it never touched.
  get diagnostics v_changed = row_count;
  if v_changed <> 1 then
    raise exception
      'The password was not changed (% rows affected). Nothing has been '
      'issued.', v_changed;
  end if;

  update public.users
     set must_change_password = true
   where id = p_user;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'password_reset',
          'Temporary password issued in person');

  return v_temp;
end $$;

-- Clean up the audit row 0028 wrote for a reset that never happened, and
-- the flag it set. Leaving them would mean the first thing anyone reads
-- in this trail is a lie.
update public.users
   set must_change_password = false
 where must_change_password
   and id not in (select id from auth.users);

delete from public.account_audit
 where action = 'password_reset'
   and subject_id not in (select id from auth.users);

commit;

-- ---------------------------------------------------------------
-- VERIFY.
--
-- 1. The function now refuses an account with no credential. Maria
--    Santos is the case that exposed this:
--
--    begin;
--    select set_config('request.jwt.claims',
--      json_build_object('sub','0ddda587-22e1-45fc-8706-50c8187b22c3')::text,
--      true);
--    select public.admin_reset_password('f3f2193f-e8ba-406c-a910-b5635eba2b5e');
--    commit;
--
--    Expect: ERROR, 'This account has never signed in...'. If it
--    returns a password instead, the fix did not take.
--
-- 2. A real account still works. Test Testing has an auth row:
--
--    begin;
--    select set_config('request.jwt.claims',
--      json_build_object('sub','0ddda587-22e1-45fc-8706-50c8187b22c3')::text,
--      true);
--    select public.admin_reset_password('88881dac-1a6f-4455-9524-280e6a485703');
--    commit;
--
--    Expect a password. Sign in with it on the phone.
--
-- 3. The false audit row is gone:
--
--    select u.full_name, a.action, a.created_at
--      from public.account_audit a
--      join public.users u on u.id = a.subject_id
--     where a.action = 'password_reset'
--     order by a.created_at desc;
--
--    Maria Santos should not appear. Test Testing should.
-- ---------------------------------------------------------------
