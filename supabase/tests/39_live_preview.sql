-- 39_live_preview.sql: pairing a phone with a super admin's Control Room (0160). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_res uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid();
  j jsonb; v_code text; v_chan text; v_id uuid; n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999971', 'Preview, Super', 'resident'), (v_po, '+639999999972', 'Preview, Peace', 'resident'),
                 (v_res, '+639999999973', 'Preview, Ana', 'resident'), (v_tan, '+639999999974', 'Preview, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_po, v_res, v_tan);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_po;

  -- 1. off by default: nothing starts, nothing pairs
  begin
    if public.feature_on('live_preview') then raise exception 'live preview is on by default'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin perform public.preview_start(); raise exception 'a preview started while it was switched off'; exception when sqlstate 'P0001' then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.preview_pair('AAAAAAAA', 'phone');
    if (j->>'ok')::boolean or j->>'reason' <> 'off' then raise exception 'pairing worked while it was switched off: %', j; end if;
    v_log := v_log || E'\n' || 'ok  live preview is off by default: a super admin cannot start one and a phone cannot pair';
  exception when others then v_log := v_log || E'\n' || 'FAIL off by default: ' || sqlerrm; end;

  -- 2. only a super admin starts one; the code is shown once and kept hashed
  begin
    update public.feature_switches set enabled = true where key = 'live_preview';
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    begin perform public.preview_start(); raise exception 'a committee admin started a preview'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    begin perform public.preview_start(); raise exception 'a tanod started a preview'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.preview_start(); v_code := j->>'code'; v_chan := j->>'channel'; v_id := (j->>'id')::uuid;
    if length(v_code) <> 8 or v_code !~ '^[A-HJKMNP-Z2-9]{8}$' then raise exception 'the code is not 8 readable characters: %', v_code; end if;
    if exists (select 1 from public.preview_sessions where code_hash = v_code) then raise exception 'the code is stored in the clear'; end if;
    if length(v_chan) < 30 then raise exception 'the channel name is guessable: %', v_chan; end if;
    v_log := v_log || E'\n' || 'ok  only a super admin starts a preview; the code is 8 readable characters, stored hashed, with a long secret channel';
  exception when others then v_log := v_log || E'\n' || 'FAIL start: ' || sqlerrm; end;

  -- 3. a resident cannot read a session, a super admin reads only their own
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    select count(*) into n from public.preview_sessions; if n <> 0 then raise exception 'a resident could read % sessions', n; end if;
    perform set_config('request.jwt.claim.sub', v_po::text, true);
    select count(*) into n from public.preview_sessions; if n <> 0 then raise exception 'a committee admin could read % sessions', n; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select count(*) into n from public.preview_sessions; if n <> 1 then raise exception 'the super admin saw % sessions, not 1', n; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  residents and committee admins read no session; the super admin reads only their own';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL reading: ' || sqlerrm; end;

  -- 4. a phone trades the code once for the channel; a second phone cannot use it
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.preview_pair(lower(v_code) || ' ', 'Pixel 7');   -- case and spaces do not matter
    if not (j->>'ok')::boolean or j->>'channel' <> v_chan then raise exception 'the code did not pair: %', j; end if;
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    j := public.preview_pair(v_code, 'Other');
    if (j->>'ok')::boolean then raise exception 'a used code paired a second phone'; end if;
    if not exists (select 1 from public.preview_sessions where id = v_id and paired_by = v_res and paired_device = 'Pixel 7') then raise exception 'the pairing was not recorded'; end if;
    v_log := v_log || E'\n' || 'ok  a phone pairs once with the code (case and spaces do not matter); a used code does not pair again; the pairing is recorded';
  exception when others then v_log := v_log || E'\n' || 'FAIL pairing: ' || sqlerrm; end;

  -- 5. five wrong codes lock a person out for 15 minutes, and the tries are kept
  begin
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    for n in 1..5 loop j := public.preview_pair('ZZZZZZZZ', 'x'); if (j->>'ok')::boolean then raise exception 'a wrong code paired'; end if; end loop;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.preview_start(); v_code := j->>'code';
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    j := public.preview_pair(v_code, 'x');
    if (j->>'ok')::boolean or j->>'reason' <> 'locked' then raise exception 'five wrong codes did not lock the person out: %', j; end if;
    v_log := v_log || E'\n' || 'ok  five wrong codes lock a person out, even for a right code; the failed tries are kept';
  exception when others then v_log := v_log || E'\n' || 'FAIL lockout: ' || sqlerrm; end;

  -- 6. an expired or ended code does not pair, starting again ends the old one, and the super admin can end it
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    update public.preview_sessions set ended_at = now() where created_by = v_sup and ended_at is null;
    j := public.preview_start(); v_code := j->>'code'; v_id := (j->>'id')::uuid;
    update public.preview_sessions set expires_at = now() - interval '1 minute' where id = v_id;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.preview_pair(v_code, 'x'); if (j->>'ok')::boolean then raise exception 'an expired code paired'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.preview_start(); v_id := (j->>'id')::uuid;
    select count(*) into n from public.preview_sessions where created_by = v_sup and ended_at is null; if n <> 1 then raise exception '% open sessions, not 1', n; end if;
    perform public.preview_end(v_id);
    select count(*) into n from public.preview_sessions where created_by = v_sup and ended_at is null; if n <> 0 then raise exception 'the session was not ended'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.preview_end(v_id); raise exception 'a resident ended a preview'; exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  an expired code does not pair; starting again leaves one open session; a super admin ends it and a resident cannot';
  exception when others then v_log := v_log || E'\n' || 'FAIL expiry and end: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
