-- 17_push_choices.sql: the alerts each person sets up, and their browsers (0136). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid; v_tan uuid; v_res uuid; v_other uuid;
  r_mine uuid; r_theirs uuid; n_id uuid;
  j jsonb; n integer; h integer := extract(hour from now() at time zone 'Asia/Manila');
  k text := repeat('B', 87); a text := repeat('C', 22);
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_adm := gen_random_uuid(); v_tan := gen_random_uuid(); v_res := gen_random_uuid(); v_other := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999961', 'Alerto, Admin', 'resident'), (v_tan, '+639999999962', 'Alerto, Tanod', 'tanod'),
                 (v_res, '+639999999963', 'Alerto, Ana', 'resident'), (v_other, '+639999999964', 'Alerto, Ben', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_tan, v_res, v_other);
  update public.users set role = 'admin' where id = v_adm;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'barangay_service', 'Ilaw', 'Patay ang ilaw sa poste.', lat, lng) returning id into r_mine;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_other, 'barangay_service', 'Kanal', 'Barado ang kanal.', lat + 0.001, lng) returning id into r_theirs;
  update public.reports set handler_id = v_adm where id = r_mine;
  insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r_theirs, v_tan, v_adm, 'assigned');
  insert into public.device_tokens (user_id, fcm_token) values (v_adm, 'phone-token');
  v_log := 'setup ok';

  -- out of the box: every notification is pushed, to the person's phones
  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_adm, r_theirs, 'escalation', 't') returning id into n_id;
    j := public.push_plan(n_id);
    if not (j ->> 'send')::boolean then raise exception 'held: %', j ->> 'why'; end if;
    if j -> 'tokens' <> '["phone-token"]' or jsonb_array_length(j -> 'web') <> 0 then raise exception 'where: %', j; end if;
    v_log := v_log || E'\n' || 'ok  out of the box every notification is pushed, to that person''s phones';
  exception when others then v_log := v_log || E'\n' || 'FAIL default: ' || sqlerrm; end;

  begin
    update public.users set muted_notification_kinds = '{escalation}' where id = v_adm;
    if public.push_plan(n_id) ->> 'why' is distinct from 'muted' then raise exception 'a muted kind went through'; end if;
    update public.users set muted_notification_kinds = '{}' where id = v_adm;
    v_log := v_log || E'\n' || 'ok  a kind the person muted is held back';
  exception when others then v_log := v_log || E'\n' || 'FAIL muted: ' || sqlerrm; end;

  -- only my cases: ones I handle, was dispatched to, or reported
  begin
    update public.users set push_scope = 'mine' where id in (v_adm, v_tan, v_res);
    if public.push_plan(n_id) ->> 'why' is distinct from 'not their case' then raise exception 'someone else''s case went through'; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (v_adm, r_mine, 'escalation', 't') returning id into n_id;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'the case they handle was held'; end if;
    insert into public.notifications (user_id, kind, message) values (v_adm, 'verification', 't') returning id into n_id;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'a notice about no case was held'; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (v_tan, r_theirs, 'assignment', 't') returning id into n_id;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'the tanod''s own dispatch was held'; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (v_res, r_mine, 'status_change', 't') returning id into n_id;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'the resident''s own report was held'; end if;
    update public.users set push_scope = 'all' where id in (v_adm, v_tan, v_res);
    v_log := v_log || E'\n' || 'ok  "only my cases" passes the cases they handle, were sent to or reported, and notices about no case';
  exception when others then v_log := v_log || E'\n' || 'FAIL mine: ' || sqlerrm; end;

  -- quiet hours, Manila time, urgent let through if they say so
  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_adm, r_mine, 'sla_warning', 't') returning id into n_id;
    update public.users set push_quiet_from = h, push_quiet_to = (h + 1) % 24 where id = v_adm;
    if public.push_plan(n_id) ->> 'why' is distinct from 'quiet hours' then raise exception 'not held in quiet hours'; end if;
    update public.users set push_quiet_from = (h + 23) % 24, push_quiet_to = (h + 1) % 24 where id = v_adm;   -- across midnight when h is 0
    if public.push_plan(n_id) ->> 'why' is distinct from 'quiet hours' then raise exception 'a window around this hour did not hold'; end if;
    update public.users set push_quiet_from = (h + 2) % 24, push_quiet_to = (h + 3) % 24 where id = v_adm;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'held outside quiet hours'; end if;
    update public.users set push_quiet_from = h, push_quiet_to = (h + 1) % 24 where id = v_adm;
    update public.report_triage set override_level = 'urgent' where report_id = r_mine;
    if not found then insert into public.report_triage (report_id, score, level, reasons, override_level) values (r_mine, 90, 'urgent', '[]', 'urgent'); end if;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'an urgent case was held'; end if;
    update public.users set push_quiet_urgent = false where id = v_adm;
    if public.push_plan(n_id) ->> 'why' is distinct from 'quiet hours' then raise exception 'urgent went through though they said no'; end if;
    v_log := v_log || E'\n' || 'ok  quiet hours hold pushes (also across midnight), urgent cases through only if they choose';
  exception when others then v_log := v_log || E'\n' || 'FAIL quiet: ' || sqlerrm; end;

  begin
    insert into public.notifications (user_id, kind, message, is_read) values (v_adm, 'test', 't', true) returning id into n_id;
    update public.users set muted_notification_kinds = '{test}', push_scope = 'mine' where id = v_adm;
    if not (public.push_plan(n_id) ->> 'send')::boolean then raise exception 'a test alert was held'; end if;
    update public.users set muted_notification_kinds = '{}', push_scope = 'all', push_quiet_from = null, push_quiet_to = null where id = v_adm;
    v_log := v_log || E'\n' || 'ok  a test alert passes every choice';
  exception when others then v_log := v_log || E'\n' || 'FAIL test alert: ' || sqlerrm; end;

  -- browsers, as the person
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    begin
      perform public.web_push_subscribe('https://evil.example/collect', k, a, 'x');
      raise exception 'took a push address that is no push service';
    exception when check_violation then null; end;
    perform public.web_push_subscribe('https://fcm.googleapis.com/fcm/send/adm-1', k, a, 'Chrome on Windows');
    for n in 1..11 loop perform public.web_push_subscribe('https://updates.push.services.mozilla.com/wpush/v2/adm-' || n, k, a, 'Firefox'); end loop;
    select count(*) into n from public.web_push_subscriptions;
    if n <> 10 then raise exception '% browsers kept, not 10', n; end if;
    perform public.set_push_choices('mine', 22::smallint, 6::smallint, true);
    begin perform public.set_push_choices('mine', 22::smallint, null, true); raise exception 'took a start with no end';
    exception when raise_exception then if sqlerrm not like '%start and an end%' then raise; end if; end;
    perform public.push_test();
    begin perform public.push_test(); raise exception 'two tests in a minute';
    exception when raise_exception then if sqlerrm not like '%One test a minute%' then raise; end if; end;
    begin perform public.push_plan(n_id); raise exception 'a person read a push plan';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    if (select push_quiet_from from public.users where id = v_adm) <> 22 then raise exception 'choices not saved'; end if;
    v_log := v_log || E'\n' || 'ok  a person adds browsers (push services only, ten at most), saves choices, tests once a minute, cannot read plans';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL browsers: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.web_push_subscriptions;
    if n <> 0 then raise exception 'saw % of someone else''s browsers', n; end if;
    perform public.web_push_unsubscribe('https://fcm.googleapis.com/fcm/send/adm-1');
    perform public.web_push_subscribe('https://updates.push.services.mozilla.com/wpush/v2/adm-11', k, a, 'Firefox');
    execute 'reset role';
    if not exists (select 1 from public.web_push_subscriptions where endpoint like '%/adm-1') then raise exception 'removed someone else''s browser'; end if;
    if (select user_id from public.web_push_subscriptions where endpoint like '%/adm-11') <> v_res then raise exception 'a browser did not follow its new sign-in'; end if;
    v_log := v_log || E'\n' || 'ok  others'' browsers stay hidden and untouched; a browser follows whoever signs in on it';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL others: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
