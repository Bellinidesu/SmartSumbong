-- 56_least_privilege_writes.sql: write rights only where something signed in really writes (0178, backend sweep).
-- dispatches, sla_extensions, retirement_requests are written by the functions alone; users are not inserted or deleted through the API;
-- look_shares and notifications take one column each. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_res uuid := gen_random_uuid(); v_kag uuid := gen_random_uuid(); v_kag2 uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid(); v_tan uuid := gen_random_uuid();
  r public.reports; r1 uuid; d1 uuid; ls uuid; n1 uuid; s text; t text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
  long_text constant text := 'This is a long enough description for the check on the length of a description.';
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999971', 'Least, Ana', 'resident'), (v_kag, '+639999999972', 'Least, Kagawad', 'resident'),
                 (v_kag2, '+639999999973', 'Least, Kagawad Two', 'resident'), (v_sup, '+639999999974', 'Least, Super', 'resident'),
                 (v_tan, '+639999999975', 'Least, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_kag, v_kag2, v_sup, v_tan);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id in (v_kag, v_kag2);
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(121.0155, 14.5269), 4326), last_location_at = now() where id = v_tan;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Videoke', long_text, lat, lng) returning id into r1;

  -- 1. a dispatch is made by admin_dispatch, and by nothing else: no administrator inserts, edits or deletes one by hand
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.set_resolution_target(r1, now() + interval '2 days');
    d1 := public.admin_dispatch(r1, v_tan, 'Check the corner');
    if d1 is null then raise exception 'admin_dispatch no longer dispatches'; end if;
    foreach s in array array['insert', 'update', 'delete'] loop
      foreach t in array array[v_sup::text, v_kag::text, v_kag2::text] loop
        perform set_config('request.jwt.claim.sub', t, true);
        begin
          if s = 'insert' then
            insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r1, v_tan, v_sup, 'assigned');
          elsif s = 'update' then
            update public.dispatches set admin_instructions = 'by hand' where id = d1;
          else
            delete from public.dispatches where id = d1;
          end if;
          raise exception 'an administrator did % on dispatches by hand', s;
        exception when insufficient_privilege then null; end;
      end loop;
    end loop;
    reset role;
    if not exists (select 1 from public.dispatches where id = d1) then raise exception 'the dispatch is gone'; end if;
    v_log := v_log || E'\n' || 'ok  nobody inserts, edits or deletes a dispatch by hand, a super admin and the committee''s Kagawad included; admin_dispatch still works';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL dispatches: ' || sqlerrm; end;

  -- 2. the deadline extensions, retirement decisions and accounts have no direct write either
  begin
    execute 'set local role authenticated';
    foreach t in array array[v_sup::text, v_kag::text] loop
      perform set_config('request.jwt.claim.sub', t, true);
      begin insert into public.sla_extensions (report_id, requested_by, previous_due, new_due, reason) values (r1, t::uuid, now(), now() + interval '1 day', 'by hand'); raise exception 'sla_extensions written by hand';
      exception when insufficient_privilege then null; end;
      begin update public.retirement_requests set status = 'approved'; raise exception 'retirement_requests written by hand';
      exception when insufficient_privilege then null; end;
      begin delete from public.users where id = v_res; raise exception 'a user was deleted through the API';
      exception when insufficient_privilege then null; end;
      begin insert into public.users (id, full_name, mobile_number, role) values (gen_random_uuid(), 'Made, By Hand', '+639999999979', 'resident'); raise exception 'a user was inserted through the API';
      exception when insufficient_privilege then null; end;
    end loop;
    reset role;
    v_log := v_log || E'\n' || 'ok  extensions, retirement decisions and accounts are written by the functions alone (no insert or delete of users through the API)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL other tables: ' || sqlerrm; end;

  -- 3. look_shares: the portal inserts, the tanod marks it seen, nobody rewrites or deletes it
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    insert into public.look_shares (report_id, tanod_id, sent_by, message) values (r1, v_tan, v_sup, 'Look at the corner') returning id into ls;
    begin update public.look_shares set message = 'changed' where id = ls; raise exception 'an administrator rewrote a share';
    exception when insufficient_privilege then null; end;
    begin delete from public.look_shares where id = ls; raise exception 'an administrator deleted a share';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    update public.look_shares set read_at = now() where id = ls;
    if (select read_at from public.look_shares where id = ls) is null then raise exception 'the tanod could not mark it seen'; end if;
    begin update public.look_shares set message = 'mine now' where id = ls; raise exception 'the tanod rewrote a share';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a look-around is sent by the portal, marked seen by the tanod, and rewritten or deleted by nobody';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL look_shares: ' || sqlerrm; end;

  -- 4. notifications: a person marks theirs read and cannot rewrite them
  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_res, r1, 'status_change', 'Your report is being reviewed') returning id into n1;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    update public.notifications set is_read = true where id = n1;
    if not (select is_read from public.notifications where id = n1) then raise exception 'could not mark a notification read'; end if;
    begin update public.notifications set message = 'You won a prize' where id = n1; raise exception 'a notification was rewritten';
    exception when insufficient_privilege then null; end;
    begin update public.notifications set report_id = null where id = n1; raise exception 'a notification was detached from its case';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a person marks their notifications read and cannot change their words or their case';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL notifications: ' || sqlerrm; end;

  -- 5. the rights themselves: no insert, update or delete left on the tables the functions write, and one column on the other two
  begin
    foreach t in array array['dispatches', 'sla_extensions', 'retirement_requests'] loop
      if has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
         or has_table_privilege('authenticated', 'public.' || t, 'delete') then raise exception 'signed-in callers can still write %', t; end if;
    end loop;
    if has_table_privilege('authenticated', 'public.users', 'insert') or has_table_privilege('authenticated', 'public.users', 'delete') then raise exception 'users can still be inserted or deleted'; end if;
    if has_table_privilege('authenticated', 'public.look_shares', 'update') or has_table_privilege('authenticated', 'public.look_shares', 'delete')
       or not has_column_privilege('authenticated', 'public.look_shares', 'read_at', 'update') then raise exception 'look_shares rights are not read_at only'; end if;
    if has_table_privilege('authenticated', 'public.notifications', 'update') or not has_column_privilege('authenticated', 'public.notifications', 'is_read', 'update') then
      raise exception 'notifications rights are not is_read only';
    end if;
    v_log := v_log || E'
' || 'ok  the rights match: nothing left to write by hand, one column each on look_shares and notifications';
  exception when others then v_log := v_log || E'
' || 'FAIL rights: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
