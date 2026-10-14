-- 11_smart_queue.sql: the SMART queue and the dispatch waiting line (0129). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_c uuid; v_tan uuid; v_adm uuid;
  r_fire uuid; r_stab uuid; r_old uuid; r_new uuid;
  r_appr uuid; r_reply uuid; r_esc uuid; r_disp uuid; r_acc uuid; r_late uuid;
  w_old uuid; w_fire uuid;
  ids uuid[];
  j jsonb;
  n integer;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid(); v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999981', 'Pila, Ana', 'resident'),
                 (v_b, '+639999999982', 'Pila, Ben', 'resident'),
                 (v_c, '+639999999983', 'Pila, Cora', 'resident'),
                 (v_tan, '+639999999984', 'Pila, Tanod', 'tanod'),
                 (v_adm, '+639999999985', 'Pila, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_c, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  v_log := 'setup ok';

  -- 1. order: urgency plus waiting
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'public_safety_infrastructure', 'Sunog', 'May sunog sa likod ng bahay, may bata sa loob.', lat, lng, date_trunc('day', now()) + interval '7 hours')
  returning id into r_fire;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_b, 'peace_order_nuisance', 'Saksak', 'May sinaksak sa inuman kanina.', lat + 0.0003, lng, date_trunc('day', now()) + interval '7 hours')
  returning id into r_stab;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_c, 'barangay_service', 'Clearance', 'Matagal ang pagkuha ng barangay clearance.', lat - 0.0003, lng, now() - interval '50 hours')
  returning id into r_old;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa gilid ng kalsada.', lat - 0.0005, lng, now() - interval '10 minutes')
  returning id into r_new;
  update public.reports set created_at = now() - interval '5 minutes' where id in (r_fire, r_stab);
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select array_agg(q.report_id order by q.priority desc) into ids
      from public.smart_queue('review', 500) q where q.report_id in (r_fire, r_stab, r_old, r_new);
    select to_jsonb(q) into j from public.smart_queue('review', 500) q where q.report_id = r_old;
    execute 'reset role';
    if ids <> array[r_fire, r_stab, r_old, r_new] then raise exception 'order %', ids; end if;
    if (j ->> 'priority')::integer <> 50 or not (j -> 'reasons') @> '[{"factor": "waiting", "points": 40}]' then raise exception 'old %', j; end if;
    v_log := v_log || E'\n' || 'ok  fire (75), stabbing (60), a clearance waiting 50 h (10 + 40 for waiting), fresh rubbish (25): in that order';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL order: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_override(r_new, 'urgent', 'Blocking the fire lane.');
    select (q.reasons -> 0 ->> 'points')::integer into n from public.smart_queue('review', 500) q where q.report_id = r_new;
    execute 'reset role';
    if n <> 80 then raise exception 'base %', n; end if;
    v_log := v_log || E'\n' || 'ok  an admin''s urgent counts as 80 in the queue';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL override: ' || sqlerrm; end;

  -- 2. stages and next actions
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, resolution_submitted_at)
  values (v_a, 'street_obstruction', 'Harang', 'May harang sa bangketa sa harap.', lat + 0.01, lng, 'in_progress', now() - interval '2 hours')
  returning id into r_appr;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_b, 'street_obstruction', 'Harang', 'May harang ulit sa eskinita.', lat + 0.011, lng, 'in_progress')
  returning id into r_reply;
  insert into public.report_messages (report_id, author_id, from_barangay, body, created_at)
  values (r_reply, v_adm, true, 'Pupuntahan po.', now() - interval '3 hours'),
         (r_reply, v_b, false, 'Wala pa pong dumarating.', now() - interval '1 hour');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_c, 'street_obstruction', 'Harang', 'Malaking truck na nakaharang sa daan.', lat + 0.012, lng, 'in_progress')
  returning id into r_esc;
  insert into public.escalation_requests (report_id, requested_by, reason) values (r_esc, v_tan, 'Needs the city towing unit.');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_a, 'animal_welfare', 'Aso', 'Asong gala sa kanto ng eskinita.', lat + 0.013, lng, 'validated')
  returning id into r_disp;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_b, 'animal_welfare', 'Aso', 'Asong gala sa harap ng tindahan.', lat + 0.014, lng, 'assigned')
  returning id into r_acc;
  insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r_acc, v_tan, v_adm, 'assigned');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, due_at)
  values (v_c, 'animal_welfare', 'Aso', 'Asong gala sa likod ng kapilya.', lat + 0.015, lng, 'in_progress', now() - interval '1 hour')
  returning id into r_late;
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select jsonb_object_agg(q.report_id::text, q.stage) into j from public.smart_queue(null, 500) q
     where q.report_id in (r_appr, r_reply, r_esc, r_disp, r_acc, r_fire);
    execute 'reset role';
    if j ->> r_appr::text <> 'approve' or j ->> r_reply::text <> 'reply' or j ->> r_esc::text <> 'escalation'
       or j ->> r_disp::text <> 'dispatch' or j ->> r_acc::text <> 'accept' or j ->> r_fire::text <> 'review' then
      raise exception '%', j;
    end if;
    v_log := v_log || E'\n' || 'ok  each case gets its next action: approve, reply, escalation, assign, wait for accept, review';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL stages: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select to_jsonb(q) into j from public.smart_queue(null, 500) q where q.report_id = r_late;
    execute 'reset role';
    if not (j -> 'reasons') @> '[{"factor": "overdue", "points": 20}]' then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  a case past its deadline gets 20 more, with the reason';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL overdue: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform * from public.smart_queue();
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident read the queue (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot read the queue (refused: ' || left(sqlerrm, 60) || ')'; end;

  -- 3. the dispatch waiting line: one free tanod, two waiting reports
  delete from public.dispatches where tanod_id = v_tan;
  update public.operational_settings set max_active_dispatches = 1 where id = 1;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat), 4326), last_location_at = now() where id = v_tan;
  update public.reports set awaiting_unit_since = null where awaiting_unit_since is not null;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, created_at, awaiting_unit_since)
  values (v_c, 'barangay_service', 'Cedula', 'Kailangan ng tulong sa cedula ng lola.', lat, lng + 0.001, 'validated', now() - interval '3 hours', now() - interval '3 hours')
  returning id into w_old;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, created_at, awaiting_unit_since)
  values (v_b, 'public_safety_infrastructure', 'Sunog', 'Nasusunog ang tindahan, may mga bata!', lat, lng + 0.002, 'validated', now() - interval '20 minutes', now() - interval '20 minutes')
  returning id into w_fire;
  begin
    perform public.sweep_awaiting_units();
    if not exists (select 1 from public.dispatches where report_id = w_fire and tanod_id = v_tan) then raise exception 'fire not sent'; end if;
    if exists (select 1 from public.dispatches where report_id = w_old) then raise exception 'older one took the tanod'; end if;
    v_log := v_log || E'\n' || 'ok  when one tanod is free, the fire waiting 20 min goes before the cedula waiting 3 h';
  exception when others then v_log := v_log || E'\n' || 'FAIL waiting line: ' || sqlerrm; end;

  begin
    delete from public.dispatches where report_id in (w_fire, w_old);
    update public.reports set status = 'validated', awaiting_unit_since = created_at where id in (w_fire, w_old);
    update public.smart_rules set smart_queue = false where id = 1;
    perform public.sweep_awaiting_units();
    if not exists (select 1 from public.dispatches where report_id = w_old and tanod_id = v_tan) then raise exception 'not first come'; end if;
    v_log := v_log || E'\n' || 'ok  with the SMART queue off, the waiting line is first come, first served again';
  exception when others then v_log := v_log || E'\n' || 'FAIL queue off: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
