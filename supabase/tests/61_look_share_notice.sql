-- 61_look_share_notice.sql: a look-around notifies the tanod from the database (0183, backend sweep). Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); r1 uuid; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999941', 'Look, Super', 'resident'), (v_tan, '+639999999942', 'Look, Tanod', 'tanod'), (v_ana, '+639999999943', 'Look, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_tan, v_ana);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto, gabi-gabi.', lat, lng) returning id into r1;

  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    insert into public.look_shares (report_id, tanod_id, sent_by, message) values (r1, v_tan, v_sup, 'Look at the corner by the sari-sari store');
    reset role;
    select count(*) into n from public.notifications where user_id = v_tan and report_id = r1 and kind = 'look_around' and message like 'From the barangay: Look at the corner%';
    if n <> 1 then raise exception '% look-around notices for the tanod, not 1', n; end if;
    if exists (select 1 from public.notifications where kind = 'look_around' and user_id <> v_tan) then raise exception 'someone else was told'; end if;
    if has_function_privilege('authenticated', 'public._look_share_notice()', 'execute') then raise exception 'the trigger function can be called'; end if;
    v_log := v_log || E'\n' || 'ok  sending a look-around tells the tanod, once, and nobody else';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL notice: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
