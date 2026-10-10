-- 04_smart.sql: SMART triage (0121 hazard zones, 0122 triage). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_c uuid; v_tan uuid; v_adm uuid;
  r_fire uuid; r_house uuid; r_canal uuid; r_near uuid; r_dup uuid; r_many uuid; r_bad uuid;
  t public.report_triage;
  n integer;
  j jsonb;
  -- outside every hazard zone, and inside a high flood zone
  dry_lng constant double precision := 121.01219; dry_lat constant double precision := 14.51944;
  wet_lng constant double precision := 121.01099; wet_lat constant double precision := 14.53115;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid();
  v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999911', 'Smart, Ana', 'resident'),
                 (v_b, '+639999999912', 'Smart, Ben', 'resident'),
                 (v_c, '+639999999913', 'Smart, Cora', 'resident'),
                 (v_tan, '+639999999914', 'Smart, Tanod', 'tanod'),
                 (v_adm, '+639999999915', 'Smart, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_c, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(dry_lng + 0.002, dry_lat), 4326),
         last_location_at = now() where id = v_tan;
  v_log := 'setup ok';

  -- 1. words and kind: fire with a child, away from any hazard zone
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'public_safety_infrastructure', 'Sunog sa likod', 'May sunog sa likod ng bahay, may bata sa loob.', dry_lat, dry_lng,
          date_trunc('day', now()) + interval '6 hours')
  returning id into r_fire;
  select * into t from public.report_triage where report_id = r_fire;
  begin
    if t.score <> 75 or t.level <> 'urgent' then raise exception 'got % %', t.score, t.level; end if;
    if not t.reasons @> '[{"factor": "words", "detail": "fire", "matched": "sunog"}]' then raise exception 'no fire reason: %', t.reasons; end if;
    if not t.reasons @> '[{"factor": "words", "detail": "vulnerable"}]' then raise exception 'no child reason'; end if;
    v_log := v_log || E'\n' || 'ok  a fire with a child is urgent (75), and says why';
  exception when others then v_log := v_log || E'\n' || 'FAIL fire scoring: ' || sqlerrm; end;

  begin
    if t.reasons @> '[{"detail": "flooding"}]' or t.reasons @> '[{"factor": "hazard zone"}]' then raise exception '%', t.reasons; end if;
    v_log := v_log || E'\n' || 'ok  "bahay" is not "baha", and a dry spot has no hazard points';
  exception when others then v_log := v_log || E'\n' || 'FAIL false flood: ' || sqlerrm; end;

  -- 2. plain complaint: kind only
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'barangay_service', 'Certificate', 'Matagal ang pagkuha ng barangay clearance.', dry_lat - 0.0008, dry_lng,
          date_trunc('day', now()) + interval '6 hours')
  returning id into r_house;
  select * into t from public.report_triage where report_id = r_house;
  begin
    if t.score <> 10 or t.level <> 'low' then raise exception 'got % %', t.score, t.level; end if;
    v_log := v_log || E'\n' || 'ok  a clearance delay is low (10)';
  exception when others then v_log := v_log || E'\n' || 'FAIL plain scoring: ' || sqlerrm; end;

  -- 3. hazard zone
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'environmental_waste_hazard', 'Barado ang kanal', 'Barado ang kanal sa kanto, puno ng basura.', wet_lat, wet_lng,
          date_trunc('day', now()) + interval '6 hours')
  returning id into r_canal;
  select * into t from public.report_triage where report_id = r_canal;
  begin
    if t.score <> 40 then raise exception 'got %: %', t.score, t.reasons; end if;
    if not t.reasons @> '[{"factor": "hazard zone", "detail": "NOAH flood zone, high", "points": 15}]' then raise exception '%', t.reasons; end if;
    v_log := v_log || E'\n' || 'ok  a blocked canal in a high flood zone gets the zone''s 15 points';
  exception when others then v_log := v_log || E'\n' || 'FAIL hazard: ' || sqlerrm; end;

  -- 4. another resident nearby backs it up, both ways
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_b, 'public_safety_infrastructure', 'Usok', 'Makapal na usok galing sa kabilang bahay.', dry_lat + 0.0005, dry_lng,
          date_trunc('day', now()) + interval '7 hours')
  returning id into r_near;
  begin
    select * into t from public.report_triage where report_id = r_near;
    if not t.reasons @> '[{"factor": "nearby reports", "points": 8}]' then raise exception 'new: %', t.reasons; end if;
    select * into t from public.report_triage where report_id = r_fire;
    if t.score <> 83 then raise exception 'first report not re-scored: %', t.score; end if;
    v_log := v_log || E'\n' || 'ok  a second resident nearby adds 8 to both reports';
  exception when others then v_log := v_log || E'\n' || 'FAIL corroboration: ' || sqlerrm; end;

  -- 5. duplicates
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_c, 'public_safety_infrastructure', 'Sunog sa likod', 'May sunog sa likod ng bahay, may mga bata.', dry_lat + 0.0001, dry_lng,
          date_trunc('day', now()) + interval '8 hours')
  returning id into r_dup;
  begin
    select possible_duplicates into n from public.report_triage where report_id = r_dup;
    if n < 1 then raise exception 'count %', n; end if;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    if not exists (select 1 from public.smart_duplicates(r_dup) d where d.report_id = r_fire and d.similarity > 0.5) then
      raise exception 'fire report not listed';
    end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  the same fire filed again is flagged as a possible duplicate';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL duplicates: ' || sqlerrm; end;

  -- 6. residents see none of it
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.report_triage;
    execute 'reset role';
    if n <> 0 then raise exception '% rows visible', n; end if;
    v_log := v_log || E'\n' || 'ok  a resident cannot read triage scores';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL triage visible: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_duplicates(r_dup);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident listed duplicates (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot list duplicates (refused: ' || left(sqlerrm, 80) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_retriage(null);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident re-scored reports (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot re-score (refused: ' || left(sqlerrm, 80) || ')'; end;

  -- 7. word points are capped
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'peace_order_nuisance', 'Saksak', 'May sinaksak, duguan, may sunog din at baril.', dry_lat - 0.003, dry_lng - 0.003,
          date_trunc('day', now()) + interval '6 hours')
  returning id into r_many;
  begin
    select coalesce(sum((x ->> 'points')::integer), 0) into n
      from public.report_triage, jsonb_array_elements(reasons) x
     where report_id = r_many and x ->> 'factor' = 'words';
    if n <> 45 then raise exception 'word points %', n; end if;
    v_log := v_log || E'\n' || 'ok  word points stop at the cap (45)';
  exception when others then v_log := v_log || E'\n' || 'FAIL cap: ' || sqlerrm; end;

  -- 8. night, for safety kinds
  begin
    update public.reports set created_at = date_trunc('day', now()) + interval '15 hours' where id = r_many; -- 23:00 Manila
    update public.reports set subject = 'Saksakan' where id = r_many;
    select * into t from public.report_triage where report_id = r_many;
    if not t.reasons @> '[{"factor": "night"}]' then raise exception '%', t.reasons; end if;
    v_log := v_log || E'\n' || 'ok  a peace-and-order report at 23:00 gets the night points';
  exception when others then v_log := v_log || E'\n' || 'FAIL night: ' || sqlerrm; end;

  -- 9. rules are the barangay's: change them, re-score
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    update public.smart_rules set category_points = category_points || '{"barangay_service": 30}';
    if public.smart_retriage(r_house) <> 1 then raise exception 'not re-scored'; end if;
    execute 'reset role';
    select * into t from public.report_triage where report_id = r_house;
    if t.score <> 30 or t.level <> 'normal' then raise exception 'got % %', t.score, t.level; end if;
    v_log := v_log || E'\n' || 'ok  an admin changes the rules and re-scores (10 -> 30)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL rules: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    update public.smart_rules set night_points = 99;
    get diagnostics n = row_count;
    execute 'reset role';
    if n <> 0 then raise exception 'resident changed the rules'; end if;
    v_log := v_log || E'\n' || 'ok  a resident cannot change the rules';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot change the rules (refused)'; end;

  -- 10. a broken rule never stops a filing
  begin
    update public.smart_rules set keyword_groups = '[{"label": "broken", "points": 5, "pattern": "(["}]';
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_b, 'other', 'Something', 'A complaint while the rules are broken.', dry_lat, dry_lng + 0.004)
    returning id into r_bad;
    if r_bad is null then raise exception 'not filed'; end if;
    if exists (select 1 from public.report_triage where report_id = r_bad) then raise exception 'scored anyway'; end if;
    v_log := v_log || E'\n' || 'ok  with a broken rule the report is still filed, just not scored';
  exception when others then v_log := v_log || E'\n' || 'FAIL broken rule blocked filing: ' || sqlerrm; end;

  -- 11. who to send
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(x) into j from public.smart_tanod_ranking(r_fire) x where x.tanod_id = v_tan;
    execute 'reset role';
    if j is null then raise exception 'tanod not ranked'; end if;
    if (j ->> 'metres')::integer not between 150 and 300 or jsonb_array_length(j -> 'reasons') <> 4 then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  the on-duty tanod is ranked, with distance, load, area and location reasons';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL ranking: ' || sqlerrm; end;

  -- 12. how long it takes: too few cases, so the SLA target
  insert into public.sla_policies (category, resolution_hours, accept_minutes)
  values ('animal_welfare', 48, 60) on conflict (category) do nothing;
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    select to_jsonb(x) into j from public.smart_eta('animal_welfare') x;
    execute 'reset role';
    if j ->> 'basis' <> 'target' or (j ->> 'sla_hours') is null then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  with under 5 closed cases the estimate is the SLA target';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL eta: ' || sqlerrm; end;

  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at, resolved_at, status)
    select v_b, 'animal_welfare', 'Aso', 'Asong gala sa kanto ng kalye.', dry_lat, dry_lng, now() - interval '3 days',
           now() - interval '3 days' + make_interval(hours => h), 'resolved'
      from unnest(array[2, 4, 6, 8, 10, 30]) h;
    select to_jsonb(x) into j from public.smart_eta('animal_welfare') x;
    if j ->> 'basis' <> 'past cases' or (j ->> 'median_hours')::numeric <> 7 or (j ->> 'cases')::integer <> 6 then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  with 6 closed cases the estimate is their median (7 h)';
  exception when others then v_log := v_log || E'\n' || 'FAIL eta past cases: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
