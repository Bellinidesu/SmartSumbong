-- 52_email_reset.sql: reset codes go only to a confirmed email; only the service role confirms one; a change clears it (0174). Rolled back.
-- The person's own writes run as the API's role ("authenticated") with their claim, so row level security and the triggers apply as in the app.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_res uuid := gen_random_uuid(); v_adm uuid := gen_random_uuid(); o1 uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id', 'contact_email', x.em,
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999971', 'Mail, Ana', 'ana.sweep@example.com'),
                 (v_adm, '+639999999972', 'Mail, Admin', null)) as x(id, mob, nm, em);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_adm);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_adm;
  update public.users set email = 'ana.sweep@example.com' where id = v_res and email is null;   -- whichever way sign-up kept the contact email

  -- 1. a new account starts unconfirmed; the service role (no claim) confirms it
  begin
    if (select email_confirmed_at from public.users where id = v_res) is not null then raise exception 'a new email starts confirmed'; end if;
    perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claims', '', true);
    update public.users set email_confirmed_at = now() where id = v_res;
    if (select email_confirmed_at from public.users where id = v_res) is null then raise exception 'the service role could not confirm'; end if;
    v_log := v_log || E'\n' || 'ok  a new email starts unconfirmed and the service role confirms it';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL confirming: ' || sqlerrm;
  end;

  -- 2. signed in, nobody writes the mark: not the person, not a super admin
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    begin update public.users set email_confirmed_at = null where id = v_res; raise exception 'the person cleared the mark by hand';
    exception when insufficient_privilege then null; end;
    begin update public.users set email_confirmed_at = now() - interval '1 day' where id = v_res; raise exception 'the person set the mark by hand';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin update public.users set email_confirmed_at = now() where id = v_adm; raise exception 'an admin set the mark by hand';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claims', '', true);
    if (select email_confirmed_at from public.users where id = v_res) is null then raise exception 'the mark was lost'; end if;
    v_log := v_log || E'\n' || 'ok  signed in, neither the person nor a super admin can set or clear the mark';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL guarding: ' || sqlerrm;
  end;

  -- 3. the person still edits their own email and address; a new address clears the mark, a change of case or the address does not
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    update public.users set address = 'Blk 1 Lot 2' where id = v_res;
    update public.users set email = ' Ana.Sweep@Example.com ' where id = v_res;
    execute 'reset role';
    if (select email_confirmed_at from public.users where id = v_res) is null then raise exception 'a change of case or the address cleared the mark'; end if;
    execute 'set local role authenticated';
    update public.users set email = 'ana.new@example.com' where id = v_res;
    execute 'reset role';
    if (select email_confirmed_at from public.users where id = v_res) is not null then raise exception 'a new address kept the old mark'; end if;
    perform set_config('request.jwt.claims', '', true);
    update public.users set email_confirmed_at = now() where id = v_res;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    update public.users set email = null where id = v_res;
    execute 'reset role';
    if (select email_confirmed_at from public.users where id = v_res) is not null then raise exception 'removing the email kept the mark'; end if;
    perform set_config('request.jwt.claims', '', true);
    -- the service role writing an address and its mark together (none does today) still ends unconfirmed: a new address is never pre-confirmed
    update public.users set email = 'ana.sweep@example.com', email_confirmed_at = now() where id = v_res;
    if (select email_confirmed_at from public.users where id = v_res) is not null then raise exception 'a new address arrived confirmed'; end if;
    v_log := v_log || E'\n' || 'ok  the person edits their email and address; a new or removed address clears the mark, a change of case does not';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL changing: ' || sqlerrm;
  end;

  -- 4. the confirming code: purpose email with its address, checked by otp_attempt; the table stays closed to the API
  begin
    perform set_config('request.jwt.claims', '', true);
    insert into public.password_otps (user_id, purpose, new_email, code_hash, expires_at)
    values (v_res, 'email', 'ana.sweep@example.com', 'h-right', now() + interval '10 minutes') returning id into o1;
    if (select outcome from public.otp_attempt(v_res, 'email', 'h-wrong')) <> 'wrong' then raise exception 'a wrong code passed'; end if;
    if (select outcome from public.otp_attempt(v_res, 'password', 'h-right')) <> 'expired' then raise exception 'an email code reset a password'; end if;
    if (select otp_id from public.otp_attempt(v_res, 'email', 'h-right')) <> o1 then raise exception 'the right code failed'; end if;
    begin insert into public.password_otps (user_id, purpose, code_hash, expires_at) values (v_res, 'phone', 'x', now()); raise exception 'an unknown purpose was stored';
    exception when check_violation then null; end;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    begin perform count(*) from public.password_otps; raise exception 'the app read the codes';
    exception when insufficient_privilege then null; end;
    begin perform public.otp_attempt(v_res, 'email', 'h-right'); raise exception 'the app called otp_attempt';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_log := v_log || E'\n' || 'ok  an email code is its own purpose with its address, a wrong one counts, it never resets a password, and the app reads none of it';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL codes: ' || sqlerrm;
  end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
