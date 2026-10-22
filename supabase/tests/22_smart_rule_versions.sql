-- 22_smart_rule_versions.sql: SMART's rules: versions, rollback, replay (0141). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_adm uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; v1 public.smart_rule_versions%rowtype;
  n integer; n0 integer; v integer; j jsonb; t text;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_adm, '+639999999941', 'Bersyon, Admin'), (v_res, '+639999999942', 'Bersyon, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_adm, v_res);
  update public.users set role = 'admin' where id = v_adm;
  select * into v1 from public.smart_rule_versions where version = (select min(version) from public.smart_rule_versions);
  v_log := 'setup ok';

  begin
    if v1.version is null or v1.reason not like 'The rules as they were%' then raise exception 'no first version: %', v1.reason; end if;
    if v1.rules ? 'storm_mode' or v1.rules ? 'id' or not v1.rules ? 'urgent_from' then raise exception 'snapshot keys wrong'; end if;
    if jsonb_array_length(v1.lexicon) <> (select count(*) from public.smart_lexicon) then raise exception 'word list not in the snapshot'; end if;
    v_log := v_log || E'\n' || 'ok  the rules as they were are version 1, with the word list, without the switches';
  exception when others then v_log := v_log || E'\n' || 'FAIL first: ' || sqlerrm; end;

  -- changing the rules: only by an administrator, with a reason, only real rules
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    v := public.smart_save_rules('{"urgent_from": 68}', 'Testing a lower bar for urgent');
    if (select urgent_from from public.smart_rules where id = 1) <> 68 then raise exception 'not saved'; end if;
    if (select reason from public.smart_rule_versions where version = v) <> 'Testing a lower bar for urgent' then raise exception 'reason not kept'; end if;
    if (select changed_by from public.smart_rule_versions where version = v) <> v_adm then raise exception 'who not kept'; end if;
    j := public.smart_rule_history(5);
    if j -> 0 -> 'changed' <> '["urgent_from"]' or (j -> 0 ->> 'current')::boolean is not true then raise exception 'history %', j -> 0; end if;
    if not exists (select 1 from public.smart_events where kind = 'rules_changed' and (detail ->> 'version')::int = v) then raise exception 'no event'; end if;
    begin perform public.smart_save_rules('{"urgent_from": 67}', ' '); raise exception 'saved without a reason';
    exception when check_violation then null; end;
    begin perform public.smart_save_rules('{"storm_mode": true}', 'sneaky'); raise exception 'changed a switch as a rule';
    exception when check_violation then null; end;
    begin perform public.smart_save_rules('{"id": 2}', 'sneaky'); raise exception 'changed the id';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_save_rules('{"urgent_from": 60}', 'a resident'); raise exception 'a resident changed the rules';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  an administrator changes a rule with a reason; it is a new version, in the history and the log; no reason, a switch, the id or a resident are refused';
  exception when others then v_log := v_log || E'\n' || 'FAIL save: ' || sqlerrm; end;

  begin
    select count(*) into n0 from public.smart_rule_versions;
    update public.smart_rules set storm_mode = true, storm_until = now() + interval '1 hour', storm_reason = 'test' where id = 1;
    update public.smart_rules set digest_enabled = not digest_enabled where id = 1;
    if (select count(*) from public.smart_rule_versions) <> n0 then raise exception 'a switch made a version'; end if;
    update public.smart_rules set storm_mode = false, storm_until = null, storm_reason = null where id = 1;
    insert into public.smart_lexicon (variant, root, kind) values ('snogg', 'sunog', 'spelling');
    select version, reason into v, t from public.smart_rule_versions order by version desc limit 1;
    if v <> n0 + (select min(version) from public.smart_rule_versions) or t <> 'Word list changed' then raise exception 'word list: % %', v, t; end if;
    v_log := v_log || E'\n' || 'ok  storm mode and the digest are not versions; a change to the word list is';
  exception when others then v_log := v_log || E'\n' || 'FAIL switches: ' || sqlerrm; end;

  -- each score remembers the rules that produced it
  begin
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_res, 'public_safety_infrastructure', 'Poste', 'Nakatagilid ang poste sa kanto.', lat, lng) returning id into r1;
    if (select rules_version from public.report_triage where report_id = r1) is distinct from (select max(version) from public.smart_rule_versions) then
      raise exception 'not stamped: %', (select rules_version from public.report_triage where report_id = r1);
    end if;
    select rules_version into n from public.report_triage where report_id = r1;
    insert into public.smart_lexicon (variant, root, kind) values ('poste', 'post', 'synonym');   -- a newer version exists now
    update public.report_triage set override_level = 'urgent', override_reason = 'test' where report_id = r1;
    if (select rules_version from public.report_triage where report_id = r1) <> n then raise exception 'an override re-stamped it'; end if;
    v_log := v_log || E'\n' || 'ok  a new score carries the version that produced it; an override does not change it';
  exception when others then v_log := v_log || E'\n' || 'FAIL stamp: ' || sqlerrm; end;

  -- replay: what a change would do, saving nothing
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    select count(*) into n0 from public.smart_rule_versions;
    j := public.smart_replay('{"urgent_from": 31, "high_from": 30, "normal_from": 20}', 30, 500);
    if (j ->> 'reports')::int < 1 or (j ->> 'moved')::int < 1 then raise exception 'replay %', j; end if;
    if not exists (select 1 from jsonb_array_elements(j -> 'transitions') x where x ->> 'to' = 'urgent' and x ->> 'from' <> 'urgent') then
      raise exception 'nothing moved to urgent: %', j -> 'transitions';
    end if;
    if (select urgent_from from public.smart_rules where id = 1) <> 68 then raise exception 'replay changed the rules'; end if;
    if (select count(*) from public.smart_rule_versions) <> n0 then raise exception 'replay made a version'; end if;
    if (select level from public.report_triage where report_id = r1) = 'urgent' and (select score from public.report_triage where report_id = r1) < 68 then
      raise exception 'replay changed a stored score';
    end if;
    begin perform public.smart_replay('{"storm_mode": true}'); raise exception 'replayed a switch';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_replay('{"urgent_from": 50}'); raise exception 'a resident replayed';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  replay shows what would move and saves nothing: no rule, no version, no stored score';
  exception when others then v_log := v_log || E'\n' || 'FAIL replay: ' || sqlerrm; end;

  -- rollback: the old rules and word list, as one new version, with the reason
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    select count(*) into n0 from public.smart_rule_versions;
    v := public.smart_rollback(v1.version, 'Back to the start');
    if (select count(*) from public.smart_rule_versions) <> n0 + 1 then raise exception 'rollback made % versions', (select count(*) from public.smart_rule_versions) - n0; end if;
    if (select reason from public.smart_rule_versions where version = v) <> format('Rolled back to version %s: Back to the start', v1.version) then raise exception 'reason'; end if;
    if (select urgent_from from public.smart_rules where id = 1) <> (v1.rules ->> 'urgent_from')::int then raise exception 'rules not restored'; end if;
    if (select count(*) from public.smart_lexicon) <> jsonb_array_length(v1.lexicon) or exists (select 1 from public.smart_lexicon where variant in ('snogg', 'poste')) then
      raise exception 'word list not restored';
    end if;
    if (select rules from public.smart_rule_versions where version = v) <> v1.rules then raise exception 'the new version is not the old rules'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.smart_rollback(v1.version, 'a resident'); raise exception 'a resident rolled back';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  a rollback restores the rules and the word list as one new version with the reason; a resident cannot';
  exception when others then v_log := v_log || E'\n' || 'FAIL rollback: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
