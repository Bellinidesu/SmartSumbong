-- 18_engine.sql: the engine's queue and its ID readings (0137). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_res uuid; v_done uuid; v_adm uuid;
  photo text := 'https://res.cloudinary.com/nwb2kryl/image/authenticated/v1760000000/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg';
  j record; t text; n integer; v_rid bigint;
begin
  v_res := gen_random_uuid(); v_done := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'philsys',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999971', 'Dela Cruz, Juan'), (v_done, '+639999999972', 'Makina, Ana'), (v_adm, '+639999999973', 'Makina, Admin')) as x(id, mob, nm);
  update public.users set id_image_url = photo where id = v_res;
  update public.users set id_image_url = replace(photo, '0d9c6c1e', '1d9c6c1e'), verification_status = 'verified', verified_at = now() where id = v_done;
  update public.users set role = 'admin', verification_status = 'verified', verified_at = now() where id = v_adm;
  v_log := 'setup ok';

  -- links are signed exactly as the portal signs them (cld_private_url, a reference value made with PHP)
  begin
    t := public._cld_sign(photo, 'c_limit,w_1600', 'not-a-real-secret');
    if t <> 'https://res.cloudinary.com/nwb2kryl/image/authenticated/s--Ow_mwAfX--/c_limit,w_1600/v1760000000/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg' then
      raise exception 'signed: %', t;
    end if;
    if public._cld_sign(replace(photo, '/authenticated/', '/upload/'), 'c_limit,w_1600', 'x') is not null then raise exception 'signed a public link'; end if;
    v_log := v_log || E'\n' || 'ok  a private photo link is signed as the portal signs it; nothing else is signed';
  exception when others then v_log := v_log || E'\n' || 'FAIL sign: ' || sqlerrm; end;

  begin
    if public.engine_tick() <> 'off' then raise exception 'ran without its settings'; end if;
    if exists (select 1 from public.engine_jobs) then raise exception 'queued while off'; end if;
    v_log := v_log || E'\n' || 'ok  without its address and secrets in Vault the engine stays off';
  exception when others then v_log := v_log || E'\n' || 'FAIL off: ' || sqlerrm; end;

  -- the queue: pending accounts with a private ID photo and no reading
  begin
    perform public.engine_enqueue(); perform public.engine_enqueue();
    select count(*) into n from public.engine_jobs where user_id in (v_res, v_done, v_adm);
    if n <> 1 or not exists (select 1 from public.engine_jobs where user_id = v_res and state = 'waiting' and photo_url = photo) then
      raise exception '% jobs', n;
    end if;
    v_log := v_log || E'\n' || 'ok  one reading is queued per pending account, none for verified ones, never twice';
  exception when others then v_log := v_log || E'\n' || 'FAIL queue: ' || sqlerrm; end;

  -- ask, then file the answer
  begin
    perform vault.create_secret('https://engine.test', 'engine_url');
    perform vault.create_secret('test-secret', 'engine_secret');
    perform vault.create_secret('not-a-real-secret', 'cloudinary_api_secret');
    t := public.engine_tick();
    select * into j from public.engine_jobs where user_id = v_res;
    if j.state <> 'asked' or j.request_id is null or j.tries <> 1 then raise exception 'not asked: % (%)', j.state, t; end if;
    insert into net._http_response (id, status_code, content)
    values (j.request_id, 200, '{"type":"philsys","name":"DELA CRUZ JUAN","number":"1234-5678-9012-3456","ms":900}');
    t := public.engine_tick();
    if t not like 'filed 1%' then raise exception 'tick said %', t; end if;
    if (select ocr_detected_type::text || '|' || ocr_extracted_name || '|' || ocr_extracted_number from public.users where id = v_res)
       <> 'philsys|DELA CRUZ JUAN|1234-5678-9012-3456' then raise exception 'reading not saved'; end if;
    if (select ocr_flags from public.users where id = v_res) is null then raise exception 'not judged'; end if;
    if (select state from public.engine_jobs where id = j.id) <> 'done' then raise exception 'job not done'; end if;
    if exists (select 1 from net._http_response where id = j.request_id) then raise exception 'the answer was left in pg_net'; end if;
    perform public.engine_enqueue();
    if exists (select 1 from public.engine_jobs where user_id = v_res and state = 'waiting') then raise exception 'read again'; end if;
    v_log := v_log || E'\n' || 'ok  the engine is asked with a signed link, its answer is saved and judged like the app''s, and not left behind';
  exception when others then v_log := v_log || E'\n' || 'FAIL file: ' || sqlerrm; end;

  begin
    update public.users set ocr_rescan_requested_at = clock_timestamp() where id = v_res;
    perform public.engine_enqueue();
    if not exists (select 1 from public.engine_jobs where user_id = v_res and state = 'waiting') then raise exception 'rescan not queued'; end if;
    -- three refusals and it gives up; a refusal that is not JSON is handled
    for n in 1..3 loop
      t := public.engine_tick();
      select * into j from public.engine_jobs where user_id = v_res and state in ('asked', 'waiting', 'failed') order by id desc limit 1;
      insert into net._http_response (id, status_code, content) values (j.request_id, 502, 'Bad Gateway');
      t := public.engine_tick();
    end loop;
    select * into j from public.engine_jobs where user_id = v_res order by id desc limit 1;
    if j.state <> 'failed' or j.tries <> 3 then raise exception 'after three refusals: % (% tries)', j.state, j.tries; end if;
    perform public.engine_enqueue();
    if exists (select 1 from public.engine_jobs where user_id = v_res and state = 'waiting') then raise exception 'a photo given up on came back'; end if;
    v_log := v_log || E'\n' || 'ok  a rescan the barangay asks for is queued; three refusals and the engine gives up on that photo';
  exception when others then v_log := v_log || E'\n' || 'FAIL retries: ' || sqlerrm; end;

  begin
    update public.users set id_image_url = replace(photo, '0d9c6c1e', '2d9c6c1e') where id = v_res;
    perform public.engine_enqueue();
    t := public.engine_tick();
    select * into j from public.engine_jobs where user_id = v_res and state = 'asked';
    update public.users set id_image_url = replace(photo, '0d9c6c1e', '3d9c6c1e') where id = v_res;   -- replaced while being read
    insert into net._http_response (id, status_code, content) values (j.request_id, 200, '{"type":"passport","name":"X","number":"1"}');
    t := public.engine_tick();
    if (select ocr_detected_type::text from public.users where id = v_res) = 'passport' then raise exception 'saved a reading of the old photo'; end if;
    perform public.engine_enqueue();   -- the next minute's tick
    if not exists (select 1 from public.engine_jobs where user_id = v_res and photo_url like '%3d9c6c1e%') then raise exception 'new photo not queued'; end if;
    v_log := v_log || E'\n' || 'ok  a new photo, even one sent while the old was being read, gets its own reading';
  exception when others then v_log := v_log || E'\n' || 'FAIL new photo: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    if not (public.engine_status() ->> 'configured')::boolean then raise exception 'status says off'; end if;
    begin perform public.engine_tick(); raise exception 'a person ran the engine';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_done, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_done::text, true);
    execute 'set local role authenticated';
    begin perform public.engine_status(); raise exception 'a resident read the engine''s status';
    exception when insufficient_privilege then null; end;
    select count(*) into n from public.engine_jobs;
    execute 'reset role';
    if n <> 0 then raise exception 'a resident saw % jobs', n; end if;
    v_log := v_log || E'\n' || 'ok  administrators see the engine''s status; nobody can run it by hand; residents see nothing';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
