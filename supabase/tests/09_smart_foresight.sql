-- 09_smart_foresight.sql: storm mode, deadline risk, spikes, similar cases,
-- referral, morning digest (0127). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_tan uuid; v_adm uuid;
  r_flood uuid; r_late uuid; r_new uuid; r_old uuid;
  t public.report_triage;
  j jsonb;
  n integer;
  v text;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
  wet_lng constant double precision := 121.01099; wet_lat constant double precision := 14.53115;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999961', 'Bukas, Ana', 'resident'),
                 (v_b, '+639999999962', 'Bukas, Ben', 'resident'),
                 (v_tan, '+639999999963', 'Bukas, Tanod', 'tanod'),
                 (v_adm, '+639999999964', 'Bukas, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat), 4326), last_location_at = now() where id = v_tan;
  v_log := 'setup ok';

  -- 1. storm mode
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'environmental_waste_hazard', 'Baha', 'Binaha ang kalye, barado ang kanal.', wet_lat, wet_lng, date_trunc('day', now()) + interval '6 hours')
  returning id into r_flood;
  begin
    select * into t from public.report_triage where report_id = r_flood;
    if t.score <> 55 then raise exception 'before: % %', t.score, t.reasons; end if;   -- 25 kind + 15 flooding + 15 zone
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_storm_mode(true, 'PAGASA heavy rainfall warning, orange', 12);
    execute 'reset role';
    select * into t from public.report_triage where report_id = r_flood;
    if t.score <> 85 or t.level <> 'urgent' or not t.reasons @> '[{"factor": "storm mode"}]' then raise exception 'storm: % %', t.score, t.reasons; end if;
    if not exists (select 1 from public.notifications where user_id = v_adm and message like 'SMART: storm mode is on until %') then raise exception 'not told'; end if;
    v_log := v_log || E'\n' || 'ok  storm mode doubles the flood words and hazard zone (55 -> 85, urgent) and tells the admins';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL storm on: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_storm_mode(true, '');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD storm mode without a reason (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  storm mode needs a reason (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_storm_mode(true, 'I say so');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident switched storm mode (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot switch storm mode (refused: ' || left(sqlerrm, 60) || ')'; end;

  begin
    update public.smart_rules set storm_until = now() - interval '1 minute' where id = 1;
    perform public.smart_watch();
    if (select storm_mode from public.smart_rules where id = 1) then raise exception 'still on'; end if;
    if (select score from public.report_triage where report_id = r_flood) <> 55 then raise exception 'not re-scored'; end if;
    v_log := v_log || E'\n' || 'ok  storm mode ends on its own when its hours are up, and scores go back';
  exception when others then v_log := v_log || E'\n' || 'FAIL storm end: ' || sqlerrm; end;

  -- 2. deadline risk: such cases take about 48 h here; this one has 5 h left after 10 h
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, resolved_at, status)
  select v_b, 'street_obstruction', 'Harang', 'May nakaharang na kariton sa bangketa.', lat, lng, now() - interval '20 days',
         now() - interval '20 days' + make_interval(hours => h), 'resolved'
    from unnest(array[40, 44, 48, 52, 60]) h;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, due_at, status)
  values (v_a, 'street_obstruction', 'Harang', 'May nakaharang na kotse sa eskinita.', lat + 0.002, lng, now() - interval '10 hours',
          now() + interval '5 hours', 'in_progress')
  returning id into r_late;
  insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r_late, v_tan, v_adm, 'accepted');
  begin
    select to_jsonb(d) into j from public._smart_deadline_risk() d where d.report_id = r_late;
    if j ->> 'risk' <> 'high' or (j ->> 'typical_hours')::numeric <> 48 then raise exception '%', j; end if;
    perform public.smart_watch();
    perform public.smart_watch();
    select count(*) into n from public.notifications where user_id = v_adm and report_id = r_late and message like 'SMART: % will probably miss its deadline%';
    if n <> 1 then raise exception 'told % times', n; end if;
    v_log := v_log || E'\n' || 'ok  a case with 5 h left that usually takes 48 h is high risk, told to the admins once';
  exception when others then v_log := v_log || E'\n' || 'FAIL deadline risk: ' || sqlerrm; end;

  -- 3. spikes: animal complaints, none in the 8 weeks before, 6 this week
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, location_label)
  select case when g % 2 = 0 then v_a else v_b end, 'animal_welfare', 'Aso', 'Asong gala na nangangagat sa kanto.',
         lat - 0.001 * g, lng, now() - make_interval(hours => g * 10), 'Purok 3'
    from generate_series(1, 6) g;
  begin
    select to_jsonb(s) into j from public._smart_spikes() s where s.category = 'animal_welfare';
    if j is null or (j ->> 'this_week')::integer < 6 or j ->> 'place' <> 'Purok 3' then raise exception '%', j; end if;
    perform public.smart_watch();
    perform public.smart_watch();
    select count(*) into n from public.notifications where user_id = v_adm and message like 'SMART: spike. % animal welfare reports%';
    if n <> 1 then raise exception 'told % times', n; end if;
    v_log := v_log || E'\n' || 'ok  six animal complaints in a week against none before is a spike, told once, with the place';
  exception when others then v_log := v_log || E'\n' || 'FAIL spike: ' || sqlerrm; end;

  -- 4. similar past cases and the usual office
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, resolved_at, referred_to, referred_at, status)
  select v_b, 'animal_welfare', 'Asong nangangagat', 'May asong gala na nangagat ng bata sa kalye.', lat + 0.01, lng,
         now() - interval '100 days' - make_interval(days => g), now() - interval '98 days' - make_interval(days => g),
         'City Veterinary Office', now() - interval '99 days' - make_interval(days => g), 'resolved'
    from generate_series(1, 3) g;
  select id into r_old from public.reports where resident_id = v_b and referred_to = 'City Veterinary Office' order by created_at desc limit 1;
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (r_old, v_adm, 'in_progress', 'resolved', 'Dog impounded by the City Veterinary Office.');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_a, 'animal_welfare', 'Kinagat ng aso', 'Kinagat ng asong gala ang anak ko sa kalye.', lat + 0.0101, lng)
  returning id into r_new;
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    j := public.smart_case_card(r_new);
    execute 'reset role';
    if jsonb_array_length(j -> 'similar') < 1 or not (j -> 'similar') @> '[{"referred_to": "City Veterinary Office"}]' then raise exception 'similar %', j -> 'similar'; end if;
    if not (j -> 'similar') @> '[{"closing_remark": "Dog impounded by the City Veterinary Office."}]' then raise exception 'remark %', j -> 'similar'; end if;
    if j -> 'referral' ->> 'office' <> 'City Veterinary Office' or (j -> 'referral' ->> 'cases')::integer <> 3 then raise exception 'referral %', j -> 'referral'; end if;
    v_log := v_log || E'\n' || 'ok  the case card shows similar past cases, how they ended, and the usual office (3 of 3)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL memory: ' || sqlerrm; end;

  -- 5. morning digest
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    v := public.smart_digest_preview();
    execute 'reset role';
    if v not like 'SMART morning digest, %' or v not like '%Likely to miss the deadline: 1%' or v not like '%Spike: animal welfare%' then raise exception '%', v; end if;
    perform public.smart_morning_digest();
    if not exists (select 1 from public.notifications where user_id = v_adm and message like 'SMART morning digest, %') then raise exception 'not sent'; end if;
    if not exists (select 1 from cron.job where jobname = 'smart-morning-digest' and schedule = '0 23 * * *') then raise exception 'not scheduled'; end if;
    v_log := v_log || E'\n' || 'ok  the 07:00 digest names deadline risks and spikes, and is scheduled';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL digest: ' || sqlerrm; end;

  begin
    update public.smart_rules set digest_enabled = false where id = 1;
    delete from public.notifications where user_id = v_adm and message like 'SMART morning digest, %';
    perform public.smart_morning_digest();
    if exists (select 1 from public.notifications where user_id = v_adm and message like 'SMART morning digest, %') then raise exception 'sent anyway'; end if;
    v_log := v_log || E'\n' || 'ok  the digest can be switched off';
  exception when others then v_log := v_log || E'\n' || 'FAIL digest off: ' || sqlerrm; end;

  -- 6. residents see none of it
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_spikes();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident saw spikes (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot see spikes, deadline risk or similar cases (refused: ' || left(sqlerrm, 50) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_similar_cases(r_new);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident saw similar cases (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot see similar cases (refused)'; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
