-- 48_engine_snapshot.sql: the engine's snapshot (0169). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 public.reports; j jsonb; n integer; m integer; ok boolean; h numeric;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999981', 'Snapshot, Super'), (v_res, '+639999999982', 'Snapshot, Resident')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  perform set_config('request.jwt.claim.sub', v_res::text, true);
  r1 := public.file_report('peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'Malakas na videoke hanggang hatinggabi.', lat, lng);
  perform set_config('request.jwt.claim.sub', '', true);
  v_log := 'setup ok';

  -- 1. a refresh fills the four lists
  begin
    delete from public.smart_snapshot;
    if not public._smart_snapshot_refresh(true) then raise exception 'a forced refresh did nothing'; end if;
    select count(*) into n from public.smart_snapshot;
    if n <> 4 then raise exception 'expected 4 lists, got %', n; end if;
    v_log := v_log || E'\n' || 'ok  a refresh fills deadline risk, quiet cases, spikes and recurring problems';
  exception when others then v_log := v_log || E'\n' || 'FAIL refresh: ' || sqlerrm; end;

  -- 2. nothing changed: the job skips; a report changed: it works again
  --    (one transaction: now() does not move, so the lists are dated a second ahead, then a minute back)
  begin
    update public.smart_snapshot set at = now() + interval '1 second';
    if public._smart_snapshot_refresh() then raise exception 'it redid the work with nothing changed'; end if;
    update public.smart_snapshot set at = now() - interval '1 minute';
    update public.reports set subject = subject where id = r1.id;   -- the touch trigger moves updated_at
    if not public._smart_snapshot_refresh() then
      -- no touch trigger on this table in the stub: a new report is a change too
      perform set_config('request.jwt.claim.sub', v_res::text, true);
      perform public.file_report('animal_welfare', 'Stray / Nuisance Animals', 'Maraming asong gala sa kanto.', lat, lng);
      perform set_config('request.jwt.claim.sub', '', true);
      update public.smart_snapshot set at = now() - interval '1 minute';
      if not public._smart_snapshot_refresh() then raise exception 'a new report did not bring a refresh'; end if;
    end if;
    -- a missing list is filled even when nothing changed
    update public.smart_snapshot set at = now() + interval '1 second';
    delete from public.smart_snapshot where key = 'spikes';
    if not public._smart_snapshot_refresh() then raise exception 'a missing list was not filled'; end if;
    -- and five minutes is the longest a list goes unrefreshed (deadline risk moves with the clock)
    if position('interval ''5 minutes''' in pg_get_functiondef('public._smart_snapshot_refresh(boolean)'::regprocedure)) = 0 then raise exception 'no five-minute refresh'; end if;
    v_log := v_log || E'\n' || 'ok  the job skips when nothing changed and works again after a change, a missing list or five minutes';
  exception when others then v_log := v_log || E'\n' || 'FAIL skip: ' || sqlerrm; end;

  -- 3. the lists say what the live analyses say
  begin
    perform public._smart_snapshot_refresh(true);
    update public.smart_snapshot set at = now() + interval '1 second';   -- current: the readers use the lists, not the live analysis
    if not public._smart_snapshot_current() then raise exception 'the lists are not current after a refresh'; end if;
    select count(*) into n from public._snap_patterns(); select count(*) into m from public._smart_patterns(null);
    if n <> m then raise exception 'patterns % vs %', n, m; end if;
    select count(*) into n from public._snap_stuck(); select count(*) into m from public._smart_stuck();
    if n <> m then raise exception 'quiet cases % vs %', n, m; end if;
    select count(*) into n from public._snap_spikes(); select count(*) into m from public._smart_spikes();
    if n <> m then raise exception 'spikes % vs %', n, m; end if;
    select count(*) into n from (select report_id from public._snap_deadline_risk() except select report_id from public._smart_deadline_risk()) x;
    if n <> 0 then raise exception 'deadline risk differs (% cases)', n; end if;
    v_log := v_log || E'\n' || 'ok  each list matches its live analysis';
  exception when others then v_log := v_log || E'\n' || 'FAIL match: ' || sqlerrm; end;

  -- 4. a current list is read (hours left counted from now); a list made before a change, an old one or a missing one is not
  --    (one transaction: the lists are dated a second after this transaction's reports to count as made after them)
  begin
    perform public._smart_snapshot_refresh(true);
    update public.smart_snapshot set at = now() + interval '1 second';
    update public.smart_snapshot
       set data = jsonb_build_array(jsonb_build_object('report_id', gen_random_uuid(), 'tracking_id', 'BRG-TEST-0001', 'due_at', now() + interval '2 hours',
                                                       'hours_left', 99, 'typical_hours', 1, 'slow_hours', 2, 'tanod_jobs', 0, 'risk', 'high', 'reasons', '[]'::jsonb))
     where key = 'deadline_risk';
    select hours_left into h from public._snap_deadline_risk() where tracking_id = 'BRG-TEST-0001';
    if h is null then raise exception 'the current list was not read'; end if;
    if abs(h - 2) > 0.01 then raise exception 'hours left %, expected 2 (counted from now)', h; end if;
    update public.smart_snapshot set at = now() - interval '1 minute';            -- made before this transaction's reports
    select count(*) into n from public._snap_deadline_risk() where tracking_id = 'BRG-TEST-0001';
    if n <> 0 then raise exception 'a list made before a change was used'; end if;
    update public.smart_snapshot set at = now() - interval '11 minutes';
    select count(*) into n from public._snap_deadline_risk() where tracking_id = 'BRG-TEST-0001';
    if n <> 0 then raise exception 'an old list was used'; end if;
    delete from public.smart_snapshot;
    select count(*) into n from public._snap_patterns(); select count(*) into m from public._smart_patterns(null);
    if n <> m then raise exception 'with no list the analysis did not run live'; end if;
    v_log := v_log || E'\n' || 'ok  a current list is read, hours left from now; one made before a change, old or missing means the live analysis';
  exception when others then v_log := v_log || E'\n' || 'FAIL freshness: ' || sqlerrm; end;

  -- 5. nobody signed in reads the lists themselves; only the engine's functions do
  begin
    if has_table_privilege('authenticated', 'public.smart_snapshot', 'select') then raise exception 'authenticated may read the table'; end if;
    if has_table_privilege('anon', 'public.smart_snapshot', 'select') then raise exception 'anon may read the table'; end if;
    if has_function_privilege('authenticated', 'public._snap_deadline_risk()', 'execute')
       or has_function_privilege('authenticated', 'public._snap_stuck()', 'execute')
       or has_function_privilege('authenticated', 'public._snap_spikes()', 'execute')
       or has_function_privilege('authenticated', 'public._snap_patterns()', 'execute')
       or has_function_privilege('authenticated', 'public._smart_snapshot_refresh(boolean)', 'execute')
       or has_function_privilege('authenticated', 'public._smart_changed_since(timestamptz)', 'execute')
       or has_function_privilege('authenticated', 'public._smart_snapshot_current()', 'execute') then
      raise exception 'a signed-in user may call one of the snapshot''s functions';
    end if;
    v_log := v_log || E'\n' || 'ok  the lists and their readers are the engine''s own';
  exception when others then v_log := v_log || E'\n' || 'FAIL rights: ' || sqlerrm; end;

  -- 6. the job runs every minute, and the module keeps its shape
  begin
    select count(*) into n from cron.job where jobname = 'smart-snapshot' and schedule = '* * * * *';
    if n <> 1 then raise exception 'the smart-snapshot job is not scheduled'; end if;
    perform public._smart_snapshot_refresh(true);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.smart_module();
    perform set_config('request.jwt.claim.sub', '', true);
    select bool_and(j ? k) into ok from unnest(array['module', 'counts', 'decisions', 'deadline_risk', 'quiet', 'spikes', 'patterns', 'tanods', 'at']) k;
    if not ok then raise exception 'the module lost a part: %', (select string_agg(k, ', ') from jsonb_object_keys(j) k); end if;
    if j->>'module' <> 'barangay' then raise exception 'a super admin got the % module', j->>'module'; end if;
    v_log := v_log || E'\n' || 'ok  the job runs every minute; the module keeps every part';
  exception when others then v_log := v_log || E'\n' || 'FAIL module: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
