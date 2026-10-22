-- 16_places.sql: places and their search (0134). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_admin uuid; v_res uuid;
  r record; n integer; t text; v_id bigint; v_req bigint;
  v_elems jsonb;
  v_m integer[];
begin
  v_admin := gen_random_uuid(); v_res := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_admin, '+639999999951', 'Lugar, Admin'), (v_res, '+639999999952', 'Lugar, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_admin, v_res);
  update public.users set role = 'admin' where id = v_admin;
  v_log := 'setup ok';

  -- the curated landmarks are the barangay's own places
  begin
    select count(*) into n from public.places where source = 'barangay' and active;
    if n <> 38 then raise exception '% barangay places', n; end if;
    v_log := v_log || E'\n' || 'ok  the 38 curated landmarks are the barangay''s own places';
  exception when others then v_log := v_log || E'\n' || 'FAIL seed: ' || sqlerrm; end;

  -- search forgives what people type
  begin
    select name into t from public.search_places('brgy 183 hall') limit 1;
    if t is distinct from 'Barangay 183 Hall' then raise exception 'brgy 183 hall -> %', t; end if;
    select name into t from public.search_places('villamor air bse') limit 1;
    if t is distinct from 'Villamor Air Base' then raise exception 'villamor air bse -> %', t; end if;
    select name into t from public.search_places('shrine st therese') limit 1;
    if t is distinct from 'Shrine of St. Thérèse of the Child Jesus' then raise exception 'shrine st therese -> %', t; end if;
    select name into t from public.search_places('eigthy one mall') limit 1;
    if t is distinct from 'Eighty One Mall' then raise exception 'eigthy one mall -> %', t; end if;
    v_log := v_log || E'\n' || 'ok  shorthand (Brgy, St), a letter slip and accents are forgiven';
  exception when others then v_log := v_log || E'\n' || 'FAIL forgiving: ' || sqlerrm; end;

  begin
    select count(*), max(branches) into n, v_id from public.search_places('watsons');
    if n <> 1 or v_id <> 2 then raise exception 'watsons: % rows, % branches', n, v_id; end if;
    v_log := v_log || E'\n' || 'ok  a chain is one result with its branches counted (Watsons, 2)';
  exception when others then v_log := v_log || E'\n' || 'FAIL chain: ' || sqlerrm; end;

  begin
    select count(*) into n from public.search_places('botika') s where s.grp <> 'health';
    if n <> 0 then raise exception 'botika listed % places that are not health', n; end if;
    select count(*) into n from public.search_places('simbahan');
    if n < 3 then raise exception 'simbahan listed %', n; end if;
    select array_agg(metres) into v_m from public.search_places('simbahan');
    if v_m <> (select array_agg(x order by x) from unnest(v_m) x) then raise exception 'simbahan not nearest first: %', v_m; end if;
    v_log := v_log || E'\n' || 'ok  a word for a kind of place (botika, simbahan) lists that kind, nearest first';
  exception when others then v_log := v_log || E'\n' || 'FAIL kinds: ' || sqlerrm; end;

  begin
    select count(*) into n from public.search_places('a');
    if n <> 0 then raise exception 'one letter gave %', n; end if;
    select count(*) into n from public.search_places('zzqxv');
    if n <> 0 then raise exception 'nonsense gave %', n; end if;
    v_log := v_log || E'\n' || 'ok  one letter or nonsense finds nothing';
  exception when others then v_log := v_log || E'\n' || 'FAIL nothing: ' || sqlerrm; end;

  -- the refresh from OpenStreetMap
  begin
    select jsonb_agg(e) into v_elems from (
      select jsonb_build_object('type', 'node', 'id', 900000 + g, 'lat', 14.52 + g / 10000.0, 'lon', 121.01,
                                'tags', jsonb_build_object('name', 'Test Store ' || g, 'shop', 'convenience', 'opening_hours', '24/7')) e
        from generate_series(1, 32) g
      union all select jsonb_build_object('type', 'way', 'id', 800001, 'center', jsonb_build_object('lat', 14.521, 'lon', 121.011),
                                          'tags', jsonb_build_object('name', 'Sampaguita Street', 'highway', 'residential'))
      union all select jsonb_build_object('type', 'way', 'id', 800002, 'center', jsonb_build_object('lat', 14.523, 'lon', 121.013),
                                          'tags', jsonb_build_object('name', 'Sampaguita Street', 'highway', 'residential'))
      union all select jsonb_build_object('type', 'node', 'id', 700001, 'lat', 14.522, 'lon', 121.012,
                                          'tags', jsonb_build_object('name', 'Botika ng Bayan', 'amenity', 'pharmacy'))) x;
    v_req := 990001;
    insert into net._http_response (id, status_code, content) values (v_req, 200, jsonb_build_object('elements', v_elems)::text);
    update public.places_refresh set request_id = v_req, asked_at = now() where id = 1;
    t := public.places_refresh_file();
    if t <> 'filed 35' then raise exception 'file said %', t; end if;
    select count(*) into n from public.places where source = 'osm' and active;
    if n <> 34 then raise exception '% osm places (32 stores, 1 pharmacy, 1 street)', n; end if;
    select count(*) into n from public.search_places('sampaguita st');
    if n <> 1 then raise exception 'the street came back % times', n; end if;
    select grp into t from public.places where osm_ref = 'n700001';
    if t <> 'health' then raise exception 'pharmacy filed as %', t; end if;
    v_log := v_log || E'\n' || 'ok  an Overpass answer is filed: places by map id, a street once, a pharmacy as health';
  exception when others then v_log := v_log || E'\n' || 'FAIL file: ' || sqlerrm; end;

  begin
    -- the next answer lacks store 1: it goes inactive; the barangay's places are untouched
    v_req := 990002;
    insert into net._http_response (id, status_code, content)
    values (v_req, 200, jsonb_build_object('elements', (select jsonb_agg(e) from jsonb_array_elements(v_elems) e where (e ->> 'id')::int <> 900001))::text);
    update public.places_refresh set request_id = v_req, asked_at = now() where id = 1;
    perform public.places_refresh_file();
    if (select active from public.places where osm_ref = 'n900001') then raise exception 'a removed place stayed active'; end if;
    select count(*) into n from public.places where source = 'barangay' and active;
    if n <> 38 then raise exception 'the barangay''s places changed: %', n; end if;
    -- a broken answer (too few places) changes nothing
    v_req := 990003;
    insert into net._http_response (id, status_code, content) values (v_req, 200, '{"elements":[]}');
    update public.places_refresh set request_id = v_req, asked_at = now() where id = 1;
    t := public.places_refresh_file();
    if t <> 'too few' then raise exception 'empty answer: %', t; end if;
    select count(*) into n from public.places where source = 'osm' and active;
    if n <> 33 then raise exception 'an empty answer changed the places: %', n; end if;
    -- a failed answer moves to the next mirror
    v_req := 990004;
    insert into net._http_response (id, status_code, content) values (v_req, 504, 'Gateway Timeout');
    update public.places_refresh set request_id = v_req, asked_at = now(), mirror = 0 where id = 1;
    t := public.places_refresh_file();
    if t <> 'failed' or (select mirror from public.places_refresh) <> 1 then raise exception 'failure: % mirror %', t, (select mirror from public.places_refresh); end if;
    v_log := v_log || E'\n' || 'ok  a place gone from the map goes inactive; an empty or failed answer changes nothing and tries the next mirror';
  exception when others then v_log := v_log || E'\n' || 'FAIL refresh guards: ' || sqlerrm; end;

  begin
    select count(*) into n from cron.job where jobname in ('places-ask', 'places-file');
    if n <> 2 then raise exception '% jobs', n; end if;
    v_log := v_log || E'\n' || 'ok  the refresh is scheduled every six hours';
  exception when others then v_log := v_log || E'\n' || 'FAIL schedule: ' || sqlerrm; end;

  -- the barangay's own places: admins only
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    execute 'set local role authenticated';
    v_id := public.place_save(null, 'Tindahan ni Aling Nena', 'shop', 14.5240, 121.0130, array['aling nena']);
    select name into t from public.search_places('aling nena') limit 1;
    if t is distinct from 'Tindahan ni Aling Nena' then raise exception 'own place not found by its alias: %', t; end if;
    begin perform public.place_save(null, 'Far away', 'shop', 14.60, 121.10); raise exception 'accepted a place 10 km away';
    exception when raise_exception then if sqlerrm not like '%within 5 km%' then raise; end if; end;
    begin perform public.place_save((select id from public.places where source = 'osm' limit 1), 'Renamed', 'shop', 14.524, 121.013);
      raise exception 'edited a map place';
    exception when raise_exception then if sqlerrm not like '%own places%' then raise; end if; end;
    perform public.place_remove(v_id);
    select count(*) into n from public.search_places('aling nena');
    execute 'reset role';
    if n <> 0 then raise exception 'a removed place is still found'; end if;
    v_log := v_log || E'\n' || 'ok  an administrator adds a place (found by its alias), not 10 km away, not over a map place, and removes it';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL admin places: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.search_places('villamor');
    if n = 0 then raise exception 'a resident found nothing'; end if;
    begin
      perform public.place_save(null, 'My house', 'shop', 14.524, 121.013);
      execute 'reset role';
      v_log := v_log || E'\n' || 'BAD a resident added a place (should have been refused)';
    exception when insufficient_privilege then
      execute 'reset role';
      v_log := v_log || E'\n' || 'ok  a resident can search but cannot add a place';
    end;
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL resident: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
