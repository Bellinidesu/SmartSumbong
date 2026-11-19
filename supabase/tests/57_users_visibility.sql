-- 57_users_visibility.sql: an administrator reads only the accounts their rung needs (0179, backend sweep). Staff and Kagawad read no
-- resident unless through a case they may open; profile requests and the account audit are the super admins'; a suspended or retired
-- administrator reads only themselves. The reading checks run as the API's own role. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_cap uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid();
  v_stf uuid := gen_random_uuid(); v_stf2 uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); v_ben uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid();
  r1 uuid; r2 uuid; n integer; s text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'Seen, Super', 'resident'), (v_cap, '+639999999962', 'Seen, Captain', 'resident'),
                 (v_kpo, '+639999999963', 'Seen, Peace', 'resident'), (v_kenv, '+639999999964', 'Seen, Env', 'resident'),
                 (v_stf, '+639999999965', 'Seen, Staff', 'resident'), (v_stf2, '+639999999966', 'Seen, Staff Two', 'resident'),
                 (v_ana, '+639999999967', 'Seen, Ana', 'resident'), (v_ben, '+639999999968', 'Seen, Ben', 'resident'),
                 (v_tan, '+639999999969', 'Seen, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_cap, v_kpo, v_kenv, v_stf, v_stf2, v_ana, v_ben, v_tan);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'captain' where id = v_cap;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id in (v_stf, v_stf2);
  update public.users set admin_tier = 'super', committee = null where role = 'admin' and committee = 'health_sanitation' and admin_tier in ('committee', 'moderator');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto, gabi-gabi.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ben, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa tabi ng kanal, ilang linggo na.', lat + 0.001, lng) returning id into r2;
  insert into public.profile_requests (user_id, kind, new_full_name, reason) values (v_ana, 'full_name', 'Seen, Ana Maria', 'Typo in my name');
  insert into public.account_audit (subject_id, actor_id, action, detail) values (v_ana, v_ana, 'password_reset', 'Password reset with a one-time code');

  -- 1. staff read no resident until a case is assigned to them, then that case's reporter only; they still read administrators and tanods
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if exists (select 1 from public.users where id in (v_ana, v_ben)) then raise exception 'staff read a resident with no case of theirs'; end if;
    if (select count(*) from public.users where id in (v_sup, v_kpo, v_stf2, v_tan)) <> 4 then raise exception 'staff no longer read administrators and tanods'; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    execute 'set local role authenticated';
    perform public.assign_case(r1, v_stf, 'please look');
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if not exists (select 1 from public.users where id = v_ana) then raise exception 'staff cannot read the reporter of the case assigned to them'; end if;
    if exists (select 1 from public.users where id = v_ben) then raise exception 'staff read another case''s reporter'; end if;
    perform set_config('request.jwt.claim.sub', v_stf2::text, true);
    if exists (select 1 from public.users where id = v_ana) then raise exception 'another staff member reads the reporter'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  staff read a resident only as the reporter of a case assigned to them, and still read administrators and tanods';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL staff: ' || sqlerrm; end;

  -- 2. a Kagawad reads the reporters of their own committee's cases and no other resident
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if not exists (select 1 from public.users where id = v_ana) then raise exception 'the Kagawad cannot read their committee''s reporter'; end if;
    if exists (select 1 from public.users where id = v_ben) then raise exception 'the Kagawad reads another committee''s reporter'; end if;
    select count(*) into n from public.account_directory('resident');
    if n <> 0 then raise exception 'the Kagawad lists residents'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if exists (select 1 from public.users where id = v_ana) or not exists (select 1 from public.users where id = v_ben) then raise exception 'the other Kagawad reads the wrong residents'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a Kagawad reads the reporters of their committee''s cases and no other resident';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL Kagawad: ' || sqlerrm; end;

  -- 3. the super admins and the captain read everyone; a resident reads only themselves
  begin
    execute 'set local role authenticated';
    foreach s in array array[v_sup::text, v_cap::text] loop
      perform set_config('request.jwt.claim.sub', s, true);
      if (select count(*) from public.users where id in (v_ana, v_ben, v_tan, v_kpo)) <> 4 then raise exception 'a full viewer misses an account'; end if;
    end loop;
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    if (select count(*) from public.users where id <> v_ana) <> 0 then raise exception 'a resident reads someone else'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  super admins and the captain read every account; a resident reads only their own';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL full viewers: ' || sqlerrm; end;

  -- 4. profile requests and the account audit: the super admins, the captain and the person themselves
  begin
    execute 'set local role authenticated';
    foreach s in array array[v_kpo::text, v_stf::text, v_kenv::text] loop
      perform set_config('request.jwt.claim.sub', s, true);
      if exists (select 1 from public.profile_requests) then raise exception 'a Kagawad or staff member reads profile requests'; end if;
      if exists (select 1 from public.account_audit) then raise exception 'a Kagawad or staff member reads the account audit'; end if;
    end loop;
    foreach s in array array[v_sup::text, v_cap::text] loop
      perform set_config('request.jwt.claim.sub', s, true);
      if not exists (select 1 from public.profile_requests where user_id = v_ana) or not exists (select 1 from public.account_audit where subject_id = v_ana) then
        raise exception 'a full viewer cannot read the requests or the audit';
      end if;
    end loop;
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    if not exists (select 1 from public.profile_requests where user_id = v_ana) then raise exception 'the requester cannot read their own request'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  profile requests are the requester''s and the super admins'', the account audit the super admins'' and the captain''s';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL requests and audit: ' || sqlerrm; end;

  -- 5. the successor picker is the super admins'
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if exists (select 1 from public.admin_candidates(null)) then raise exception 'a Kagawad reads the successor list'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if exists (select 1 from public.admin_candidates(null)) then raise exception 'a staff member reads the successor list'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if not exists (select 1 from public.admin_candidates('Seen, Ben')) then raise exception 'a super admin no longer reads it'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  the successor list is the super admins'' alone';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL successors: ' || sqlerrm; end;

  -- 6. a retired administrator is no administrator any more: they read themselves and nothing else
  begin
    update public.users set is_retired = true, retired_at = now() where id = v_stf2;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_stf2::text, true);
    if public.is_admin() then raise exception 'a retired administrator is still an administrator'; end if;
    if (select count(*) from public.users) <> 1 then raise exception 'a retired administrator reads other accounts'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a retired administrator reads only themselves';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL retired: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
