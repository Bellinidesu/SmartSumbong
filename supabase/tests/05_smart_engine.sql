-- 05_smart_engine.sql: the SMART engine (0123): overrides, recurring
-- problems, the watcher, calibration. Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_c uuid; v_tan uuid; v_adm uuid;
  r_low uuid; r_urgent uuid; r_sent uuid; r_w uuid;
  t public.report_triage;
  n integer;
  j jsonb;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid();
  v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999921', 'Engine, Ana', 'resident'),
                 (v_b, '+639999999922', 'Engine, Ben', 'resident'),
                 (v_c, '+639999999923', 'Engine, Cora', 'resident'),
                 (v_tan, '+639999999924', 'Engine, Tanod', 'tanod'),
                 (v_adm, '+639999999925', 'Engine, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_c, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat), 4326), last_location_at = now() where id = v_tan;
  v_log := 'setup ok';

  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'barangay_service', 'Clearance', 'Matagal ang pagkuha ng barangay clearance.', lat, lng + 0.003, now() - interval '2 hours')
  returning id into r_low;

  -- 1. overrides
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    t := public.smart_override(r_low, 'urgent', 'Senior citizen waiting for medical assistance papers.');
    execute 'reset role';
    if t.level <> 'low' or t.effective_level <> 'urgent' or t.override_by <> v_adm then raise exception '%', to_jsonb(t); end if;
    if not exists (select 1 from public.smart_overrides where report_id = r_low and from_level = 'low' and to_level = 'urgent' and by_user = v_adm) then
      raise exception 'not logged';
    end if;
    v_log := v_log || E'\n' || 'ok  an admin raises a low report to urgent; the change and reason are kept';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL override: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_retriage(r_low);
    execute 'reset role';
    select * into t from public.report_triage where report_id = r_low;
    if t.effective_level <> 'urgent' then raise exception '%', t.effective_level; end if;
    v_log := v_log || E'\n' || 'ok  re-scoring keeps the admin''s level';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL override kept: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_override(r_low, 'urgent', '');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD an override without a reason (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  an override needs a reason (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_override(r_low, 'urgent', 'I want it faster');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident changed a level (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot change a level (refused: ' || left(sqlerrm, 60) || ')'; end;

  -- 2. the watcher: urgent reports waiting without a tanod
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_b, 'public_safety_infrastructure', 'Sunog', 'May sunog sa kanto, may mga bata.', lat + 0.004, lng, now() - interval '20 minutes')
  returning id into r_urgent;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_c, 'public_safety_infrastructure', 'Kuryente', 'May live wire na nakalaylay, may bata sa tabi.', lat - 0.004, lng, now() - interval '20 minutes')
  returning id into r_sent;
  insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r_sent, v_tan, v_adm, 'assigned');
  begin
    if (select effective_level from public.report_triage where report_id = r_urgent) <> 'urgent' then raise exception 'not urgent'; end if;
    perform public.smart_watch();
    select count(*) into n from public.notifications
     where user_id = v_adm and report_id = r_urgent and kind = 'sla_warning' and message like 'SMART: Urgent report %';
    if n <> 1 then raise exception 'admin told % times', n; end if;
    if exists (select 1 from public.notifications where report_id = r_sent and message like 'SMART:%') then
      raise exception 'dispatched report alerted';
    end if;
    v_log := v_log || E'\n' || 'ok  an urgent report 20 minutes without a tanod is told to the admins; a dispatched one is not';
  exception when others then v_log := v_log || E'\n' || 'FAIL watcher: ' || sqlerrm; end;

  begin
    perform public.smart_watch();
    select count(*) into n from public.notifications where report_id = r_urgent and message like 'SMART:%';
    if n <> 1 then raise exception 'told % times', n; end if;
    v_log := v_log || E'\n' || 'ok  the watcher tells it once';
  exception when others then v_log := v_log || E'\n' || 'FAIL watcher repeats: ' || sqlerrm; end;

  -- 3. recurring problems: same kind, same spot, three different weeks
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  select x.who, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa kanto ng eskinita.', lat + x.dlat, lng - 0.006, now() - x.ago
    from (values (v_a, 0.0000, interval '1 day'), (v_b, 0.0001, interval '8 days'), (v_c, 0.0002, interval '15 days')) as x(who, dlat, ago);
  -- and three in one week elsewhere: one event, not a pattern
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  select x.who, 'animal_welfare', 'Aso', 'Asong gala na nangangagat sa kanto.', lat - 0.006, lng + x.dlng, now() - interval '1 day'
    from (values (v_a, 0.0000), (v_b, 0.0001), (v_c, 0.0002)) as x(who, dlng);
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(p) into j from public.smart_patterns() p where p.category = 'environmental_waste_hazard';
    select count(*) into n from public.smart_patterns() p where p.category = 'animal_welfare';
    execute 'reset role';
    if j is null or (j ->> 'reports')::integer <> 3 or (j ->> 'weeks')::integer < 2 or (j ->> 'residents')::integer <> 3 then raise exception '%', j; end if;
    if n <> 0 then raise exception 'one-week burst counted as recurring'; end if;
    v_log := v_log || E'\n' || 'ok  rubbish at one spot in three different weeks is a recurring problem; three in one week is not';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL patterns: ' || sqlerrm; end;

  begin
    perform public.smart_watch();
    perform public.smart_watch();
    select count(*) into n from public.notifications where user_id = v_adm and message like 'SMART: recurring problem. 3 reports of environmental waste hazard%';
    if n <> 1 then raise exception 'told % times', n; end if;
    v_log := v_log || E'\n' || 'ok  a new recurring problem is told to the admins once';
  exception when others then v_log := v_log || E'\n' || 'FAIL pattern alert: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_patterns();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident listed recurring problems (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot list recurring problems (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public._smart_patterns();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident called the internal pattern function (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  the internal pattern function is closed to residents (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_watch();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident ran the watcher (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot run the watcher (refused: ' || left(sqlerrm, 60) || ')'; end;

  if exists (select 1 from cron.job where jobname = 'smart-watch' and schedule = '*/5 * * * *') then
    v_log := v_log || E'\n' || 'ok  the watcher runs every 5 minutes';
  else
    v_log := v_log || E'\n' || 'FAIL watcher not scheduled';
  end if;

  -- 4. calibration
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(c) into j from public.smart_calibration(30) c where c.level = 'low';
    select count(*) into n from public.smart_factor_stats(30) f where f.factor = 'category' and f.detail = 'barangay_service' and f.raised >= 1;
    execute 'reset role';
    if (j ->> 'raised')::integer < 1 then raise exception 'calibration %', j; end if;
    if n <> 1 then raise exception 'factor stats'; end if;
    v_log := v_log || E'\n' || 'ok  calibration counts the raised low report, by level and by factor';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL calibration: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    t := public.smart_override(r_low, null, 'Papers already released.');
    execute 'reset role';
    if t.effective_level <> 'low' or t.override_level is not null then raise exception '%', to_jsonb(t); end if;
    if (select count(*) from public.smart_overrides where report_id = r_low) <> 2 then raise exception 'not logged'; end if;
    v_log := v_log || E'\n' || 'ok  clearing an override returns the computed level, and is logged too';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL clear: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
