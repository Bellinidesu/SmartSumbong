-- 20_reroute_guard.sql: the reroute queue cannot log without end (0139). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_res uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid();
  r1 uuid; r2 uuid; r3 uuid; v_d uuid;
  n integer; n0 integer; v_max smallint; i integer;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999991', 'Linya, Admin', 'resident'), (v_res, '+639999999992', 'Linya, Ana', 'resident'),
                 (v_tan, '+639999999993', 'Linya, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_res, v_tan);
  update public.users set role = 'admin' where id = v_adm;
  select max_dispatch_attempts into v_max from public.operational_settings where id = 1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'barangay_service', 'Ilaw', 'Patay ang ilaw sa poste.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'barangay_service', 'Kanal', 'Barado ang kanal.', lat + 0.001, lng) returning id into r2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'barangay_service', 'Daan', 'May lubak sa daan.', lat - 0.001, lng) returning id into r3;
  v_log := 'setup ok';

  -- a reroute that finds no one joins the waiting line, and retrying it writes nothing new
  begin
    perform public.redispatch_report(r1, 'test');
    if (select dispatch_attempts from public.reports where id = r1) <> 1 then raise exception 'attempts'; end if;
    if (select awaiting_unit_since from public.reports where id = r1) is null then raise exception 'not in the waiting line'; end if;
    select count(*) into n0 from public.status_logs where report_id = r1;
    for i in 1..6 loop perform public.sweep_awaiting_units(); end loop;
    select count(*) into n from public.status_logs where report_id = r1;
    if n <> n0 then raise exception 'the waiting line wrote % new lines in six sweeps', n - n0; end if;
    if (select count(*) from public.status_logs where report_id = r1 and remark like 'No tanod available%') <> 1 then raise exception 'the no-tanod line is not written once'; end if;
    v_log := v_log || E'\n' || 'ok  a reroute that finds no one waits in line; six sweeps write nothing new';
  exception when others then v_log := v_log || E'\n' || 'FAIL queue: ' || sqlerrm; end;

  -- past the cap: said once, the line lets go, the next offers do nothing
  begin
    update public.reports set dispatch_attempts = v_max where id = r2;
    for i in 1..4 loop perform public.redispatch_report(r2, 'test'); end loop;
    if (select count(*) from public.status_logs where report_id = r2 and remark like 'Automatic dispatch gave up%') <> 1 then
      raise exception 'gave up written % times', (select count(*) from public.status_logs where report_id = r2 and remark like 'Automatic dispatch gave up%');
    end if;
    if (select max(c) from (select count(*) c from public.notifications where report_id = r2 and kind = 'escalation' group by user_id) x) <> 1 then
      raise exception 'an administrator was told more than once';
    end if;
    if (select awaiting_unit_since from public.reports where id = r2) is not null then raise exception 'still in the line'; end if;
    select count(*) into n0 from public.status_logs where report_id = r2;
    perform public.auto_dispatch(r2);
    perform public.sweep_awaiting_units();
    select count(*) into n from public.status_logs where report_id = r2;
    if n <> n0 then raise exception 'auto_dispatch wrote after the cap'; end if;
    v_log := v_log || E'\n' || 'ok  past the cap "gave up" and its notice are written once, the line lets go, later calls are silent';
  exception when others then v_log := v_log || E'\n' || 'FAIL cap: ' || sqlerrm; end;

  -- a day in line, and it lets go
  begin
    update public.reports set status = 'validated', dispatch_attempts = 1, awaiting_unit_since = now() - interval '25 hours' where id = r3;
    perform public.sweep_awaiting_units();
    if (select awaiting_unit_since from public.reports where id = r3) is not null then raise exception 'still in the line after 25 hours'; end if;
    v_log := v_log || E'\n' || 'ok  a case leaves the waiting line after a day';
  exception when others then v_log := v_log || E'\n' || 'FAIL day: ' || sqlerrm; end;

  -- the barangay's reroute back to the system starts a fresh run
  begin
    insert into public.dispatches (report_id, tanod_id, assigned_by) values (r2, v_tan, v_adm) returning id into v_d;
    update public.reports set status = 'assigned', dispatch_attempts = v_max + 3 where id = r2;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_reroute_dispatch(v_d, 'test', null);
    execute 'reset role';
    if (select dispatch_attempts from public.reports where id = r2) <> 1 then
      raise exception 'attempts after the barangay''s reroute: %', (select dispatch_attempts from public.reports where id = r2);
    end if;
    v_log := v_log || E'\n' || 'ok  an administrator''s reroute back to the system starts a fresh run of offers';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL admin reroute: ' || sqlerrm; end;

  -- the guard under every system line
  begin
    for i in 1..2 loop
      insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
      values (r3, v_res, 'validated', 'validated', 'A system line', true);
    end loop;
    if (select count(*) from public.status_logs where report_id = r3 and remark = 'A system line') <> 1 then raise exception 'a repeated system line was written'; end if;
    for i in 1..2 loop
      insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
      values (r3, v_adm, 'validated', 'validated', 'A person''s note');
    end loop;
    if (select count(*) from public.status_logs where report_id = r3 and remark = 'A person''s note') <> 2 then raise exception 'a person''s notes were merged'; end if;
    insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
    values (r3, v_res, 'validated', 'validated', 'A different system line', true);
    if (select count(*) from public.status_logs where report_id = r3 and is_system and remark like 'A %system line') <> 2 then raise exception 'a different system line was dropped'; end if;
    v_log := v_log || E'\n' || 'ok  an identical system line within ten minutes is not written again; people''s notes and different lines are';
  exception when others then v_log := v_log || E'\n' || 'FAIL guard: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
