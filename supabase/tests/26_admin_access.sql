-- 26_admin_access.sql: super admins, committees and captains (0145). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_hs uuid := gen_random_uuid(); v_cap uuid := gen_random_uuid();
  v_res uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid();
  r_po uuid; r_env uuid; r_ani uuid; r_mix uuid;
  n integer; k text; j jsonb;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999981', 'Access, Super', 'resident'), (v_po, '+639999999982', 'Access, Peace', 'resident'),
                 (v_hs, '+639999999983', 'Access, Health', 'resident'), (v_cap, '+639999999984', 'Access, Captain', 'resident'),
                 (v_res, '+639999999985', 'Access, Ana', 'resident'), (v_tan, '+639999999986', 'Access, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_po, v_hs, v_cap, v_res, v_tan);
  update public.users set role = 'admin' where id in (v_sup, v_po, v_hs, v_cap);
  update public.users set admin_tier = 'super' where id = v_sup;
  update public.users set admin_tier = 'committee', committee = 'peace_order' where id = v_po;
  update public.users set admin_tier = 'committee', committee = 'health_sanitation' where id = v_hs;
  update public.users set admin_tier = 'captain' where id = v_cap;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', lat, lng) returning id into r_po;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa tabi ng kanal.', lat, lng + 0.001) returning id into r_env;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'animal_welfare', 'Asong gala', 'Mga asong gala sa harap ng paaralan.', lat + 0.001, lng) returning id into r_ani;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'environmental_waste_hazard', 'Daga', 'Maraming daga sa basurahan.', lat - 0.001, lng) returning id into r_mix;
  insert into public.report_concerns (report_id, category, note, created_by) values (r_mix, 'animal_welfare', 'Daga', v_res);
  v_log := 'setup ok';

  -- 1. the committees for 183, and the ticks they start with
  begin
    if (select count(*) from public.committees where active) <> 4 then raise exception 'active committees %', (select string_agg(key, ',') from public.committees where active); end if;
    if exists (select 1 from public.committees where key = 'women_family' and active) then raise exception 'a struck committee is on'; end if;
    if not exists (select 1 from public.committee_categories where committee = 'peace_order' and category = 'peace_order_nuisance') then raise exception 'peace ticks'; end if;
    if exists (select 1 from public.committee_categories where committee = 'infrastructure') then raise exception 'a struck committee has ticks'; end if;
    v_log := v_log || E'\n' || 'ok  four committees on for 183 (the struck ones off, without ticks); the ticks start from the routing table';
  exception when others then v_log := v_log || E'\n' || 'FAIL committees: ' || sqlerrm; end;

  -- 2. reading, through row level security
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env, r_ani, r_mix);
    if n <> 1 then raise exception 'peace and order sees % (wants its 1)', n; end if;
    if exists (select 1 from public.status_logs where report_id = r_env) then raise exception 'peace and order reads another committee''s history'; end if;
    perform set_config('request.jwt.claim.sub', v_hs::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env, r_ani, r_mix);
    if n <> 2 then raise exception 'health sees % (wants the animal case and the one with an animal concern)', n; end if;
    perform set_config('request.jwt.claim.sub', v_cap::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env, r_ani, r_mix);
    if n <> 4 then raise exception 'the captain sees %', n; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env, r_ani, r_mix);
    if n <> 4 then raise exception 'the super admin sees %', n; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env, r_ani, r_mix);
    if n <> 4 then raise exception 'the resident sees % of their own', n; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a committee reads only its ticked categories (and a case with a concern in them); a captain and a super admin read all; a resident still reads their own';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL reading: ' || sqlerrm; end;

  -- 3. writing a case: in scope yes, out of scope no, the captain never
  begin
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    perform public.take_case(r_po);
    if (select handler_id from public.reports where id = r_po) <> v_po then raise exception 'did not take its own case'; end if;
    begin perform public.take_case(r_env); raise exception 'took a case outside its committee';
    exception when insufficient_privilege then null; end;
    begin perform public.admin_set_status(r_env, 'validated', 'Sinuri', null); raise exception 'changed a case outside its committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_cap::text, true);
    begin perform public.take_case(r_ani); raise exception 'the captain took a case';
    exception when insufficient_privilege then null; end;
    begin perform public.post_report_message(r_ani, 'Sinusuri na po.'); raise exception 'the captain wrote to a resident';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.take_case(r_env);
    v_log := v_log || E'\n' || 'ok  a committee admin works its own case and is refused one outside it; the captain cannot take or write; the super admin can';
  exception when others then v_log := v_log || E'\n' || 'FAIL writing: ' || sqlerrm; end;

  -- 4. a case handed to an admin outside its committee stays visible to the one handling it
  begin
    perform set_config('smartsumbong.handler_change', 'on', true);
    update public.reports set handler_id = v_hs where id = r_po;
    perform set_config('smartsumbong.handler_change', 'off', true);
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_hs::text, true);
    if not exists (select 1 from public.reports where id = r_po) then raise exception 'the handler cannot see the case handed to them'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  an admin handling a case outside its committee (an escalation) still sees it';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL handler: ' || sqlerrm; end;

  -- 5. the analytics and the settings
  begin
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    begin perform public.smart_summary(); raise exception 'a committee read the barangay-wide summary';
    exception when insufficient_privilege then null; end;
    begin perform public.smart_storm_mode(true, 'Bagyo', 6); raise exception 'a committee turned on storm mode';
    exception when insufficient_privilege then null; end;
    select count(*) into n from public.smart_queue(null, 200) q where q.report_id in (r_env, r_ani, r_mix);
    if n <> 0 then raise exception 'the queue showed % cases outside its committee', n; end if;
    perform set_config('request.jwt.claim.sub', v_cap::text, true);
    perform public.smart_summary();
    begin perform public.smart_storm_mode(true, 'Bagyo', 6); raise exception 'the captain turned on storm mode';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.smart_summary();
    perform public.smart_storm_mode(true, 'Bagyo', 6);
    v_log := v_log || E'\n' || 'ok  the analytics are for super admins and captains; settings for super admins; the queue shows a committee only its own cases';
  exception when others then v_log := v_log || E'\n' || 'FAIL analytics: ' || sqlerrm; end;

  -- 6. setting up access: committees, ticks, tiers; nobody widens their own scope; there is always a super admin
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    k := public.committee_save(null, 'Committee on Senior Citizens', 'Komite sa mga Nakatatanda', true);
    if k <> 'committee_on_senior_citizens' then raise exception 'key %', k; end if;
    perform public.committee_set_categories(k, array['barangay_service']::public.complaint_category[]);
    perform public.set_admin_access(v_hs, 'committee', k, false);
    if (select committee from public.users where id = v_hs) <> k then raise exception 'not moved'; end if;
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    begin perform public.committee_save(null, 'Kahit ano', null, true); raise exception 'a committee admin made a committee';
    exception when insufficient_privilege then null; end;
    begin perform public.set_admin_access(v_po, 'super', null, true); raise exception 'a committee admin made itself super';
    exception when insufficient_privilege then null; end;
    begin update public.users set admin_tier = 'super' where id = v_po; raise exception 'a committee admin changed its own tier';
    exception when insufficient_privilege then null; end;
    begin update public.users set committee = 'environment' where id = v_po; raise exception 'a committee admin changed its own committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    update public.users set admin_tier = 'committee', committee = 'peace_order' where role = 'admin' and coalesce(admin_tier, 'super') = 'super' and id <> v_sup;
    begin perform public.set_admin_access(v_sup, 'captain', null, null); raise exception 'the last super admin stepped down';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  a super admin makes a committee, ticks it and moves an admin into it; a committee admin cannot make committees or widen its own scope; the last super admin stays';
  exception when others then v_log := v_log || E'\n' || 'FAIL setup: ' || sqlerrm; end;

  -- 7. notifications about a case outside a committee are never made for it
  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_po, r_ani, 'status_change', 'Iba ang komite');
    insert into public.notifications (user_id, report_id, kind, message) values (v_sup, r_ani, 'status_change', 'Para sa lahat');
    if exists (select 1 from public.notifications where user_id = v_po and report_id = r_ani) then raise exception 'the committee was told about another committee''s case'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and report_id = r_ani) then raise exception 'the super admin was not told'; end if;
    v_log := v_log || E'\n' || 'ok  a committee admin is never notified about a case outside its committee; a super admin is';
  exception when others then v_log := v_log || E'\n' || 'FAIL notifications: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
