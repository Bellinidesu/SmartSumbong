-- 06_smart_screens.sql: what the SMART screens call (0124). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_a uuid; v_b uuid; v_tan uuid; v_adm uuid;
  r_fire uuid; r_other uuid;
  j jsonb;
  n integer;
  lng constant double precision := 121.01219; lat constant double precision := 14.51944;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid(); v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_a, '+639999999931', 'Screens, Ana', 'resident'),
                 (v_b, '+639999999932', 'Screens, Ben', 'resident'),
                 (v_tan, '+639999999933', 'Screens, Tanod', 'tanod'),
                 (v_adm, '+639999999934', 'Santos, Maria', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_a, v_b, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng, lat), 4326), last_location_at = now() - interval '6 minutes' where id = v_tan;
  v_log := 'setup ok';

  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_a, 'public_safety_infrastructure', 'Sunog', 'May sunog sa likod ng bahay, may bata sa loob.', lat, lng, date_trunc('day', now()) + interval '6 hours')
  returning id into r_fire;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, created_at)
  values (v_b, 'other', 'Counterflow', 'May tricycle na counterflow sa kalye araw-araw.', lat + 0.003, lng, date_trunc('day', now()) + interval '6 hours')
  returning id into r_other;

  -- Try it: the same score as a filed report, nothing saved
  begin
    select count(*) into n from public.report_triage;
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    j := public.smart_preview('public_safety_infrastructure', 'Sunog', 'May sunog sa likod ng bahay, may bata sa loob.', lat + 0.002, lng);
    execute 'reset role';
    if (j ->> 'score')::integer <> 75 or j ->> 'level' <> 'urgent' then raise exception '%', j; end if;
    if not j -> 'reasons' @> '[{"factor": "words", "detail": "fire"}]' then raise exception '%', j; end if;
    if (select count(*) from public.report_triage) <> n then raise exception 'saved something'; end if;
    v_log := v_log || E'\n' || 'ok  Try it scores a sentence like a filed report (75, urgent) and saves nothing';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL preview: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_preview('other', 'x', 'probing the rules');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident used Try it (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot use Try it (refused: ' || left(sqlerrm, 60) || ')'; end;

  -- category hint
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    j := public.smart_case_card(r_other);
    execute 'reset role';
    if j -> 'category_hint' ->> 'category' <> 'traffic_violation' or not (j -> 'category_hint' -> 'words') ? 'counterflow' then raise exception '%', j -> 'category_hint'; end if;
    v_log := v_log || E'\n' || 'ok  "counterflow" filed as Other suggests Traffic violation, with the words';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL hint: ' || sqlerrm; end;

  begin
    if public._smart_category_hint('traffic_violation', 'Counterflow', 'May tricycle na counterflow.') is not null then raise exception 'hint on the right kind'; end if;
    if public._smart_category_hint('other', 'Hello', 'Walang kinalaman na salita dito.') is not null then raise exception 'hint from nothing'; end if;
    v_log := v_log || E'\n' || 'ok  no hint when the kind already fits, or when no words point anywhere';
  exception when others then v_log := v_log || E'\n' || 'FAIL hint quiet: ' || sqlerrm; end;

  -- the case card
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.smart_override(r_fire, 'high', 'Bureau of Fire Protection already on site.');
    j := public.smart_case_card(r_fire);
    execute 'reset role';
    if (j ->> 'score')::integer <> 75 or j ->> 'level' <> 'urgent' or j ->> 'effective_level' <> 'high' then raise exception 'levels %', j; end if;
    if j -> 'override' ->> 'by' <> 'Maria Santos' or j -> 'override' ->> 'reason' not like 'Bureau%' then raise exception 'override %', j -> 'override'; end if;
    if jsonb_array_length(j -> 'reasons') < 3 or j -> 'eta' is null or jsonb_typeof(j -> 'duplicates') <> 'array' then raise exception 'parts %', j; end if;
    if j -> 'tanods' -> 0 ->> 'tanod_id' <> v_tan::text or not (j -> 'tanods' -> 0 -> 'reasons') @> '[{"factor": "location", "detail": "last reading 6 min ago"}]' then
      raise exception 'tanods %', j -> 'tanods';
    end if;
    v_log := v_log || E'\n' || 'ok  the case card has both levels, who overrode and why, reasons, estimate, duplicates and the top tanod';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL case card: ' || sqlerrm; end;

  begin
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    execute 'set local role authenticated';
    perform public.smart_case_card(r_fire);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD a resident read a case card (should have been refused)';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'ok  a resident cannot read a case card (refused: ' || left(sqlerrm, 60) || ')'; end;

  -- the dashboard tiles
  begin
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    j := public.smart_summary();
    execute 'reset role';
    if (j ->> 'high_waiting')::integer < 1 or not (j ? 'urgent_waiting' and j ? 'recurring' and j ? 'recurring_open') then raise exception '%', j; end if;
    v_log := v_log || E'\n' || 'ok  the dashboard summary counts the overridden fire as high, waiting';
  exception when others then execute 'reset role'; v_log := v_log || E'\n' || 'FAIL summary: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
