-- 24_command_center.sql: the command center (0143). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_r1 uuid := gen_random_uuid(); v_r2 uuid := gen_random_uuid(); v_r3 uuid := gen_random_uuid();
  v_tan uuid := gen_random_uuid();
  j jsonb; k jsonb; s uuid; s2 uuid; h bigint; n integer; tok text; v_grp text; v_fuel bigint; v_school bigint; v_link uuid;
  lat double precision; lng double precision;
begin
  -- the middle of the widest part of the barangay, so places 150 m away are still inside it
  select st_y(c.center), st_x(c.center) into lat, lng from public.barangay_boundary b, st_maximuminscribedcircle(b.geom::geometry) c where b.id = 1;
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999961', 'Utos, Admin', 'resident'), (v_r1, '+639999999962', 'Utos, Isa', 'resident'),
                 (v_r2, '+639999999963', 'Utos, Dalawa', 'resident'), (v_r3, '+639999999964', 'Utos, Tatlo', 'resident'),
                 (v_tan, '+639999999965', 'Utos, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_r1, v_r2, v_r3, v_tan);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty' where id = v_tan;
  update public.users set last_geom = st_setsrid(st_makepoint(lng + 0.0028, lat), 4326)::geography, last_location_at = now() where id = v_tan;
  select grp into v_grp from public.place_kinds limit 1;
  if v_grp is null then insert into public.place_kinds (grp, label, words) values ('test', 'Test', '{}') returning grp into v_grp; end if;
  insert into public.places (source, name, kind, grp, lat, lng) values ('barangay', 'Gasolinahan sa Kanto', 'fuel', v_grp, lat + 0.00036, lng) returning id into v_fuel;
  insert into public.places (source, name, kind, grp, lat, lng) values ('barangay', 'Paaralang Elementarya ng 183', 'school', v_grp, lat + 0.00135, lng) returning id into v_school;
  perform set_config('request.jwt.claim.sub', v_adm::text, true);
  v_log := 'setup ok';
  update public.feature_switches set enabled = true where key = 'command_center';   -- 0144: it ships switched off

  -- 1. reading: depth on MMDA's gauge, phrases before words, negation, stretched letters, roots
  begin
    j := public._command_read('Hanggang tuhod na ang baha sa kanto');
    if not (j -> 'flood' ->> 'about')::boolean or j -> 'flood' ->> 'tag' <> 'knee' then raise exception 'knee %', j; end if;
    j := public._command_read('Kalahating tuhod lang ang baha');
    if j -> 'flood' ->> 'tag' <> 'half_knee' then raise exception 'half-knee read as %', j -> 'flood'; end if;
    j := public._command_read('Walang baha dito ngayon');
    if coalesce((j -> 'flood' ->> 'about')::boolean, false) then raise exception 'walang baha read as a flood: %', j; end if;
    j := public._command_read('Sunoooog sa kanto, may tao sa loob!');
    if not (j -> 'fire' ->> 'about')::boolean or j -> 'fire' ->> 'tag' <> 'people_inside' then raise exception 'fire %', j; end if;
    j := public._command_read('May bitak ang pader ng paaralan pagkatapos lumindol');
    if not (j -> 'quake' ->> 'about')::boolean or j -> 'quake' ->> 'tag' <> 'crack' then raise exception 'quake %', j; end if;
    j := public._command_read('Masakit ang tuhod ko');
    if coalesce((j -> 'flood' ->> 'about')::boolean, false) then raise exception 'a sore knee read as a flood'; end if;
    v_log := v_log || E'\n' || 'ok  reading: knee-deep, half-knee before knee, "walang baha", "sunoooog", "may tao sa loob", cracks after a quake; a sore knee is not a flood';
  exception when others then v_log := v_log || E'\n' || 'FAIL reading: ' || sqlerrm; end;

  -- 2. SMART suggests Flood Watch at three reports from residents, says why, and "not now" quiets it
  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_r1, 'environmental_waste_hazard', 'Baha sa kalye', 'Hanggang tuhod ang baha sa kalye namin.', lat, lng),
           (v_r2, 'environmental_waste_hazard', 'Baha sa tindahan', 'Baha hanggang bukung-bukong sa tapat ng tindahan.', lat + 0.0002, lng + 0.0002);
    j := public.command_suggest(null);
    if j is not null then raise exception 'suggested at two reports: %', j; end if;
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_r3, 'environmental_waste_hazard', 'Bumabaha na', 'Bumabaha na, hanggang baywang sa may ilog.', lat - 0.0003, lng);
    j := public.command_suggest(null);
    if j ->> 'mode' <> 'flood' or (j ->> 'reports')::int <> 3 or (j ->> 'residents')::int <> 3 then raise exception 'suggestion %', j; end if;
    if j ->> 'why_en' not like '3 reports in the last 3 hours mention flood water, from 3 residents.' then raise exception 'why %', j ->> 'why_en'; end if;
    perform public.command_dismiss('flood', 2);
    if public.command_suggest(null) is not null then raise exception 'not now did not quiet it'; end if;
    j := public.command_suggest(2::smallint);
    if j ->> 'mode' <> 'typhoon' or j ->> 'why_en' not like 'PAGASA Wind Signal No. 2%' then raise exception 'signal %', j; end if;
    v_log := v_log || E'\n' || 'ok  SMART suggests Flood Watch at three reports from three residents, in words; "not now" quiets it; a PAGASA signal suggests Typhoon Board';
  exception when others then v_log := v_log || E'\n' || 'FAIL suggestion: ' || sqlerrm; end;

  -- 3. turning Flood Watch on, its board, its checklist, a handover
  begin
    begin perform public.command_start('flood', 'x'); raise exception 'a reason of one letter';
    exception when check_violation then null; end;
    s := public.command_start('flood', 'Malakas ang ulan, bumabaha na sa tatlong kalye');
    begin perform public.command_start('flood', 'Ulit'); raise exception 'turned on twice';
    exception when check_violation then null; end;
    if public.command_suggest(null) ->> 'mode' = 'flood' then raise exception 'suggests the mode that is on'; end if;
    j := public.command_board(null, null);
    if j ->> 'mode' <> 'flood' or not (j ->> 'live')::boolean or (j -> 'counts' ->> 'reports')::int <> 3 then raise exception 'board %', j -> 'counts'; end if;
    if j -> 'tags' -> 0 ->> 'tag' <> 'waist' then raise exception 'worst depth %', j -> 'tags'; end if;
    if jsonb_array_length(j -> 'cells') < 1 or j -> 'cells' -> 0 -> 'outline' ->> 'type' <> 'Polygon' then raise exception 'cells %', j -> 'cells'; end if;
    if jsonb_array_length(j -> 'checklist') <> 5 or (j -> 'checklist' -> 0 ->> 'done')::boolean then raise exception 'checklist %', j -> 'checklist'; end if;
    if (j -> 'tanods' ->> 'on_duty')::int < 1 then raise exception 'tanods %', j -> 'tanods'; end if;
    perform public.command_check('evac', true, 'Bukas ang covered court');
    begin perform public.command_check('nope', true); raise exception 'ticked a made-up item';
    exception when check_violation then null; end;
    j := public.command_board(null, null);
    if not exists (select 1 from jsonb_array_elements(j -> 'checklist') c where c ->> 'key' = 'evac' and (c ->> 'done')::boolean) then raise exception 'evac not done'; end if;
    begin perform public.command_handover('ok'); raise exception 'a handover of two letters';
    exception when check_violation then null; end;
    h := public.command_handover('Bukas ang covered court; tatlong kalye ang may baha');
    j := public.command_board(null, null);
    if j -> 'handover' ->> 'note' not like 'Bukas ang covered court%' then raise exception 'handover %', j -> 'handover'; end if;
    if (select (snapshot ->> 'checklist_done')::int from public.command_handovers where id = h) <> 1 then raise exception 'handover snapshot'; end if;
    v_log := v_log || E'\n' || 'ok  Flood Watch: on with a reason, once; the board counts, ranks the depth, draws cells; checklist ticks; a handover keeps a note and the counts';
  exception when others then v_log := v_log || E'\n' || 'FAIL flood: ' || sqlerrm; end;

  -- 4. switching to Fire Surroundings: the flood session closes; what is within 50, 100, 200 m; the nearest tanod
  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_r1, 'public_safety_infrastructure', 'Sunog', 'May sunog sa kanto, may tao sa loob ng bahay.', lat, lng);
    s2 := public.command_start('fire', 'Sunog sa kanto ayon sa residente');
    if (select end_note from public.command_sessions where id = s) <> 'Switched to Fire Surroundings.' then raise exception 'flood not closed'; end if;
    j := public.command_board(null, null);
    if j ->> 'mode' <> 'fire' or jsonb_array_length(j -> 'sites') <> 1 then raise exception 'sites %', j -> 'sites'; end if;
    k := j -> 'sites' -> 0;
    if k ->> 'tag' <> 'people_inside' then raise exception 'site tag %', k ->> 'tag'; end if;
    if (k -> 'rings' -> 0 ->> 'metres')::int <> 50 or (k -> 'rings' -> 0 ->> 'places')::int < 1 or k -> 'rings' -> 0 -> 'named' -> 0 ->> 'kind' <> 'fuel' then raise exception 'ring 50 %', k -> 'rings' -> 0; end if;
    if (k -> 'rings' -> 2 ->> 'places')::int < 1 then raise exception 'ring 200 %', k -> 'rings' -> 2; end if;
    if (k -> 'rings' -> 1 ->> 'other_reports')::int + (k -> 'rings' -> 0 ->> 'other_reports')::int < 1 then raise exception 'flood reports near the fire not counted: %', k -> 'rings'; end if;
    if jsonb_array_length(k -> 'tanods') <> 1 or (k -> 'tanods' -> 0 ->> 'metres')::int not between 250 and 350 then raise exception 'tanod %', k -> 'tanods'; end if;
    v_log := v_log || E'\n' || 'ok  switching closes the flood session; Fire Surroundings names what is within 50/100/200 m and the nearest tanod on duty';
  exception when others then v_log := v_log || E'\n' || 'FAIL fire: ' || sqlerrm; end;

  -- 5. Quake Check lists the public buildings to check; a place is marked; the feed; the mode ends only with a note
  begin
    j := public.command_board('quake', null);
    if not exists (select 1 from jsonb_array_elements(j -> 'places') p where (p ->> 'id')::bigint = v_school) then raise exception 'school not listed'; end if;
    if exists (select 1 from jsonb_array_elements(j -> 'places') p where (p ->> 'id')::bigint = v_fuel) then raise exception 'a fuel station on the quake list'; end if;
    if (j ->> 'live')::boolean then raise exception 'quake shown as live'; end if;
    perform public.command_place_check(v_school, 'damage', 'May bitak sa hagdan');
    begin perform public.command_place_check(v_school, 'fine'); raise exception 'a made-up status';
    exception when check_violation then null; end;
    j := public.command_feed(40);
    if (select count(*) from jsonb_array_elements(j) f where f ->> 'kind' = 'filed') < 4 then raise exception 'feed filed %', j; end if;
    if not exists (select 1 from jsonb_array_elements(j) f where f ->> 'kind' = 'check') or not exists (select 1 from jsonb_array_elements(j) f where f ->> 'kind' = 'place') then raise exception 'feed checks'; end if;
    begin perform public.command_end(''); raise exception 'ended without a note';
    exception when check_violation then null; end;
    perform public.command_end('Naapula na ang sunog, ligtas ang lahat');
    if (public._command_active()).id is not null then raise exception 'still on'; end if;
    if (select count(*) from public.command_handovers where session_id = s2 and final) <> 1 then raise exception 'final handover'; end if;
    v_log := v_log || E'\n' || 'ok  Quake Check lists schools, not fuel stations; a place is marked; the feed shows filings, ticks and places; ending needs a note';
  exception when others then v_log := v_log || E'\n' || 'FAIL quake: ' || sqlerrm; end;

  -- 6. the auto switch: off, nothing happens; on, SMART turns on what it would suggest, and says so
  begin
    perform public._command_auto();
    if (public._command_active()).id is not null then raise exception 'switched on with the auto switch off'; end if;
    perform public.command_set_auto(true);
    perform public._command_auto();
    if (public._command_active()).mode is distinct from 'flood' or (public._command_active()).how <> 'auto' or (public._command_active()).started_by is not null then
      raise exception 'auto %', to_jsonb(public._command_active());
    end if;
    if not exists (select 1 from public.notifications where user_id = v_adm and message like 'SMART turned on Flood Watch%') then raise exception 'admins not told'; end if;
    perform public._command_auto();   -- already on: nothing more
    if (select count(*) from public.command_sessions where ended_at is null) <> 1 then raise exception 'two sessions'; end if;
    v_log := v_log || E'\n' || 'ok  the auto switch: off does nothing; on turns on Flood Watch as SMART, tells the administrators, and never twice';
  exception when others then v_log := v_log || E'\n' || 'FAIL auto: ' || sqlerrm; end;

  -- 7. the hall display: counts only, by a link that can be turned off; the app banner; residents refused
  begin
    tok := public.command_display_link_create('Hall TV');
    if tok !~ '^[0-9a-f]{48}$' then raise exception 'token %', tok; end if;
    if exists (select 1 from public.command_display_links where token_sha256 = tok) then raise exception 'the secret was stored'; end if;
    if public.command_hall('0123') is not null or public.command_hall(repeat('a', 48)) is not null then raise exception 'a wrong link read'; end if;
    j := public.command_hall(tok);
    if j is null or j -> 'mode' ->> 'mode' <> 'flood' or (j -> 'mode' ->> 'reports')::int < 3 then raise exception 'hall %', j; end if;
    if j::text ~* '(SS-|tracking|subject|"lat"|"lng"|utos|kalye|ilog|tindahan)' then raise exception 'the hall shows more than counts: %', j; end if;
    select id into v_link from public.command_display_links where label = 'Hall TV';
    perform public.command_display_link_revoke(v_link);
    if public.command_hall(tok) is not null then raise exception 'a turned-off link still reads'; end if;
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    if public.command_now() ->> 'mode' <> 'flood' then raise exception 'tanod banner'; end if;
    perform set_config('request.jwt.claim.sub', v_r1::text, true);
    if public.command_now() is not null then raise exception 'a resident saw the banner'; end if;
    begin perform public.command_board(null, null); raise exception 'a resident read the board';
    exception when insufficient_privilege then null; end;
    begin perform public.command_start('fire', 'Gusto ko lang'); raise exception 'a resident turned a mode on';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    v_log := v_log || E'\n' || 'ok  the hall display shows counts only, by a link kept as a hash and turned off at will; tanods see the banner; residents are refused';
  exception when others then v_log := v_log || E'\n' || 'FAIL hall: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
