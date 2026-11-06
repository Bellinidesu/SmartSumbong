-- 41_dev_levels.sql: a developer's test account for each rung (0162). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_dev uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid(); v_po uuid := gen_random_uuid();
  j jsonb; n integer; k uuid; v_com text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_dev, '+639999999951', 'Levels, Dev'), (v_sup, '+639999999952', 'Levels, Super'), (v_po, '+639999999953', 'Levels, Peace')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_dev, v_sup, v_po);
  update public.users set role = 'admin', admin_tier = 'super' where id in (v_dev, v_sup);
  update public.users set is_dev = true where id = v_dev;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_po;
  select key into v_com from public.committees where active order by sort, key limit 1;

  -- 1. only a developer has test accounts; one for each rung, marked as tests, with the access of that rung
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin perform public.dev_test_accounts_ensure(null); raise exception 'a super admin who is not a developer got test accounts';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    begin perform public.dev_test_accounts_ensure(null); raise exception 'a Kagawad got test accounts'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    j := public.dev_test_accounts_ensure('peace_order');
    if (j->>'made')::int <> 4 then raise exception 'not four accounts: %', j; end if;
    select count(*) into n from public.dev_test_accounts d join public.users u on u.id = d.account
     where d.owner = v_dev and u.is_test and not u.is_dev and u.role = 'admin' and u.admin_tier = d.level and not u.must_change_password;
    if n <> 4 then raise exception 'only % accounts have the access of their rung', n; end if;
    if not exists (select 1 from public.dev_test_accounts d join public.users u on u.id = d.account
                    where d.owner = v_dev and d.level = 'committee' and u.committee = 'peace_order' and u.official_role = 'kagawad') then
      raise exception 'the test Kagawad is not a Kagawad of Peace and Order';
    end if;
    if exists (select 1 from public.dev_test_accounts d join public.users u on u.id = d.account where d.owner = v_dev and d.level in ('super', 'captain') and u.committee is not null) then
      raise exception 'a test super admin or captain has a committee';
    end if;
    v_log := v_log || E'\n' || 'ok  only a developer gets test accounts: one per rung, marked test, with exactly that rung''s access';
  exception when others then v_log := v_log || E'\n' || 'FAIL make: ' || sqlerrm; end;

  -- 2. asking again makes nothing new; moving to another committee moves the Kagawad and the staff only
  begin
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    select account into k from public.dev_test_accounts where owner = v_dev and level = 'committee';
    j := public.dev_test_accounts_ensure(v_com);
    if (j->>'made')::int <> 0 then raise exception 'asking again made % more', j->>'made'; end if;
    if (select account from public.dev_test_accounts where owner = v_dev and level = 'committee') <> k then raise exception 'the Kagawad was replaced, not moved'; end if;
    if (select committee from public.users where id = k) <> v_com then raise exception 'the Kagawad did not move'; end if;
    begin perform public.dev_test_accounts_ensure('no_such_committee'); raise exception 'an unknown committee was taken'; exception when check_violation then null; end;
    j := public.dev_levels();
    if jsonb_array_length(j) <> 4 or j->0->>'level' <> 'super' or j->3->>'level' <> 'moderator' then raise exception 'the switcher list is wrong: %', j; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if jsonb_array_length(public.dev_levels()) <> 0 then raise exception 'someone else saw a developer''s test accounts'; end if;
    v_log := v_log || E'\n' || 'ok  asking again makes nothing new; another committee moves the Kagawad and staff; nobody else sees the list';
  exception when others then v_log := v_log || E'\n' || 'FAIL again: ' || sqlerrm; end;

  -- 3. a test Kagawad is never the one asked to pick a tanod
  begin
    if pg_get_functiondef('public._reroute_ask(uuid)'::regprocedure) !~ 'not u\.is_test' then raise exception '_reroute_ask still takes test accounts'; end if;
    if pg_get_functiondef('public.sweep_reroute_questions()'::regprocedure) !~ 'not u\.is_test' then raise exception 'sweep_reroute_questions still tells test accounts'; end if;
    v_log := v_log || E'
' || 'ok  routing never takes a test Kagawad to pick a tanod';
  exception when others then v_log := v_log || E'
' || 'FAIL routing: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
