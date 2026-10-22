-- 23_smart_planning.sql: SMART plans ahead: roster, work orders, forecast, fairness (0142). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_adm2 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid(); v_t3 uuid := gen_random_uuid();
  r uuid; i integer; j jsonb; n integer; wo uuid; k text;
  d date := (now() at time zone 'Asia/Manila')::date - 2;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999951', 'Plano, Admin', 'resident'), (v_adm2, '+639999999952', 'Plano, Dalawa', 'resident'),
                 (v_res, '+639999999953', 'Plano, Ana', 'resident'), (v_t1, '+639999999954', 'Plano, Isa', 'tanod'),
                 (v_t2, '+639999999955', 'Plano, Pangalawa', 'tanod'), (v_t3, '+639999999956', 'Plano, Pangatlo', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_adm2, v_res, v_t1, v_t2, v_t3);
  update public.users set role = 'admin' where id in (v_adm, v_adm2);
  v_log := 'setup ok';
  perform set_config('request.jwt.claim.sub', v_adm::text, true);

  -- the roster: reports by weekday and 3-hour block, and who is usually on duty
  begin
    for i in 1..4 loop
      insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
      values (v_res, 'barangay_service', 'Ilaw ' || i, 'Patay ang ilaw.', lat + i * 0.01, lng, (d + time '14:30') at time zone 'Asia/Manila');
    end loop;
    insert into public.attendance (tanod_id, duty_status, logged_at)
    values (v_t1, 'on_duty', (d + time '14:10') at time zone 'Asia/Manila'), (v_t2, 'on_duty', (d + time '14:20') at time zone 'Asia/Manila');
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    j := public.smart_roster_suggestion(30);
    select x into j from jsonb_array_elements(j -> 'blocks') x
      where (x ->> 'dow')::int = extract(dow from d)::int and (x ->> 'block')::int = 4;
    if j is null then raise exception 'no row for the Wednesday-style block of the test day'; end if;
    if (j ->> 'reports')::int < 4 or (j ->> 'suggested')::int < 1 then raise exception 'row %', j; end if;
    if (j ->> 'usual')::numeric < 2 then raise exception 'usual on duty % (two tanods logged)', j ->> 'usual'; end if;
    if (j ->> 'gap')::numeric <> (j ->> 'suggested')::numeric - (j ->> 'usual')::numeric then raise exception 'gap %', j; end if;
    v_log := v_log || E'\n' || 'ok  the roster suggestion counts reports by weekday and 3-hour block and the tanods usually on duty, with the gap';
  exception when others then v_log := v_log || E'\n' || 'FAIL roster: ' || sqlerrm; end;

  -- hotspot work orders
  begin
    for i in 1..4 loop
      insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
      values (v_res, 'environmental_waste_hazard', 'Baradong kanal', 'Barado ang kanal sa kanto.', 14.5300, 121.0200, now() - make_interval(days => (array[26, 17, 9, 1])[i]));
    end loop;
    select p.pattern_key into k from public.smart_patterns(90) p where p.category = 'environmental_waste_hazard' limit 1;
    if k is null then raise exception 'the test problem is not a recurring pattern'; end if;
    wo := public.smart_workorder_create(k, 'Palitan ang kanal sa kanto', 'Para sa konseho');
    if (select status from public.smart_work_orders where id = wo) <> 'open' then raise exception 'not open'; end if;
    if (select (evidence ->> 'reports')::int from public.smart_work_orders where id = wo) < 4 or jsonb_array_length((select evidence -> 'tracking_ids' from public.smart_work_orders where id = wo)) < 1 then
      raise exception 'evidence %', (select evidence from public.smart_work_orders where id = wo);
    end if;
    begin perform public.smart_workorder_create(k, 'Another', null); raise exception 'a second open order for the same problem';
    exception when check_violation then null; end;
    begin perform public.smart_workorder_create('nope:0,0', 'Nothing', null); raise exception 'an order for a problem that is not there';
    exception when check_violation then null; end;
    begin perform public.smart_workorder_create(k, 'x', null); raise exception 'a title of one letter';
    exception when check_violation then null; end;
    perform public.smart_workorder_set(wo, 'planned', 'Isasama sa badyet');
    perform public.smart_workorder_set(wo, 'done');
    if (select status from public.smart_work_orders where id = wo) <> 'done' then raise exception 'status'; end if;
    wo := public.smart_workorder_create(k, 'Ayusin muli', null);   -- done frees the problem for a new order
    begin perform public.smart_workorder_set(wo, 'finished'); raise exception 'a made-up status';
    exception when check_violation then null; end;
    if (select count(*) from public.smart_events where kind = 'work_order') < 3 then raise exception 'events'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_workorder_create(k, 'A resident', null); raise exception 'a resident made a work order';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    v_log := v_log || E'\n' || 'ok  a recurring problem becomes one work order with its reports as evidence; one open order per problem; refusals; a resident cannot';
  exception when others then v_log := v_log || E'\n' || 'FAIL workorders: ' || sqlerrm; end;

  -- the forecast
  begin
    j := public.smart_forecast(28);
    if (j ->> 'arrive_per_day')::numeric <= 0 or (j ->> 'open_now')::int < 8 or j -> 'open_in_7_days' is null then raise exception 'forecast %', j; end if;
    if (j ->> 'seasonal_ready')::boolean then raise exception 'seasonal claimed with under a year of history'; end if;
    if j -> 'seasonal' <> 'null'::jsonb then raise exception 'seasonal should be null: %', j -> 'seasonal'; end if;
    if jsonb_array_length(j -> 'this_week') < 2 then raise exception 'this week %', j -> 'this_week'; end if;
    v_log := v_log || E'\n' || 'ok  the forecast gives next week''s open cases and this week''s kinds, and says plainly the seasonal forecast needs a year of history';
  exception when others then v_log := v_log || E'\n' || 'FAIL forecast: ' || sqlerrm; end;

  -- fairness among tanods and among administrators
  begin
    for i in 1..8 loop
      insert into public.reports (resident_id, category, subject, description, latitude, longitude, handler_id)
      values (v_res, 'barangay_service', 'Gawa ' || i, 'Pakisuri po ang problemang ito.', lat, lng + i * 0.001, case when i <= 7 then v_adm else v_adm2 end) returning id into r;
      insert into public.dispatches (report_id, tanod_id, assigned_by, state, assigned_at, accepted_at, resolved_at)
      values (r, case when i <= 6 then v_t1 when i = 7 then v_t2 else v_t3 end, v_adm, 'resolved',
              now() - interval '2 days', now() - interval '2 days' + interval '6 minutes', now() - interval '1 day');
    end loop;
    j := public.smart_fairness(14);
    if (j -> 'tanods' -> 0 ->> 'tanod_id')::uuid <> v_t1 or (j -> 'tanods' -> 0 ->> 'assigned')::int < 6 then raise exception 'tanods %', j -> 'tanods'; end if;
    if (j -> 'tanods' -> 0 ->> 'share_pct')::int < 50 then raise exception 'share %', j -> 'tanods' -> 0; end if;
    if (j -> 'tanods' -> 0 ->> 'median_accept_minutes')::numeric <> 6 then raise exception 'accept minutes %', j -> 'tanods' -> 0; end if;
    if j ->> 'tanod_note' is distinct from 'one_tanod_most' then raise exception 'note %', j ->> 'tanod_note'; end if;
    if (j -> 'admins' -> 0 ->> 'admin_id')::uuid <> v_adm then raise exception 'admins %', j -> 'admins'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_fairness(14); raise exception 'a resident read fairness';
    exception when insufficient_privilege then null; end;
    begin perform public.smart_forecast(28); raise exception 'a resident read the forecast';
    exception when insufficient_privilege then null; end;
    begin perform public.smart_roster_suggestion(30); raise exception 'a resident read the roster';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  fairness shows each tanod''s share and how fast they accept, and flags one tanod with most of the work; all four views are for administrators';
  exception when others then v_log := v_log || E'\n' || 'FAIL fairness: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
