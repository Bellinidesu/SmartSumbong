-- 14_workspace_widgets.sql: the Workspace widgets' tables and reads (0132). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_res uuid; v_tan uuid; v_tan2 uuid; v_a uuid; v_b uuid; v_c uuid; v_chair uuid;
  r1 uuid; p uuid; cp uuid; post uuid;
  n integer; t text; j jsonb; b boolean;
  v_week0 timestamptz := date_trunc('week', (now() at time zone 'Asia/Manila')::date::timestamp) at time zone 'Asia/Manila';
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_res := gen_random_uuid(); v_tan := gen_random_uuid(); v_tan2 := gen_random_uuid();
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_c := gen_random_uuid(); v_chair := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_res, '+639999999951', 'Widget, Resident', 'resident'),
                 (v_tan, '+639999999952', 'Widget, Tanod', 'tanod'),
                 (v_tan2, '+639999999953', 'Widget, Tanod Two', 'tanod'),
                 (v_a, '+639999999954', 'Widget, Staff A', 'resident'),
                 (v_b, '+639999999955', 'Widget, Staff B', 'resident'),
                 (v_c, '+639999999956', 'Widget, Staff C', 'resident'),
                 (v_chair, '+639999999957', 'Widget, Chairman', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_tan, v_tan2, v_a, v_b, v_c, v_chair);
  update public.users set role = 'admin' where id in (v_a, v_b, v_c, v_chair);
  -- no other Chairman, so the rules below are about these accounts only
  update public.users set official_role = null where official_role = 'chairman';
  v_log := 'setup ok';

  -- 1. each person's Workspace
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.workspace_save(p_tab => 'flood');
    select cardinality(tabs), tab into n, t from public.workspace_prefs where user_id = v_a;
    if n <> 8 or t <> 'flood' then raise exception 'defaults % %', n, t; end if;
    perform public.workspace_save(p_tabs => array['brief', 'calc', 'ttt'], p_feeds => array['https://example.org/feed.xml'],
                                  p_keywords => array['Pasay', 'baha'], p_mine => '{"sticky":"Radio 3"}');
    select count(*) into n from public.workspace_prefs where user_id = v_a and tab = 'flood' and tabs = array['brief', 'calc', 'ttt'] and mine->>'sticky' = 'Radio 3';
    if n <> 1 then raise exception 'not kept'; end if;
    begin perform public.workspace_save(p_tabs => array['Bad Id!']); raise exception 'bad id saved'; exception when check_violation then null; end;
    begin perform public.workspace_save(p_feeds => array['http://example.org/feed']); raise exception 'plain http saved'; exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_b::text, true);
    select count(*) into n from public.workspace_prefs;
    if n <> 0 then raise exception 'B sees % rows', n; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.workspace_save(p_tab => 'brief'); raise exception 'resident saved'; exception when insufficient_privilege then null; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  each person saves their own widgets and notes; bad ids and plain-http feeds are refused; no one else reads them';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL prefs: ' || sqlerrm; end;

  -- 2. the barangay settings and who is the lead
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    if not public._ws_is_lead() then raise exception 'no Chairman yet, but A is not lead'; end if;
    execute 'reset role';
    update public.users set official_role = 'chairman' where id = v_chair;
    update public.users set official_role = 'secretary' where id = v_c;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    if public._ws_is_lead() then raise exception 'A is still lead with a Chairman'; end if;
    update public.workspace_settings set games_enabled = true where id = 1;
    execute 'reset role';
    if (select games_enabled from public.workspace_settings where id = 1) then raise exception 'A changed the settings'; end if;
    perform set_config('request.jwt.claim.sub', v_c::text, true);
    execute 'set local role authenticated';
    update public.workspace_settings set alarm_rules = '{red,sig3,urgent2h}' where id = 1;
    begin update public.workspace_settings set alarm_rules = '{red,storm}' where id = 1; raise exception 'unknown rule'; exception when check_violation then null; end;
    execute 'reset role';
    if (select alarm_rules from public.workspace_settings where id = 1) <> '{red,sig3,urgent2h}' then raise exception 'secretary could not'; end if;
    v_log := v_log || E'\n' || 'ok  the Chairman or Secretary sets the alarm rules and switches (any admin while there is no Chairman); others cannot';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL settings: ' || sqlerrm; end;

  -- 3. team posts
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.team_posts (kind, body) values ('board', 'Road on 9th St. is closed.') returning id into post;
    insert into public.team_posts (kind, body) values ('handover', 'Videoke on 9th St. again; spoke to the owner twice.');
    begin insert into public.team_posts (kind, body) values ('notice', 'Meeting at 3.'); raise exception 'A posted a notice'; exception when insufficient_privilege then null; end;
    begin insert into public.team_posts (kind, body) values ('board', repeat('x', 281)); raise exception 'long board line'; exception when check_violation then null; end;
    begin update public.team_posts set body = 'changed' where id = post; raise exception 'body changed'; exception when insufficient_privilege then null; end;
    insert into public.team_post_reads (post_id) values (post);
    perform set_config('request.jwt.claim.sub', v_chair::text, true);
    insert into public.team_posts (kind, body, pinned_until) values ('notice', 'Typhoon prep meeting at 3 PM.', now() + interval '8 hours');
    update public.team_posts set removed_at = now() where id = post;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    select count(*) into n from public.team_posts;
    if n <> 0 then raise exception 'resident reads % posts', n; end if;
    execute 'reset role';
    if (select removed_at from public.team_posts where id = post) is null then raise exception 'lead could not remove'; end if;
    select count(*) into n from public.team_post_reads where post_id = post and user_id = v_a;
    if n <> 1 then raise exception 'read not kept'; end if;
    v_log := v_log || E'\n' || 'ok  board and handover by any staff, notices by the lead, board lines short, text never edited, removal by author or lead, residents see nothing';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL posts: ' || sqlerrm; end;

  -- 4. a poll
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.polls (question, options) values ('Who can cover Saturday night?', array['Kim', 'Martin', 'Nobody yet']) returning id into p;
    perform public.poll_vote(p, 1::smallint);
    perform public.poll_vote(p, 0::smallint);
    begin perform public.poll_vote(p, 4::smallint); raise exception 'answer 4 accepted'; exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_b::text, true);
    perform public.poll_vote(p, 0::smallint);
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    update public.polls set closed_at = now() where id = p;
    perform set_config('request.jwt.claim.sub', v_c::text, true);
    begin perform public.poll_vote(p, 2::smallint); raise exception 'voted on a closed poll'; exception when check_violation then null; end;
    begin insert into public.polls (question, options) values ('One?', array['only']); raise exception 'one answer'; exception when check_violation then null; end;
    execute 'reset role';
    select count(*) into n from public.poll_votes where poll_id = p and choice = 0;
    if n <> 2 then raise exception 'votes %', n; end if;
    v_log := v_log || E'\n' || 'ok  a poll takes one vote per person, a changed vote replaces the old, wrong answers and closed polls are refused';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL poll: ' || sqlerrm; end;

  -- 5. staff: birthdays, leave, credentials, roster, attendance; the team read
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.staff_dates (user_id, birthday) values (v_tan, ((now() at time zone 'Asia/Manila')::date + 3) - interval '30 years');
    begin insert into public.staff_dates (user_id, birthday) values (v_res, date '1990-01-01'); raise exception 'resident listed'; exception when check_violation then null; end;
    insert into public.staff_leave (user_id, starts_on, ends_on, reason) values (v_tan2, (now() at time zone 'Asia/Manila')::date, (now() at time zone 'Asia/Manila')::date + 2, 'Family');
    insert into public.staff_credentials (user_id, kind, label, expires_on) values (v_tan, 'first_aid', 'Red Cross first aid', (now() at time zone 'Asia/Manila')::date + 21);
    insert into public.duty_roster (user_id, shift_date, shift) values (v_tan, (now() at time zone 'Asia/Manila')::date, 'morning');
    begin insert into public.duty_roster (user_id, shift_date, shift) values (v_tan, (now() at time zone 'Asia/Manila')::date, 'morning'); raise exception 'twice'; exception when unique_violation then null; end;
    execute 'reset role';
    insert into public.attendance (tanod_id, duty_status, logged_at)
    values (v_tan, 'on_duty', ((now() at time zone 'Asia/Manila')::date::timestamp + interval '6 hours 20 minutes') at time zone 'Asia/Manila');
    if now() - v_week0 > interval '4 hours' then
      insert into public.attendance (tanod_id, duty_status, logged_at) values (v_tan2, 'on_duty', now() - interval '3 hours'), (v_tan2, 'offline', now() - interval '1 hour');
    end if;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    j := public.workspace_team();
    execute 'reset role';
    select (x->>'late_minutes')::int into n from jsonb_array_elements(j->'tanods') x where x->>'id' = v_tan::text;
    if n is distinct from 20 then raise exception 'late %', n; end if;
    if now() - v_week0 > interval '4 hours' then
      select (x->>'hours_week')::numeric into t from jsonb_array_elements(j->'tanods') x where x->>'id' = v_tan2::text;
      if t::numeric <> 2.0 then raise exception 'hours %', t; end if;
    end if;
    if not exists (select 1 from jsonb_array_elements(j->'birthdays') x where x->>'user_id' = v_tan::text and (x->>'in_days')::int = 3) then raise exception 'birthday missing'; end if;
    if not exists (select 1 from jsonb_array_elements(j->'leave') x where x->>'user_id' = v_tan2::text and (x->>'now')::boolean) then raise exception 'leave missing'; end if;
    if not exists (select 1 from jsonb_array_elements(j->'credentials') x where x->>'user_id' = v_tan::text and (x->>'days_left')::int = 21) then raise exception 'credential missing'; end if;
    if not exists (select 1 from jsonb_array_elements(j->'roster') x where x->>'user_id' = v_tan::text and x->>'shift' = 'morning') then raise exception 'roster missing'; end if;
    if j->'waiting' is null or j->'directory' is null then raise exception 'keys %', j; end if;
    v_log := v_log || E'\n' || 'ok  birthdays, leave, credentials and the roster are kept for staff only; late is measured against the roster; hours this week add up';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL team: ' || sqlerrm; end;

  -- 6. patrol checkpoints
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.patrol_checkpoints (name, lat, lng) values ('Barangay hall', lat, lng) returning id into cp;
    insert into public.checkpoint_scans (checkpoint_id, tanod_id) values (cp, v_tan);
    begin insert into public.checkpoint_scans (checkpoint_id, tanod_id) values (cp, v_res); raise exception 'resident scanned'; exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    insert into public.checkpoint_scans (checkpoint_id, tanod_id) values (cp, v_tan);
    begin insert into public.checkpoint_scans (checkpoint_id, tanod_id) values (cp, v_tan2); raise exception 'scanned for another'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    select count(*) into n from public.patrol_checkpoints;
    if n <> 0 then raise exception 'resident sees checkpoints'; end if;
    execute 'reset role';
    select count(*) into n from public.checkpoint_scans where checkpoint_id = cp;
    if n <> 2 then raise exception 'scans %', n; end if;
    v_log := v_log || E'\n' || 'ok  staff record a tanod reaching a checkpoint, a tanod only their own, residents see nothing';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL checkpoints: ' || sqlerrm; end;

  -- 7. how is the shift: own rows only, totals for the lead once three have answered
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.shift_checkin('busy');
    perform public.shift_checkin('tired');
    perform set_config('request.jwt.claim.sub', v_b::text, true);
    perform public.shift_checkin('calm');
    select count(*) into n from public.shift_checkins;
    if n <> 1 then raise exception 'B sees % check-ins', n; end if;
    begin perform public.shift_mood_totals(); raise exception 'B saw totals'; exception when insufficient_privilege then null; end;
    begin perform public.shift_checkin('angry'); raise exception 'unknown mood'; exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_chair::text, true);
    j := public.shift_mood_totals();
    if not (j->>'hidden')::boolean then raise exception 'shown with two: %', j; end if;
    perform public.shift_checkin('tired');
    j := public.shift_mood_totals();
    execute 'reset role';
    if (j->>'hidden')::boolean or (j->>'tired')::int <> 2 or (j->>'calm')::int <> 1 then raise exception 'totals %', j; end if;
    v_log := v_log || E'\n' || 'ok  a check-in is private; the lead sees only totals, and only once three have answered; a changed answer replaces the old';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL check-in: ' || sqlerrm; end;

  -- 8. relief packs and safe-point notes
  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    insert into public.relief_tally (event, street, packs) values ('Typhoon Kristine', 'Rizal Ext.', 120);
    begin insert into public.relief_tally (event, street, packs) values ('Typhoon Kristine', 'Rizal Ext.', 0); raise exception 'zero packs'; exception when check_violation then null; end;
    begin insert into public.safe_point_notes (osm_id, capacity, status) values ('node/123', 300, 'open'); raise exception 'A set a note'; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_chair::text, true);
    insert into public.safe_point_notes (osm_id, name, capacity, status) values ('node/123', 'Pasay Elementary School', 300, 'open');
    update public.safe_point_notes set status = 'full' where osm_id = 'node/123';
    begin insert into public.safe_point_notes (osm_id) values ('school 1'); raise exception 'bad id'; exception when check_violation then null; end;
    execute 'reset role';
    if (select status from public.safe_point_notes where osm_id = 'node/123') <> 'full' then raise exception 'note not kept'; end if;
    v_log := v_log || E'\n' || 'ok  relief packs are counted by street; safe-point capacity and status are set by the lead, keyed by the OSM element';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL relief and safe points: ' || sqlerrm; end;

  -- 9. minigame bests
  begin
    update public.workspace_settings set games_enabled = false where id = 1;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    begin perform public.record_game_score('react', 300); raise exception 'scored with games off'; exception when check_violation then null; end;
    execute 'reset role';
    update public.workspace_settings set games_enabled = true where id = 1;
    execute 'set local role authenticated';
    j := public.record_game_score('react', 300);
    j := public.record_game_score('react', 250);
    if not (j->>'new_best')::boolean or (j->>'best')::numeric <> 250 then raise exception 'react %', j; end if;
    j := public.record_game_score('react', 400);
    if (j->>'new_best')::boolean or (j->>'best')::numeric <> 250 then raise exception 'react slower %', j; end if;
    j := public.record_game_score('snake', 12);
    j := public.record_game_score('snake', 30);
    if (j->>'best')::numeric <> 30 then raise exception 'snake %', j; end if;
    begin perform public.record_game_score('poker', 1); raise exception 'unknown game'; exception when invalid_parameter_value then null; end;
    begin perform public.record_game_score('quiz', 11); raise exception 'quiz 11 of 10'; exception when invalid_parameter_value then null; end;
    begin insert into public.game_scores (game, best) values ('snake', 99999); raise exception 'wrote directly'; exception when insufficient_privilege then null; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  minigame bests: off until the lead allows them, lower or higher is better per game, out-of-range and direct writes refused';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL games: ' || sqlerrm; end;

  -- 10. the reads: what they hold, and residents kept out
  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, location_label)
    values (v_res, 'street_obstruction', 'Xylophone cart blocking 50% of the road', 'May nakaharang na kariton sa kalsada.', lat, lng, 'validated', 'Rizal Ext.')
    returning id into r1;
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    j := public.workspace_numbers();
    if j->'status' is null or jsonb_array_length(j->'per_day') <> 30 or jsonb_array_length(j->'per_hour') <> 24
       or jsonb_array_length(j->'pace'->'days') <> 7 or j->'month' is null then raise exception 'numbers %', left(j::text, 300); end if;
    if not exists (select 1 from jsonb_array_elements(j->'streets') x where x->>'place' = 'Rizal Ext.') then raise exception 'street missing'; end if;
    j := public.workspace_find('xylophone');
    if jsonb_array_length(j) <> 1 then raise exception 'find %', j; end if;
    j := public.workspace_find('50%');
    if jsonb_array_length(j) <> 1 then raise exception 'literal percent %', j; end if;
    j := public.workspace_find('%%');
    if exists (select 1 from jsonb_array_elements(j) x where x->>'report_id' = r1::text) then raise exception 'wildcard matched'; end if;
    j := public.workspace_activity(5);
    if not exists (select 1 from jsonb_array_elements(j) x where x->>'report_id' = r1::text and x->>'kind' = 'new') then raise exception 'activity %', j; end if;
    j := public.workspace_alarm_db();
    if j->'urgent2h' is null or j->'deadline' is null or j->'rules' is null then raise exception 'alarm %', j; end if;
    j := public.workspace_photos(4);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.workspace_numbers(); raise exception 'resident: numbers'; exception when insufficient_privilege then null; end;
    begin perform public.workspace_team(); raise exception 'resident: team'; exception when insufficient_privilege then null; end;
    begin perform public.workspace_find('x'); raise exception 'resident: find'; exception when insufficient_privilege then null; end;
    begin perform public.workspace_activity(); raise exception 'resident: activity'; exception when insufficient_privilege then null; end;
    begin perform public.workspace_photos(); raise exception 'resident: photos'; exception when insufficient_privilege then null; end;
    begin perform public.workspace_alarm_db(); raise exception 'resident: alarm'; exception when insufficient_privilege then null; end;
    execute 'reset role';
    if has_table_privilege('anon', 'public.workspace_prefs', 'select') or has_table_privilege('anon', 'public.team_posts', 'select') then
      raise exception 'anon can read';
    end if;
    v_log := v_log || E'\n' || 'ok  the widget reads (numbers, team, alarm, activity, photos, find) answer staff only; find matches text literally';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL reads: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
