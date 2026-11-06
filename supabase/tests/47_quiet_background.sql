-- 47_quiet_background.sql: the background jobs skip work that cannot have a different answer (0168). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_res uuid := gen_random_uuid();
  t1 timestamptz; t2 timestamptz; t3 timestamptz; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', v_res, 'authenticated', 'authenticated', public.auth_email_for('+639999999901'),
         jsonb_build_object('full_name', 'Quiet, Ana', 'mobile_number', '+639999999901', 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now();
  update public.users set verification_status = 'verified', verified_at = now() where id = v_res;
  v_log := 'setup ok';

  -- 1. the waiting line: nobody waiting, the sweep runs and changes nothing
  begin
    update public.reports set awaiting_unit_since = null where awaiting_unit_since is not null;
    select count(*) into n from public.notifications;
    perform public.sweep_awaiting_units();
    if (select count(*) from public.notifications) <> n then raise exception 'the sweep wrote with nobody waiting'; end if;
    if position('nobody waiting' in pg_get_functiondef('public.sweep_awaiting_units()'::regprocedure)) = 0 then raise exception 'no early return'; end if;
    v_log := v_log || E'\n' || 'ok  with nobody waiting for a tanod the sweep returns at once';
  exception when others then v_log := v_log || E'\n' || 'FAIL sweep: ' || sqlerrm; end;

  -- 2. the watcher: scans, then skips while no report changes, then scans again after a report is filed
  --    (one transaction: now() does not move, so the last scan is set back a minute rather than waiting)
  begin
    delete from public.smart_watch_state;
    perform public.smart_watch();
    t1 := (select scanned_at from public.smart_watch_state where id = 1);
    if t1 is null then raise exception 'the first run did not scan'; end if;
    update public.smart_watch_state set scanned_at = now() + interval '1 second';   -- after every report's time
    perform public.smart_watch();
    t2 := (select scanned_at from public.smart_watch_state where id = 1);
    if t2 <> now() + interval '1 second' then raise exception 'it rescanned with no report changed'; end if;
    update public.smart_watch_state set scanned_at = now() - interval '1 minute';
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', lat, lng);
    perform public.smart_watch();
    t3 := (select scanned_at from public.smart_watch_state where id = 1);
    if t3 <> now() then raise exception 'a new report did not bring a rescan (%)', t3; end if;
    if position('interval ''1 hour''' in pg_get_functiondef('public.smart_watch()'::regprocedure)) = 0 then raise exception 'no hourly safety scan'; end if;
    v_log := v_log || E'\n' || 'ok  the watcher rescans patterns and spikes only after a report changes (and hourly)';
  exception when others then v_log := v_log || E'\n' || 'FAIL watcher: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
