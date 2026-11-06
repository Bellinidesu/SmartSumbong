-- 45_ladder.sql: the ladder as Barangay 183 runs it, and staff retirement (0166). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_chr uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid();
  v_ktest uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_stf2 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r_fwd uuid; r_kag uuid; r_dv uuid; r_hs uuid; r_ret uuid; q uuid; v_off uuid; t record; n integer; s text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999981', 'Ladder, Super'), (v_chr, '+639999999982', 'Ladder, Chair'), (v_kpo, '+639999999983', 'Ladder, Peace'),
                 (v_kenv, '+639999999984', 'Ladder, Environment'), (v_ktest, '+639999999985', 'Ladder, Test Kagawad'),
                 (v_stf, '+639999999986', 'Ladder, Staff'), (v_stf2, '+639999999987', 'Ladder, Other Staff'), (v_res, '+639999999988', 'Ladder, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_chr, v_kpo, v_kenv, v_ktest, v_stf, v_stf2, v_res);
  update public.users set official_role = null where official_role in ('chairman', 'kagawad');   -- only this test's officials
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'super', official_role = 'chairman' where id = v_chr;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order', official_role = 'kagawad' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment', official_role = 'kagawad' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'health_sanitation', official_role = 'kagawad', is_test = true where id = v_ktest;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'environment' where id = v_stf2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa gilid ng kalsada.', lat, lng, 'validated') returning id into r_fwd;
  update public.reports set committee = 'peace_order' where id = r_fwd;   -- forwarded from Environment to Peace and Order (0152)
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'peace_order_nuisance', 'Ingay', 'Maingay na karaoke hanggang madaling araw.', lat, lng + 0.001, 'validated') returning id into r_kag;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'peace_order_nuisance', 'Domestic violence', 'Sinasaktan ng asawa ang kapitbahay namin gabi-gabi.', lat, lng + 0.002, 'validated') returning id into r_dv;
  update public.reports set is_sensitive = true, committee = 'peace_order' where id = r_dv;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'animal_welfare', 'Aso', 'Maraming asong gala sa kanto.', lat, lng + 0.003, 'validated') returning id into r_hs;
  update public.reports set committee = 'health_sanitation' where id = r_hs;
  v_log := 'setup ok';

  -- 1. a forwarded case goes to the Kagawad of the committee it is with now; what the page shows is what happens; staff may escalate
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    select * into t from public.escalation_target(r_fwd) limit 1;
    if t.official is distinct from v_kpo or t.to_tier <> 1 or t.why <> 'next' then raise exception 'shown: % % %', t.official, t.to_tier, t.why; end if;
    perform public.take_case(r_fwd);
    v_off := public.escalate_in_barangay(r_fwd, 'Hindi kaya ng tanod.');
    if v_off <> v_kpo then raise exception 'went to % (the Environment Kagawad is %)', v_off, v_kenv; end if;
    if (select tier from public.reports where id = r_fwd) <> 1 then raise exception 'tier'; end if;
    v_log := v_log || E'\n' || 'ok  a forwarded case goes to the Kagawad of the committee it is with now, as shown beforehand; staff may escalate';
  exception when others then v_log := v_log || E'\n' || 'FAIL forwarded: ' || sqlerrm; end;

  -- 2. a Kagawad escalating goes to the Chairman, and the super admins are told
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    select * into t from public.escalation_target(r_kag) limit 1;
    if t.official is distinct from v_chr or t.to_tier <> 2 or t.why <> 'kagawad' then raise exception 'shown: % % %', t.official, t.to_tier, t.why; end if;
    perform public.take_case(r_kag);
    v_off := public.escalate_in_barangay(r_kag, 'Kailangan ng Kapitan.');
    if v_off <> v_chr then raise exception 'went to %', v_off; end if;
    if (select tier from public.reports where id = r_kag) <> 2 then raise exception 'not at the Chairman''s rung'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and report_id = r_kag and kind = 'escalation') then raise exception 'the super admin was not told'; end if;
    if not exists (select 1 from public.notifications where user_id = v_chr and report_id = r_kag and kind = 'escalation') then raise exception 'the Chairman was not told'; end if;
    v_log := v_log || E'\n' || 'ok  a Kagawad escalating goes straight to the Chairman; the Chairman and the super admins are told';
  exception when others then v_log := v_log || E'\n' || 'FAIL kagawad: ' || sqlerrm; end;

  -- 3. a sensitive case goes to the Chairman; returned, it comes straight back down to whoever had it
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    perform public.take_case(r_dv);
    select * into t from public.escalation_target(r_dv) limit 1;
    if t.why <> 'sensitive' or t.official is distinct from v_chr then raise exception 'shown: % %', t.official, t.why; end if;
    v_off := public.escalate_in_barangay(r_dv, 'Sensitibong kaso.');
    if v_off <> v_chr then raise exception 'went to %', v_off; end if;
    if not exists (select 1 from public.status_logs where report_id = r_dv and remark like '%a sensitive case%') then raise exception 'not marked in the history'; end if;
    perform set_config('request.jwt.claim.sub', v_chr::text, true);
    perform public.return_from_official(r_dv, 'Kayo na muna ang humawak.');
    select handler_id::text || '|' || tier || '|' || coalesce(higher_official, 'none') into s from public.reports where id = r_dv;
    if s <> v_stf::text || '|0|none' then raise exception 'after the return: %', s; end if;
    v_log := v_log || E'\n' || 'ok  a sensitive case goes to the Chairman and is marked so; returned, it comes straight back to the staff member';
  exception when others then v_log := v_log || E'\n' || 'FAIL sensitive: ' || sqlerrm; end;

  -- 4. a committee whose only Kagawad is a test account: the Chairman, never the test account
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select * into t from public.escalation_target(r_hs) limit 1;
    if t.official is distinct from v_chr or t.why <> 'no_kagawad' then raise exception 'shown: % %', t.official, t.why; end if;
    v_log := v_log || E'\n' || 'ok  a committee with no real Kagawad account goes to the Chairman; a test account never receives an escalation';
  exception when others then v_log := v_log || E'\n' || 'FAIL no kagawad: ' || sqlerrm; end;

  -- 5. staff hold the other decisions too: handing up and referring out are no longer refused
  begin
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('approve_escalation', 'deny_escalation', 'escalate_in_barangay', 'hand_to_higher_official', 'refer_report')
                 and position('Staff cannot make this decision' in p.prosrc) > 0) then
      raise exception 'a decision function still refuses staff';
    end if;
    v_log := v_log || E'\n' || 'ok  staff hold the five decisions (approve and deny escalations, escalate, hand up, refer out)';
  exception when others then v_log := v_log || E'\n' || 'FAIL staff decisions: ' || sqlerrm; end;

  -- 6. staff ask to retire: their Kagawad is told and endorses, another Kagawad cannot; a super admin decides
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, handler_id)
    values (v_res, 'peace_order_nuisance', 'Away', 'Nag-aaway ang magkapitbahay.', lat, lng + 0.004, 'validated', v_stf) returning id into r_ret;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    q := (public.request_retirement()).id;
    if not exists (select 1 from public.notifications where user_id = v_kpo and kind = 'retirement' and subject_user_id = v_stf) then raise exception 'their Kagawad was not told'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and kind = 'retirement' and subject_user_id = v_stf) then raise exception 'the super admins were not told'; end if;
    if exists (select 1 from public.notifications where user_id in (v_kenv, v_stf2) and kind = 'retirement' and subject_user_id = v_stf) then raise exception 'another committee was told'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.endorse_retirement(q, null); raise exception 'another committee''s Kagawad endorsed';
    exception when insufficient_privilege then null; end;
    execute 'set local role authenticated';
    select count(*) into n from public.retirement_requests_queue() where id = q;
    execute 'reset role';
    if n <> 0 then raise exception 'another Kagawad reads the request'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    execute 'set local role authenticated';
    select role into s from public.retirement_requests_queue() where id = q;
    execute 'reset role';
    if s is distinct from 'staff' then raise exception 'their Kagawad reads %', s; end if;
    perform public.endorse_retirement(q, 'Lilipat na siya ng tirahan.');
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.finalize_retirement(q, 'approve', null); raise exception 'a Kagawad decided';
    exception when others then if sqlerrm not like '%Only an administrator%' then raise; end if; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.finalize_retirement(q, 'approve', null);
    if not (select is_retired from public.users where id = v_stf) then raise exception 'not retired'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if public.admin_tier() is not null then raise exception 'a retired staff member still has a tier'; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    if (select handler_id from public.reports where id = r_ret) is not null then raise exception 'their case was left with them'; end if;
    if not exists (select 1 from public.case_handler_log where report_id = r_ret and action = 'release' and previous_id = v_stf) then raise exception 'the release is not logged'; end if;
    v_log := v_log || E'\n' || 'ok  staff ask to retire; only their Kagawad is told, reads and endorses it; a super admin approves; their tier ends and their cases are released';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL staff retirement: ' || sqlerrm; end;

  -- 7. a Kagawad or a super admin cannot ask to retire through this (their accounts are changed in Roles)
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.request_retirement(); raise exception 'a Kagawad asked';
    exception when others then if sqlerrm not like '%Only a tanod or a staff member%' then raise; end if; end;
    v_log := v_log || E'\n' || 'ok  only a tanod or a staff member asks to retire';
  exception when others then v_log := v_log || E'\n' || 'FAIL who may ask: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
