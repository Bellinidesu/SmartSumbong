-- 25_feature_switches.sql: parts of the system can be switched off without removing them (0144). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  j jsonb; tok text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999971', 'Switch, Admin', 'resident'), (v_res, '+639999999972', 'Switch, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_res);
  update public.users set role = 'admin' where id = v_adm;
  perform set_config('request.jwt.claim.sub', v_adm::text, true);
  v_log := 'setup ok';

  -- 1. they ship off, and a key that does not exist reads as off
  begin
    if public.feature_on('workspace') or public.feature_on('command_center') then raise exception 'a part ships on'; end if;
    if public.feature_on('nonsense') then raise exception 'an unknown key reads on'; end if;
    if (select count(*) from public.feature_switches) < 2 then raise exception 'switches %', (select count(*) from public.feature_switches); end if;
    v_log := v_log || E'\n' || 'ok  the Workspace and the command center ship switched off; an unknown key reads as off';
  exception when others then v_log := v_log || E'\n' || 'FAIL defaults: ' || sqlerrm; end;

  -- 2. off, the command center cannot be reached by calling its functions
  begin
    if public.command_suggest(2::smallint) is not null then raise exception 'a suggestion while off'; end if;
    begin perform public.command_board('flood', null); raise exception 'the board answered while off';
    exception when check_violation then null; end;
    begin perform public.command_start('flood', 'Malakas ang ulan'); raise exception 'a mode started while off';
    exception when check_violation then null; end;
    perform public._command_auto();   -- does nothing, raises nothing
    if public.command_now() is not null then raise exception 'the banner showed while off'; end if;
    v_log := v_log || E'\n' || 'ok  switched off, the command center refuses the board and starting a mode, and gives no suggestion, banner or auto switch';
  exception when others then v_log := v_log || E'\n' || 'FAIL off: ' || sqlerrm; end;

  -- 3. on, it works; the hall display follows the switch both ways
  begin
    perform public.feature_set('command_center', true);
    if not public.feature_on('command_center') then raise exception 'not on'; end if;
    j := public.command_board('flood', null);
    if j ->> 'mode' <> 'flood' then raise exception 'board %', j; end if;
    tok := public.command_display_link_create('Hall TV');
    if public.command_hall(tok) is null then raise exception 'the hall display did not answer while on'; end if;
    perform public.feature_set('command_center', false);
    if public.command_hall(tok) is not null then raise exception 'the hall display answered while off'; end if;
    if (select count(*) from public.smart_events where kind = 'feature_switch') < 2 then raise exception 'events'; end if;
    v_log := v_log || E'\n' || 'ok  switched on it works and the hall display answers; switched off again the hall display stops; each flip is kept as an event';
  exception when others then v_log := v_log || E'\n' || 'FAIL on: ' || sqlerrm; end;

  -- 4. who may flip a switch
  begin
    begin perform public.feature_set('nonsense', true); raise exception 'a made-up key was switched';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.feature_set('workspace', true); raise exception 'a resident flipped a switch';
    exception when insufficient_privilege then null; end;
    if public.command_now() is not null then raise exception 'a resident got the banner'; end if;
    v_log := v_log || E'\n' || 'ok  a made-up key is refused and a resident cannot flip a switch';
  exception when others then v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
