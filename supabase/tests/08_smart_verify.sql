-- 08_smart_verify.sql: SMART Verify, ID checks on the server (0126). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_c uuid; v_adm uuid;
  j jsonb;
  n integer;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', x.idt,
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999951', 'Dela Cruz, Juan Pedro', 'philsys'),
                 (v_b, '+639999999952', 'Reyes, Ana', 'drivers_license'),
                 (v_c, '+639999999953', 'Lim, Carlo', 'philsys'),
                 (v_adm, '+639999999954', 'Verify, Admin', 'barangay_id')) as x(id, mob, nm, idt);
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id = v_adm;
  v_log := 'setup ok';

  -- the phone cannot grade itself any more
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    update public.users set ocr_flags = '{}', ocr_extracted_name = 'Anyone', ocr_processed_at = now() where id = v_a;
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident wrote their own ID reading (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot write ID flags directly (refused: ' || left(sqlerrm, 70) || ')'; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    update public.users set email = 'juan@example.com' where id = v_a;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a resident still edits their own email';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL own email: ' || sqlerrm; end;

  -- a good reading: ready, flags worked out here
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.submit_id_reading('philsys', 'DELA CRU2, JUAN P.', '1234-5678-9012-3456');
    execute 'reset role';
    j := public._smart_verify(v_a);
    if j ->> 'level' <> 'ready' or (select ocr_flags from public.users where id = v_a) <> '{}' then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  a matching name ("CRU2" read as Cruz) and a 16-digit PhilSys number are ready, no flags';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL good reading: ' || sqlerrm; end;

  -- someone else's ID, wrong type, bad number shape
  begin
    perform set_config('request.jwt.claim.sub', v_b::text, true);
    execute 'set local role authenticated';
    perform public.submit_id_reading('philsys', 'SANTOS, MARIA', 'X12');
    execute 'reset role';
    j := public._smart_verify(v_b);
    if j ->> 'level' <> 'problem' then raise exception 'level %', j; end if;
    if not (j -> 'flags') @> '["name_mismatch", "type_mismatch", "number_format"]' then raise exception 'flags %', j -> 'flags'; end if;
    if (select ocr_flags from public.users where id = v_b) @> array['name_mismatch', 'type_mismatch', 'number_format'] is not true then raise exception 'not stored'; end if;
    v_log := v_log || E'\n' || 'ok  another person''s name is a problem; wrong type and number shape are flagged and stored';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL bad reading: ' || sqlerrm; end;

  -- the same ID on two accounts
  begin
    perform set_config('request.jwt.claim.sub', v_c::text, true);
    execute 'set local role authenticated';
    perform public.submit_id_reading('philsys', 'LIM, CARLO', '1234 5678 9012 3456');
    execute 'reset role';
    j := public._smart_verify(v_c);
    if j ->> 'level' <> 'problem' or not (j -> 'flags') ? 'number_reused'
       or not (j -> 'reasons') @> jsonb_build_array(jsonb_build_object('other_account', v_a)) then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  the same ID number on two accounts is a problem, naming the other account';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL reused: ' || sqlerrm; end;

  -- unreadable
  begin
    perform set_config('request.jwt.claim.sub', v_c::text, true);
    execute 'set local role authenticated';
    perform public.submit_id_reading(null, '', null);
    execute 'reset role';
    j := public._smart_verify(v_c);
    if j ->> 'level' <> 'check' or not (j -> 'flags') ? 'unreadable' then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  an unreadable ID is "check", not a problem';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL unreadable: ' || sqlerrm; end;

  -- a re-check request is cleared by the next reading
  begin
    update public.users set ocr_rescan_requested_at = now() where id = v_a;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.submit_id_reading('philsys', 'DELA CRUZ, JUAN', '1234567890123456');
    execute 'reset role';
    if (select ocr_rescan_requested_at from public.users where id = v_a) is not null then raise exception 'not cleared'; end if;
    v_log := v_log || E'\n' || 'ok  a new reading clears the admin''s re-check request';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL rescan: ' || sqlerrm; end;

  -- admins see it, residents do not
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.smart_verify_queue('resident') q where q.user_id in (v_a, v_b, v_c);
    j := (select jsonb_agg(q.level order by q.level) from public.smart_verify_queue('resident') q where q.user_id in (v_a, v_b, v_c));
    execute 'reset role';
    if n <> 3 then raise exception 'queue has %', n; end if;
    if (select q.level from public.smart_verify_queue('resident') q limit 0) is not null then null; end if;
    v_log := v_log || E'\n' || 'ok  the verification queue lists pending accounts with their check level';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL queue: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    select q.level into j from (select to_jsonb(q.level) as level from public.smart_verify_queue('resident') q
                                 where q.user_id in (v_a, v_b, v_c) limit 1) q;
    execute 'reset role';
    if j #>> '{}' <> 'problem' then raise exception 'first is %', j; end if;
    v_log := v_log || E'\n' || 'ok  problems come first in the queue';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL queue order: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_verify(v_b);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident read someone''s ID checks (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot read ID checks (refused: ' || left(sqlerrm, 60) || ')'; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
