-- 10_smart_learning.sql: new words, quiet cases, the week, the scorecard,
-- SMART routing of the system's dispatches (0128). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_c uuid; v_t1 uuid; v_t2 uuid; v_adm uuid;
  r_quiet uuid; r_route uuid; d uuid;
  j jsonb;
  n integer;
  v text;
  s record;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
  mon date := date_trunc('month', (now() at time zone 'Asia/Manila')::date)::date;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid();
  v_t1 := gen_random_uuid(); v_t2 := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999971', 'Aral, Ana', 'resident'),
                 (v_b, '+639999999972', 'Aral, Ben', 'resident'),
                 (v_c, '+639999999973', 'Aral, Cora', 'resident'),
                 (v_t1, '+639999999974', 'Malapit, Tanod', 'tanod'),
                 (v_t2, '+639999999975', 'Maluwag, Tanod', 'tanod'),
                 (v_adm, '+639999999976', 'Aral, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_c, v_t1, v_t2, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  -- t1 close by, t2 about 330 m away
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng + 0.0003, lat), 4326), last_location_at = now() where id = v_t1;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng + 0.003, lat), 4326), last_location_at = now() where id = v_t2;
  v_log := 'setup ok';

  -- 1. new words
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  select x.who, 'public_safety_infrastructure', 'Bubong', 'Nagliliyab ang bubong ng tindahan, tulong!', lat + x.dl, lng, now() - interval '2 days'
    from (values (v_a, 0.01), (v_b, 0.011), (v_c, 0.012)) as x(who, dl);
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  select x.who, 'environmental_waste_hazard', 'Tambak', 'Ang daming basuraa sa eskinita, umaapaw.', lat - x.dl, lng, now() - interval '2 days'
    from (values (v_a, 0.01), (v_b, 0.011), (v_c, 0.012)) as x(who, dl);
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(w) into j from public.smart_word_suggestions(30) w where w.word = 'nagliliyab';
    if j is null or (j ->> 'reports')::integer <> 3 or j ->> 'mostly_category' <> 'public_safety_infrastructure' or (j ->> 'share')::numeric <> 100 then raise exception 'liyab %', j; end if;
    select to_jsonb(w) into j from public.smart_word_suggestions(30) w where w.word = 'basuraa';
    if j ->> 'likely_spelling_of' <> 'basura' then raise exception 'basuraa %', j; end if;
    select count(*) into n from public.smart_word_suggestions(30) w where w.word in ('eskinita', 'tindahan', 'bubong', 'kanto', 'ang', 'daming');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  unknown words residents keep using are suggested, with their kind (100% public safety) and a likely spelling (basuraa: basura)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL suggestions: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_teach_word('nagliliyab', 'form', 'sunog');
    perform public.smart_teach_word('basuraa', 'spelling', 'basura');
    perform public.smart_teach_word('umaapaw', 'dismiss');
    select count(*) into n from public.smart_word_suggestions(30) w where w.word in ('nagliliyab', 'basuraa', 'umaapaw');
    execute 'reset role';
    if n <> 0 then raise exception 'still suggested'; end if;
    if not exists (select 1 from public.report_triage t join public.reports r on r.id = t.report_id
                    where r.description like 'Nagliliyab%' and t.reasons @> '[{"detail": "fire", "matched": "nagliliyab → sunog"}]') then
      raise exception 'not re-scored';
    end if;
    v_log := v_log || E'\n' || 'ok  an admin teaches a word (nagliliyab: sunog) or dismisses one; open reports are re-scored at once';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL teach: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_teach_word('jeepney', 'category', 'traffic_violation');
    perform public.smart_teach_word('liyab', 'urgent', 'fire');
    execute 'reset role';
    if public._smart_category_hint('other', '', 'Ang jeepney ay nakaharang sa gitna.') ->> 'category' <> 'street_obstruction'
       and public._smart_category_hint('other', '', 'Ang jeepney ay laging mabilis dito.') ->> 'category' <> 'traffic_violation' then
      raise exception 'category word not used';
    end if;
    if not exists (select 1 from public.smart_rules k, jsonb_array_elements(k.keyword_groups) g
                    where k.id = 1 and g ->> 'label' = 'fire' and (g -> 'words') ? 'liyab') then raise exception 'urgent word not added'; end if;
    v_log := v_log || E'\n' || 'ok  a word can be taught as a kind''s word or an urgent word';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL teach kinds: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_teach_word('ingay', 'synonym', 'sunog');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident taught SMART a word (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot teach SMART words (refused: ' || left(sqlerrm, 60) || ')'; end;

  -- 2. quiet cases
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, status, updated_at)
  values (v_a, 'barangay_service', 'Permit', 'Matagal ang permit ng tindahan namin.', lat, lng - 0.004, now() - interval '5 days', 'validated', now() - interval '5 days')
  returning id into r_quiet;
  begin
    select to_jsonb(q) into j from public._smart_stuck() q where q.report_id = r_quiet;
    if j is null or (j ->> 'days_quiet')::integer < 4 then raise exception '%', j; end if;
    perform public.smart_watch();
    perform public.smart_watch();
    select count(*) into n from public.notifications where user_id = v_adm and report_id = r_quiet and message like 'SMART: % has had no update for % days%';
    if n <> 1 then raise exception 'told % times', n; end if;
    insert into public.report_messages (report_id, author_id, from_barangay, body) values (r_quiet, v_adm, true, 'Inaayos na po.');
    if exists (select 1 from public._smart_stuck() q where q.report_id = r_quiet) then raise exception 'still quiet after a message'; end if;
    v_log := v_log || E'\n' || 'ok  a case with no update for 5 days is told once; a new message takes it off the list';
  exception when others then v_log := v_log || E'\n' || 'FAIL quiet: ' || sqlerrm; end;

  -- 3. the week: videoke on Saturday nights
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, location_label)
  select case when g % 2 = 0 then v_b else v_c end, 'peace_order_nuisance', 'Videoke', 'Maingay na videoke hanggang madaling araw.', lat, lng + 0.006,
         ((date_trunc('week', now() at time zone 'Asia/Manila') - make_interval(weeks => g) + interval '5 days 22 hours') at time zone 'Asia/Manila'),
         'Purok 2'
    from generate_series(1, 6) g;
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(p) into j from public.smart_time_patterns(90, 'peace_order_nuisance') p where p.weekday = 'Saturday';
    execute 'reset role';
    if j is null or j ->> 'hours' <> '21:00-00:00' or (j ->> 'reports')::integer < 6 or j ->> 'place' <> 'Purok 2' then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  videoke complaints show up as Saturday 21:00-00:00 in Purok 2';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL week: ' || sqlerrm; end;

  -- 4. scorecard: this month 3 of 4 on time, last month 1 of 2
  --    (finished on day x.done; deadline x.due; on time when done <= due)
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, due_at, resolved_at, status)
  select v_c, 'animal_welfare', 'Aso', 'Asong gala na nangangagat.', lat, lng,
         (x.done - 2)::timestamp at time zone 'Asia/Manila',
         (x.due)::timestamp at time zone 'Asia/Manila' + interval '12 hours',
         (x.done)::timestamp at time zone 'Asia/Manila' + interval '9 hours', 'resolved'
    from (values (mon + 2, mon + 3), (mon + 3, mon + 4), (mon + 4, mon + 5), (mon + 5, mon + 4),
                 (mon - 10, mon - 9), (mon - 8, mon - 9)) as x(done, due);
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(c) into j from public.smart_sla_scorecard(mon) c where c.category = 'animal_welfare';
    execute 'reset role';
    if (j ->> 'finished')::integer <> 4 or (j ->> 'on_time')::integer <> 3 or (j ->> 'on_time_pct')::numeric <> 75
       or (j ->> 'last_month_pct')::numeric <> 50 or (j ->> 'change_pct')::numeric <> 25 then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  the scorecard: animal welfare 75% on time this month, 50% last month, +25';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL scorecard: ' || sqlerrm; end;

  -- 5. routing: the nearest tanod has 3 jobs, the other is free and 330 m away
  for n in 1..3 loop
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
    values (v_b, 'street_obstruction', 'Harang ' || n, 'May nakaharang sa daan, numero ' || n || '.', lat + 0.02 + n * 0.001, lng, 'assigned')
    returning id into r_route;
    insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r_route, v_t1, v_adm, 'accepted');
  end loop;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_a, 'street_obstruction', 'Kotse', 'May kotseng nakaharang sa eskinita namin.', lat, lng, 'validated')
  returning id into r_route;
  begin
    d := public.auto_dispatch(r_route);
    if (select tanod_id from public.dispatches where id = d) <> v_t2 then raise exception 'sent the busy one'; end if;
    if (select admin_instructions from public.dispatches where id = d) not like 'Automatic dispatch — SMART pick: % m from the incident, 0 job(s) in hand%' then
      raise exception '%', (select admin_instructions from public.dispatches where id = d);
    end if;
    v_log := v_log || E'\n' || 'ok  the system sends the free tanod 330 m away, not the nearest with 3 jobs, and says why';
  exception when others then v_log := v_log || E'\n' || 'FAIL routing: ' || sqlerrm; end;

  begin
    delete from public.dispatches where report_id = r_route;
    update public.reports set status = 'validated' where id = r_route;
    update public.smart_rules set smart_routing = false where id = 1;
    d := public.auto_dispatch(r_route);
    if (select tanod_id from public.dispatches where id = d) <> v_t1 then raise exception 'not the nearest'; end if;
    if (select admin_instructions from public.dispatches where id = d) not like 'Automatic dispatch — nearest available unit%' then raise exception 'wording'; end if;
    v_log := v_log || E'\n' || 'ok  with SMART routing off, the system sends the nearest, as before';
  exception when others then v_log := v_log || E'\n' || 'FAIL routing off: ' || sqlerrm; end;

  -- 6. the digest names quiet cases and new words
  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
    select x.who, 'other', 'Bagyo', 'Lumilipad ang yero ng bubong, delikado.', lat + 0.03, lng + x.dl, now() - interval '1 day'
      from (values (v_a, 0.0), (v_b, 0.001), (v_c, 0.002)) as x(who, dl);
    update public.reports set updated_at = now() - interval '6 days', created_at = now() - interval '6 days', status = 'validated' where id = r_quiet;
    delete from public.report_messages where report_id = r_quiet;
    v := public._smart_digest_text();
    if v not like '%No update for 3+ days: %' or v not like '%New words for SMART to learn: %' then raise exception '%', v; end if;
    v_log := v_log || E'\n' || 'ok  the morning digest counts quiet cases and new words to learn';
  exception when others then v_log := v_log || E'\n' || 'FAIL digest: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
