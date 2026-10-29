-- 12_defense_structure.sql: positions, the ladder, several concerns, sensitive cases (0130). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_staff uuid; v_kenv uuid; v_kpeace uuid; v_chair uuid;
  r_env uuid; r_peace uuid; r_dv uuid; r_ok uuid; r_multi uuid; r_late uuid;
  c_extra uuid;
  v_off uuid;
  n integer; t text; st text;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_res := gen_random_uuid(); v_res2 := gen_random_uuid(); v_tan := gen_random_uuid(); v_staff := gen_random_uuid();
  v_kenv := gen_random_uuid(); v_kpeace := gen_random_uuid(); v_chair := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_res, '+639999999931', 'Layer, Ana', 'resident'),
                 (v_res2, '+639999999932', 'Layer, Ben', 'resident'),
                 (v_tan, '+639999999933', 'Layer, Tanod', 'tanod'),
                 (v_staff, '+639999999934', 'Layer, Secretary', 'resident'),
                 (v_kenv, '+639999999935', 'Layer, Kagawad Environment', 'resident'),
                 (v_kpeace, '+639999999936', 'Layer, Kagawad Peace', 'resident'),
                 (v_chair, '+639999999937', 'Layer, Chairman', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_res2, v_tan, v_staff, v_kenv, v_kpeace, v_chair);
  update public.users set role = 'admin' where id in (v_staff, v_kenv, v_kpeace, v_chair);
  v_log := 'setup ok';

  -- 1. positions
  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    perform public.set_official_role(v_kenv, 'kagawad', 'environment');
    perform public.set_official_role(v_kpeace, 'kagawad', 'peace_order');
    perform public.set_official_role(v_chair, 'chairman', null);
    execute 'reset role';
    select count(*) into n from public.users where (id = v_kenv and official_role = 'kagawad' and committee = 'environment')
        or (id = v_kpeace and official_role = 'kagawad' and committee = 'peace_order') or (id = v_chair and official_role = 'chairman' and committee is null);
    if n <> 3 then raise exception 'got %', n; end if;
    v_log := v_log || E'\n' || 'ok  an admin gives accounts a position: two Kagawads with their committees and a Chairman';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL positions: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    begin perform public.set_official_role(v_staff, 'kagawad', null); raise exception 'kagawad without a committee'; exception when check_violation then null; end;
    begin perform public.set_official_role(v_staff, 'chairman', null); raise exception 'a second chairman'; exception when check_violation then null; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a Kagawad needs a committee; there is only one Chairman';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL position rules: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    begin perform public.set_official_role(v_res, 'chairman', null); raise exception 'a resident set a position'; exception when insufficient_privilege then null; end;
    begin update public.users set official_role = 'chairman' where id = v_res; exception when others then null; end;
    execute 'reset role';
    if exists (select 1 from public.users where id = v_res and official_role is not null) then raise exception 'self-promoted'; end if;
    v_log := v_log || E'\n' || 'ok  a resident can neither set a position nor give themselves one';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL self position: ' || sqlerrm; end;

  -- 2. the ladder
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa gilid ng kalsada.', lat, lng, 'validated') returning id into r_env;
  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    perform public.take_case(r_env);
    v_off := public.escalate_in_barangay(r_env, 'The tanods cannot clear this alone.');
    execute 'reset role';
    if v_off <> v_kenv then raise exception 'went to %', v_off; end if;
    select handler_id::text || '|' || tier || '|' || coalesce(higher_official, '') into t from public.reports where id = r_env;
    if t not like v_kenv::text || '|1|%Kagawad (Environment%' then raise exception 'row %', t; end if;
    if not exists (select 1 from public.notifications where user_id = v_kenv and report_id = r_env and kind = 'escalation') then raise exception 'no notice'; end if;
    if not exists (select 1 from public.notifications where user_id = v_res and report_id = r_env and message like '%passed up to%') then raise exception 'resident not told'; end if;
    if not exists (select 1 from public.case_handler_log where report_id = r_env and action = 'escalate' and previous_id = v_staff) then raise exception 'not logged'; end if;
    v_log := v_log || E'\n' || 'ok  escalating a waste case goes to the Environment Kagawad, who becomes its handler; they and the resident are told, and it is logged';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL escalate: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_kpeace::text, true);
    execute 'set local role authenticated';
    begin perform public.escalate_in_barangay(r_env, 'not mine'); raise exception 'a bystander escalated'; exception when others then
      if sqlerrm not like '%handling this case%' then raise; end if; end;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    execute 'set local role authenticated';
    v_off := public.escalate_in_barangay(r_env, 'The committee needs the Chairman.');
    execute 'reset role';
    if v_off <> v_chair then raise exception 'went to %', v_off; end if;
    select tier || '|' || coalesce(array_length(tier_path, 1), 0) into t from public.reports where id = r_env;
    if t <> '2|2' then raise exception 'row %', t; end if;
    perform set_config('request.jwt.claim.sub', v_chair::text, true);
    execute 'set local role authenticated';
    begin perform public.escalate_in_barangay(r_env, 'higher still'); raise exception 'above the chairman'; exception when others then
      if sqlerrm not like '%already with the Chairman%' then raise; end if; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  only the handler can escalate; a Kagawad passes it to the Chairman; nothing goes above the Chairman';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL ladder: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_chair::text, true);
    execute 'set local role authenticated';
    perform public.return_from_official(r_env, 'Decided: the barangay will haul it.');
    execute 'reset role';
    select handler_id::text || '|' || tier into t from public.reports where id = r_env;
    if t <> v_kenv::text || '|1' then raise exception 'row %', t; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    execute 'set local role authenticated';
    perform public.return_from_official(r_env, 'Back to the secretary to schedule.');
    execute 'reset role';
    select handler_id::text || '|' || tier || '|' || coalesce(higher_official, 'none') into t from public.reports where id = r_env;
    if t <> v_staff::text || '|0|none' then raise exception 'row %', t; end if;
    v_log := v_log || E'\n' || 'ok  a return goes back down the same steps, to whoever held it, and clears the hand-up';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL return: ' || sqlerrm; end;

  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res2, 'peace_order_nuisance', 'Ingay', 'Maingay na karaoke hanggang madaling araw.', lat, lng, 'validated') returning id into r_peace;
  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    perform public.take_case(r_peace);
    v_off := public.escalate_in_barangay(r_peace, 'Repeated complaints.');
    execute 'reset role';
    if v_off <> v_kpeace then raise exception 'went to %', v_off; end if;
    v_log := v_log || E'\n' || 'ok  a noise complaint goes to the Peace and Order Kagawad, not the Environment one';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL committee: ' || sqlerrm; end;

  -- 3. sensitive cases
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, awaiting_unit_since)
  values (v_res, 'peace_order_nuisance', 'Domestic violence', 'Sinasaktan ng asawa ang kapitbahay namin gabi-gabi.', lat, lng, 'validated', now() - interval '1 hour')
  returning id into r_dv;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'street_obstruction', 'Nakaharang na sasakyan', 'May nakaparadang sasakyan na humaharang sa daan.', lat, lng, 'validated')
  returning id into r_ok;
  begin
    if not (select is_sensitive from public.reports where id = r_dv) then raise exception 'not flagged'; end if;
    if (select is_sensitive from public.reports where id = r_ok) then raise exception 'ordinary flagged'; end if;
    v_log := v_log || E'\n' || 'ok  a domestic-violence report is marked sensitive on filing; a parked car is not';
  exception when others then v_log := v_log || E'\n' || 'FAIL flag: ' || sqlerrm; end;

  begin
    update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng + 0.001, lat), 4326), last_location_at = now() where id = v_tan;
    perform public.sweep_awaiting_units();
    if exists (select 1 from public.dispatches where report_id = r_dv) then raise exception 'sent to a tanod'; end if;
    update public.reports set is_sensitive = false where id = r_dv;
    perform public.sweep_awaiting_units();
    if not exists (select 1 from public.dispatches where report_id = r_dv and tanod_id = v_tan) then raise exception 'not sent once ordinary'; end if;
    v_log := v_log || E'\n' || 'ok  the waiting line leaves a sensitive case to people, and sends the same case once it is not marked';
  exception when others then v_log := v_log || E'\n' || 'FAIL waiting line: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    perform public.take_case(r_ok);
    perform public.set_case_sensitive(r_ok, true, 'The parked car belongs to the person who threatened her.');
    begin perform public.set_case_sensitive(r_ok, false, ''); raise exception 'no reason'; exception when others then
      if sqlerrm not like '%Say why%' then raise; end if; end;
    execute 'reset role';
    if not (select is_sensitive from public.reports where id = r_ok) then raise exception 'not set'; end if;
    if not exists (select 1 from public.status_logs where report_id = r_ok and remark like 'Marked sensitive:%') then raise exception 'not logged'; end if;
    v_log := v_log || E'\n' || 'ok  the handler can mark a case sensitive with a reason on the record; a reason is required';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL set sensitive: ' || sqlerrm; end;

  -- 4. several concerns in one report
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'barangay_service', 'Matagal ang proseso', 'Matagal ang proseso ng dokumento at walang sumasagot.', lat, lng) returning id into r_multi;
  begin
    select count(*) into n from public.report_concerns where report_id = r_multi and category = 'barangay_service';
    if n <> 1 then raise exception 'main concern %', n; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    c_extra := public.add_report_concern(r_multi, 'peace_order_nuisance', 'Duty negligence');
    begin perform public.add_report_concern(r_multi, 'peace_order_nuisance'); raise exception 'twice'; exception when others then
      if sqlerrm not like '%already has that concern%' then raise; end if; end;
    select count(*) into n from public.report_concerns where report_id = r_multi;
    execute 'reset role';
    if n <> 2 then raise exception 'resident sees %', n; end if;
    v_log := v_log || E'\n' || 'ok  a report starts with its main concern; the resident adds another while it is under review, but not the same twice';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL concerns: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.report_concerns where report_id = r_multi;
    begin perform public.add_report_concern(r_multi, 'traffic_violation'); raise exception 'someone else added one'; exception when insufficient_privilege then null; end;
    begin insert into public.report_concerns (report_id, category) values (r_multi, 'animal_welfare'); raise exception 'direct insert'; exception when others then
      if sqlerrm like 'direct insert' then raise; end if; end;
    execute 'reset role';
    if n <> 0 then raise exception 'another resident saw %', n; end if;
    v_log := v_log || E'\n' || 'ok  another resident cannot see or add concerns to it, and nobody writes the table directly';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL concern privacy: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_staff::text, true);
    execute 'set local role authenticated';
    perform public.take_case(r_multi);
    perform public.set_concern_status(c_extra, true, 'Spoke with the duty tanod.');
    execute 'reset role';
    select status into st from public.report_concerns where id = c_extra;
    if st <> 'resolved' then raise exception 'status %', st; end if;
    if not exists (select 1 from public.notifications where user_id = v_res and report_id = r_multi and message like 'One concern%resolved%') then raise exception 'resident not told'; end if;
    select count(*) into n from public.report_concerns where report_id = r_multi and status = 'open';
    if n <> 1 then raise exception 'open %', n; end if;
    update public.reports set status = 'resolved', resolved_at = now() where id = r_multi;
    select count(*) into n from public.report_concerns where report_id = r_multi and status = 'open';
    if n <> 0 then raise exception 'still open %', n; end if;
    v_log := v_log || E'\n' || 'ok  one concern can be resolved on its own and the resident is told; resolving the case finishes the rest';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL resolve concern: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
