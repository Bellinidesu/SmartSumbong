-- 21_smart_explain.sql: SMART explains itself and is measured (0140). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_res uuid := gen_random_uuid(); v_oth uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid();
  r1 uuid; r2 uuid; v_d1 uuid; v_d2 uuid;
  a record; j jsonb; n integer; t text;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999931', 'Paliwanag, Admin', 'resident'), (v_res, '+639999999932', 'Paliwanag, Ana', 'resident'),
                 (v_oth, '+639999999933', 'Paliwanag, Ben', 'resident'), (v_t1, '+639999999934', 'Paliwanag, Isa', 'tanod'),
                 (v_t2, '+639999999935', 'Paliwanag, Dalawa', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_res, v_oth, v_t1, v_t2);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat), 4326), last_location_at = now() where id = v_t1;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat + 0.01), 4326), last_location_at = now() where id = v_t2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'public_safety_infrastructure', 'Kuryente', 'May live wire na nakalaylay, may bata sa tabi.', lat, lng, now() + interval '1 day') returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'barangay_service', 'Ilaw', 'Patay ang ilaw sa poste.', lat + 0.0005, lng, now() + interval '1 day') returning id into r2;
  v_log := 'setup ok';

  -- SMART's ranking of the tanod the admin chose is saved with the dispatch
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    v_d1 := public.admin_dispatch(r1, v_t2, 'Puntahan po');   -- the farther tanod: not SMART's first choice
    select smart_rank, smart_of, smart_reasons into a from public.dispatches where id = v_d1;
    if a.smart_rank <> 2 or a.smart_of <> 2 then raise exception 'rank % of %', a.smart_rank, a.smart_of; end if;
    if jsonb_array_length(a.smart_reasons) < 3 then raise exception 'no reasons saved'; end if;
    v_d2 := public.admin_dispatch(r2, v_t1, 'Puntahan po');   -- the nearer one: SMART's first choice
    select smart_rank into n from public.dispatches where id = v_d2;
    if n <> 1 then raise exception 'second pick ranked %', n; end if;
    if (select count(*) from public.smart_events where kind = 'picked' and report_id in (r1, r2)) <> 2 then raise exception 'events not written'; end if;
    j := public.smart_pick_stats(30);
    if (j ->> 'ranked')::int < 2 or (j ->> 'top_pick')::int < 1 or (j ->> 'top_pick_pct') is null then raise exception 'stats %', j; end if;
    v_log := v_log || E'\n' || 'ok  an admin''s dispatch saves SMART''s rank of the tanod chosen, with the reasons, and the stats count the top picks';
  exception when others then v_log := v_log || E'\n' || 'FAIL picks: ' || sqlerrm; end;

  -- "Was it fixed?": asked when resolved, answered once by the owner
  begin
    update public.reports set status = 'resolved', resolved_at = now() where id = r1;
    if (select count(*) from public.resolution_checks where report_id = r1 and answered_at is null) <> 1 then raise exception 'no check asked'; end if;
    if not exists (select 1 from public.notifications where user_id = v_res and report_id = r1 and message like 'Naayos na ba%') then raise exception 'the resident was not told'; end if;
    update public.reports set status = 'resolved' where id = r1;   -- not a new resolution: not asked twice
    if (select count(*) from public.resolution_checks where report_id = r1) <> 1 then raise exception 'asked twice'; end if;
    v_log := v_log || E'\n' || 'ok  resolving a case asks the resident "Was it fixed?", once, and tells them';
  exception when others then v_log := v_log || E'\n' || 'FAIL asked: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_oth::text, true);
    begin perform public.confirm_fix(r1, true); raise exception 'someone else answered';
    exception when raise_exception then if sqlerrm not like '%nothing to confirm%' then raise; end if; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.confirm_fix(r1, false, 'Bumalik po ang problema');
    if (select fixed from public.resolution_checks where report_id = r1) is not false then raise exception 'answer not saved'; end if;
    if not exists (select 1 from public.notifications where user_id = v_adm and report_id = r1 and message like '%is not fixed%') then raise exception 'admins not told'; end if;
    if not exists (select 1 from public.smart_events where kind = 'fix_answered' and report_id = r1) then raise exception 'no event'; end if;
    begin perform public.confirm_fix(r1, true); raise exception 'answered twice';
    exception when raise_exception then if sqlerrm not like '%nothing to confirm%' then raise; end if; end;
    v_log := v_log || E'\n' || 'ok  only the owner answers, once; "not fixed" tells every administrator';
  exception when others then v_log := v_log || E'\n' || 'FAIL answer: ' || sqlerrm; end;

  -- "not fixed" is a stage of the SMART queue until the barangay answers or reopens
  begin
    select stage, next_action into a from public._smart_queue() where report_id = r1;
    if a.stage is distinct from 'recheck' then raise exception 'stage %', a.stage; end if;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    perform public.post_report_message(r1, 'Titingnan po namin ulit.');
    if exists (select 1 from public._smart_queue() where report_id = r1) then raise exception 'still queued after the barangay answered'; end if;

    update public.reports set status = 'resolved', resolved_at = now() where id = r2;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.confirm_fix(r2, false);
    if (select stage from public._smart_queue() where report_id = r2) is distinct from 'recheck' then raise exception 'r2 not queued'; end if;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    perform public.reopen_report(r2, 'Bumalik ang problema');
    if (select handled_at from public.resolution_checks where report_id = r2 and fixed is false) is null then raise exception 'reopening did not answer it'; end if;
    if (select stage from public._smart_queue() where report_id = r2) = 'recheck' then raise exception 'still a recheck after reopening'; end if;
    v_log := v_log || E'\n' || 'ok  a case the resident says is not fixed joins the queue (stage recheck) until the barangay answers or reopens it';
  exception when others then v_log := v_log || E'\n' || 'FAIL queue: ' || sqlerrm; end;

  -- a plain sentence for the resident
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.smart_why_order(r1);
    if j ->> 'en' not like 'Reports are handled in order%' or j ->> 'fil' not like 'Inaayos ang mga report%' then raise exception 'sentence %', j; end if;
    if j ->> 'en' ~ '[0-9]' then raise exception 'a number in the sentence'; end if;
    if j ->> 'en' not like '%public safety%' then raise exception 'the safety reason is missing: %', j ->> 'en'; end if;
    perform set_config('request.jwt.claim.sub', v_oth::text, true);
    begin perform public.smart_why_order(r1); raise exception 'someone else read it';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    if public.smart_why_order(r1) is null then raise exception 'admin cannot read it'; end if;
    v_log := v_log || E'\n' || 'ok  the resident gets a sentence in both languages, with reasons and no number; others cannot read it';
  exception when others then v_log := v_log || E'\n' || 'FAIL why: ' || sqlerrm; end;

  -- is the engine running; what it has answered
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    j := public.smart_engine_health();
    if j -> 'unscored' is null or j -> 'open_reports' is null or j -> 'routing_on' is null then raise exception 'health %', j; end if;
    j := public.smart_fix_stats(30);
    if (j ->> 'asked')::int < 2 or (j ->> 'not_fixed')::int < 2 then raise exception 'fix stats %', j; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_engine_health(); raise exception 'a resident read the health';
    exception when insufficient_privilege then null; end;
    begin perform public.smart_pick_stats(30); raise exception 'a resident read the stats';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  engine health and the fix and pick statistics are for administrators';
  exception when others then v_log := v_log || E'\n' || 'FAIL health: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
