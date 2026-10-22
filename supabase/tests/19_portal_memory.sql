-- 19_portal_memory.sql: the portal's memory, filed from its keep-awake checks (0138). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid();
  v_req bigint := 990101;
  j json;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_adm, 'authenticated', 'authenticated', public.auth_email_for('+639999999981'),
          jsonb_build_object('full_name', 'Sukat, Admin', 'mobile_number', '+639999999981', 'role', 'resident', 'id_type', 'barangay_id',
                             'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                             'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now());
  update public.users set role = 'admin', verification_status = 'verified', verified_at = now() where id = v_adm;
  v_log := 'setup ok';

  begin
    insert into public.portal_uptime (request_id) values (v_req), (v_req + 1);
    insert into net._http_response (id, status_code, content, headers)
    values (v_req, 200, 'ok', '{"X-Portal-Memory": "used=138;peak=204;limit=512"}'),
           (v_req + 1, 200, 'ok', '{"content-type": "text/plain"}');
    perform public.ping_portal();
    if (select array[mem_used_mb, mem_peak_mb, mem_limit_mb] from public.portal_uptime where request_id = v_req) <> array[138, 204, 512] then
      raise exception 'filed %', (select array[mem_used_mb, mem_peak_mb, mem_limit_mb] from public.portal_uptime where request_id = v_req);
    end if;
    if (select ok and mem_used_mb is null from public.portal_uptime where request_id = v_req + 1) is not true then
      raise exception 'an answer without the header was not filed as plain ok';
    end if;
    v_log := v_log || E'\n' || 'ok  a check files the memory the portal reports, and an answer without it as before';
  exception when others then v_log := v_log || E'\n' || 'FAIL file: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    j := public.portal_uptime_summary();
    execute 'reset role';
    if (j ->> 'mem_now')::int <> 138 or (j ->> 'mem_limit')::int <> 512 or (j ->> 'mem_week_max')::int < 204 then raise exception 'summary %', j; end if;
    v_log := v_log || E'\n' || 'ok  Settings gets memory now, the limit and the week''s highest';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL summary: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
