-- 32_moderator.sql: staff as moderators; positions set the tier (0151). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kag uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_chr uuid := gen_random_uuid();
  v_ki uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r_po uuid; r_env uuid; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999931', 'Mod, Super'), (v_kag, '+639999999932', 'Mod, Kagawad'), (v_stf, '+639999999933', 'Mod, Staff'),
                 (v_chr, '+639999999934', 'Mod, Chair'), (v_ki, '+639999999935', 'Mod, Kiko'), (v_res, '+639999999936', 'Mod, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kag, v_stf, v_chr, v_ki, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id in (v_sup, v_ki);
  update public.users set role = 'admin', admin_tier = 'committee' where id in (v_kag, v_stf, v_chr);
  -- clear any Chairman already in the test database, so this one can be made
  update public.users set official_role = null where official_role = 'chairman';
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', lat, lng) returning id into r_po;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa tabi ng kanal.', lat, lng + 0.001) returning id into r_env;
  v_log := 'setup ok';

  -- 1. a position sets its tier: Chairman super admin, Kagawad committee, secretary moderator; a super admin stays one
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.set_official_role(v_chr, 'chairman', null, null);
    perform public.set_official_role(v_kag, 'kagawad', 'peace_order', null);
    perform public.set_official_role(v_stf, 'secretary', 'peace_order', null);
    perform public.set_official_role(v_ki, 'secretary', 'peace_order', null);
    if (select admin_tier from public.users where id = v_chr) <> 'super' then raise exception 'chairman not super'; end if;
    if (select admin_tier || '/' || committee from public.users where id = v_kag) <> 'committee/peace_order' then raise exception 'kagawad'; end if;
    if (select admin_tier || '/' || committee from public.users where id = v_stf) <> 'moderator/peace_order' then raise exception 'staff'; end if;
    if (select admin_tier from public.users where id = v_ki) <> 'super' then raise exception 'a super admin was lowered by a position'; end if;
    begin perform public.set_admin_access(v_kag, 'moderator', null, null); raise exception 'a moderator without a committee was taken';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  a position sets its tier (Chairman super admin, Kagawad committee, secretary moderator), a super admin stays one; a moderator needs a committee';
  exception when others then v_log := v_log || E'\n' || 'FAIL positions: ' || sqlerrm; end;

  -- 2. a moderator reads and works their committee's cases only
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    select count(*) into n from public.reports where id in (r_po, r_env);
    if n <> 1 or not exists (select 1 from public.reports where id = r_po) then raise exception 'reads % of the two', n; end if;
    if not public.admin_can_write() or not public.admin_scoped() then raise exception 'not a writing, scoped tier'; end if;
    reset role;   -- _scope_guard is internal (the case functions call it); as the moderator, outside the API role
    perform public._scope_guard(r_po, true);
    begin perform public._scope_guard(r_env, true); raise exception 'worked a case outside the committee';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  a moderator reads and works their committee''s cases, not another''s';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL scope: ' || sqlerrm; end;

  -- 3. the decisions that change who answers for a case are not a moderator's
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.hand_to_higher_official(r_po, 'chairman', null); raise exception 'a moderator handed a case up';
    exception when insufficient_privilege then null; end;
    begin perform public.refer_report(r_po, 'PNP', null); raise exception 'a moderator referred a case out';
    exception when insufficient_privilege then null; end;
    begin perform public.escalate_in_barangay(r_po, 'Needs the Chairman', null); raise exception 'a moderator escalated';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  a moderator cannot hand a case up, refer it out or escalate it';
  exception when others then v_log := v_log || E'\n' || 'FAIL decisions: ' || sqlerrm; end;

  -- 4. a moderator is never notified about a case outside their committee
  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_stf, r_env, 'status_change', 'outside'), (v_stf, r_po, 'status_change', 'inside');
    select count(*) into n from public.notifications where user_id = v_stf;
    if n <> 1 or not exists (select 1 from public.notifications where user_id = v_stf and report_id = r_po) then raise exception '% notifications', n; end if;
    v_log := v_log || E'\n' || 'ok  a moderator is notified about their committee''s cases only';
  exception when others then v_log := v_log || E'\n' || 'FAIL notify: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
