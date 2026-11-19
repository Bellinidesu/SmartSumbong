-- 53_case_hierarchy.sql: the case hierarchy (0175, Rose 19 Nov 2026). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kpo2 uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid();
  v_stf uuid := gen_random_uuid(); v_stf2 uuid := gen_random_uuid(); v_senv uuid := gen_random_uuid(); v_res uuid := gen_random_uuid(); v_sup2 uuid := gen_random_uuid();
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; n integer; s text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999801', 'Rung, Super'), (v_kpo, '+639999999802', 'Rung, Peace'), (v_kpo2, '+639999999803', 'Rung, Peace Two'),
                 (v_kenv, '+639999999804', 'Rung, Env'), (v_stf, '+639999999805', 'Rung, Staff'), (v_stf2, '+639999999806', 'Rung, Staff Two'),
                 (v_senv, '+639999999807', 'Rung, Env Staff'), (v_res, '+639999999808', 'Rung, Ana'), (v_sup2, '+639999999809', 'Rung, Super Two')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kpo2, v_kenv, v_stf, v_stf2, v_senv, v_res, v_sup2);
  update public.users set role = 'admin', admin_tier = 'super' where id in (v_sup, v_sup2);
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id in (v_kpo, v_kpo2);
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id in (v_stf, v_stf2);
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'environment' where id = v_senv;
  -- no other administrator of these committees is left from an earlier check (each rolls back), and Health and Sanitation has no Kagawad
  update public.users set admin_tier = 'super', committee = null where role = 'admin' and committee = 'health_sanitation' and admin_tier in ('committee', 'moderator');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Away', 'May nag-aaway sa kanto gabi-gabi.', lat, lng + 0.001) returning id into r2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Tambay', 'Mga tambay hanggang madaling araw sa tindahan.', lat + 0.001, lng) returning id into r3;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa tabi ng kanal.', lat + 0.001, lng + 0.001) returning id into r4;

  -- 1. staff do not see a case of their committee that nobody assigned to them, in any table, nor are told about it
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if exists (select 1 from public.reports where id in (r1, r2, r3)) then raise exception 'staff read an unassigned case'; end if;
    if exists (select 1 from public.status_logs where report_id = r1) or exists (select 1 from public.report_concerns where report_id = r1)
       or exists (select 1 from public.report_triage where report_id = r1) then raise exception 'staff read an unassigned case''s rows'; end if;
    if exists (select 1 from public.smart_queue(null, 500) q where q.report_id in (r1, r2, r3)) then raise exception 'the queue lists it to staff'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if (select count(*) from public.reports where id in (r1, r2, r3)) <> 3 then raise exception 'the Kagawad does not read the committee''s cases'; end if;
    reset role;
    insert into public.notifications (user_id, report_id, kind, message) values (v_stf, r1, 'sla_warning', 'A report has been waiting');
    if exists (select 1 from public.notifications where user_id = v_stf and report_id = r1) then raise exception 'staff were told of an unassigned case'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.take_case(r1); raise exception 'staff took a case';
    exception when insufficient_privilege then null; end;
    begin perform public.review_report(r1, 'validate'); raise exception 'staff accepted an unassigned case';
    exception when others then if sqlerrm like 'staff accepted%' then raise; end if; end;
    v_log := v_log || E'\n' || 'ok  staff do not read, list or hear of a committee case nobody assigned to them, and cannot take one';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL unassigned: ' || sqlerrm; end;

  -- 2. a Kagawad assigns to their own staff only; staff never assign; the staff member is told and reads it, but acts only after accepting
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.assign_case(r1, v_senv, null); raise exception 'a Kagawad assigned to another committee''s staff';
    exception when insufficient_privilege then null; end;
    begin perform public.assign_case(r1, v_kpo2, null); raise exception 'a Kagawad assigned to another Kagawad';
    exception when insufficient_privilege then null; end;
    if exists (select 1 from public.case_assignees(r1) a where a.id in (v_senv, v_kpo2, v_kpo)) or not exists (select 1 from public.case_assignees(r1) a where a.id = v_stf) then
      raise exception 'the Kagawad''s pick list is wrong'; end if;
    perform public.assign_case(r1, v_stf, 'Ikaw na ang bahala');
    select handler_id::text || '|' || assigned_to::text || '|' || assigned_by::text into s from public.reports where id = r1;
    if s <> v_kpo::text || '|' || v_stf::text || '|' || v_kpo::text then raise exception 'after assigning: %', s; end if;
    if not exists (select 1 from public.notifications where user_id = v_stf and report_id = r1 and kind::text = 'case_assigned') then raise exception 'staff not told'; end if;
    if not exists (select 1 from public.case_handler_log where report_id = r1 and action = 'assign' and to_id = v_stf) then raise exception 'not logged'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.assign_case(r1, v_stf2, null); raise exception 'staff assigned a case';
    exception when insufficient_privilege then null; end;
    begin perform public.post_report_message(r1, 'Hello po'); raise exception 'staff acted before accepting';
    exception when others then if sqlerrm like 'staff acted%' then raise; end if; end;
    execute 'set local role authenticated';
    if not exists (select 1 from public.reports where id = r1) then raise exception 'staff cannot read the case assigned to them'; end if;
    if exists (select 1 from public.reports where id = r2) then raise exception 'staff read another case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a Kagawad assigns to their own staff only (staff never assign); the staff member is told, reads it, and acts only after accepting';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL assign: ' || sqlerrm; end;

  -- 3. declining needs a reason; the case stays with whoever assigned it, who is told, and staff no longer read it
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.answer_case_assignment(r1, false, ''); raise exception 'declined without a reason';
    exception when check_violation then null; end;
    perform public.answer_case_assignment(r1, false, 'Naka-leave po ako bukas');
    if (select handler_id::text || '|' || coalesce(assigned_to::text, 'none') from public.reports where id = r1) <> v_kpo::text || '|none' then raise exception 'not back with the Kagawad'; end if;
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r1 and message like '%declined%Naka-leave%') then raise exception 'the Kagawad not told'; end if;
    execute 'set local role authenticated';
    if exists (select 1 from public.reports where id = r1) then raise exception 'staff still read a case they declined'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  declining needs a reason; the case stays with whoever assigned it, who is told; staff no longer read it';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL decline: ' || sqlerrm; end;

  -- 4. accepting makes the staff member the handler; the Kagawad is told; nobody writes the handler or the assignment by hand
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.assign_case(r1, v_stf, null);
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    perform public.answer_case_assignment(r1, true, null);
    if (select handler_id::text || '|' || coalesce(assigned_to::text, 'none') from public.reports where id = r1) <> v_stf::text || '|none' then raise exception 'not the staff member''s'; end if;
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r1 and message like '%accepted%') then raise exception 'the Kagawad not told'; end if;
    perform public.post_report_message(r1, 'Pupuntahan po namin');
    execute 'set local role authenticated';
    begin update public.reports set handler_id = v_stf2 where id = r1; raise exception 'the handler was moved by hand';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin update public.reports set assigned_to = v_stf2 where id = r2; raise exception 'assigned by hand';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  accepting makes the staff member the handler (the Kagawad is told, they work it); nobody moves the handler or the assignment by hand';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL accept: ' || sqlerrm; end;

  -- 5. taking over: staff never; a Kagawad from their own staff only; a super admin from anyone. Staff keep reading a case they had
  begin
    perform set_config('request.jwt.claim.sub', v_stf2::text, true);
    begin perform public.take_over_case(r1, 'Ako na po'); raise exception 'staff took over';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.take_over_case(r1, 'Kami na'); raise exception 'another committee''s Kagawad took over';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo2::text, true);
    perform public.take_over_case(r1, 'Ako muna ang hahawak');
    if (select handler_id from public.reports where id = r1) <> v_kpo2 then raise exception 'the Kagawad did not take it from their staff'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.take_over_case(r1, 'Akin ito'); raise exception 'a Kagawad took over from another Kagawad';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.take_over_case(r1, 'Ako na ang bahala');
    if (select handler_id from public.reports where id = r1) <> v_sup then raise exception 'the super admin did not take it'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.take_over_case(r1, 'Ibalik sa amin'); raise exception 'a Kagawad took over from a super admin';
    exception when insufficient_privilege then null; end;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if not exists (select 1 from public.reports where id = r1) then raise exception 'staff lost the case they handled'; end if;
    reset role;
    begin perform public.post_report_message(r1, 'Update po'); raise exception 'staff still act on a case taken from them';
    exception when others then if sqlerrm like 'staff still act%' then raise; end if; end;
    v_log := v_log || E'\n' || 'ok  staff never take over; a Kagawad takes over from their own staff only; a super admin from anyone; staff keep reading what they handled';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL take over: ' || sqlerrm; end;

  -- 6. a super admin assigns to a councilor or to staff; another committee's staff member: the case moves to that committee (a forward)
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if not exists (select 1 from public.case_assignees(r2) a where a.id = v_kenv) or not exists (select 1 from public.case_assignees(r2) a where a.id = v_senv) then
      raise exception 'the super admin''s pick list is wrong'; end if;
    perform public.assign_case(r2, v_kpo, null);
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.answer_case_assignment(r2, true, null);
    if (select handler_id from public.reports where id = r2) <> v_kpo then raise exception 'the Kagawad did not accept'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.assign_case(r3, v_senv, 'Sa kapaligiran ito');
    if (select committee from public.reports where id = r3) <> 'environment' then raise exception 'the case did not move to the assignee''s committee'; end if;
    if not exists (select 1 from public.case_forwards where report_id = r3 and kind = 'forward' and to_committee = 'environment') then raise exception 'the move is not in the history'; end if;
    v_log := v_log || E'\n' || 'ok  a super admin assigns to a councilor (who accepts) or to staff; to another committee''s staff, the case moves there as a forward';
  exception when others then v_log := v_log || E'\n' || 'FAIL super assigns: ' || sqlerrm; end;

  -- 7. a waiting assignment ends when the case changes hands (here, a super admin takes it over)
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.assign_case(r2, v_stf2, null);
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.take_over_case(r2, 'Ako na ang hahawak');
    if (select assigned_to from public.reports where id = r2) is not null then raise exception 'the assignment outlived the take-over'; end if;
    v_log := v_log || E'
' || 'ok  a waiting assignment ends when the case changes hands (a take-over)';
  exception when others then v_log := v_log || E'
' || 'FAIL ends: ' || sqlerrm; end;

  -- 8. a forward tells only the committee it went to (by name), never its staff or another committee; no Kagawad there, the super admins
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.forward_case(r4, 'peace_order', 'Ingay ito, hindi basura', null);
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r4 and kind::text = 'case_forwarded' and message like '%forwarded to ' || public._committee_label('peace_order') || ' by%') then
      raise exception 'the receiving Kagawad was not told by name'; end if;
    if exists (select 1 from public.notifications where report_id = r4 and kind::text = 'case_forwarded' and user_id in (v_kenv, v_senv, v_stf, v_stf2)) then
      raise exception 'another committee or staff were told'; end if;
    perform public.forward_case(r4, 'health_sanitation', null, null);
    if not exists (select 1 from public.notifications where user_id = v_sup2 and report_id = r4 and kind::text = 'case_forwarded' and message like '%no Kagawad account%') then
      raise exception 'a committee with no Kagawad: the super admins were not told'; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if exists (select 1 from public.notifications where report_id = r4) then raise exception 'the Kagawad still sees the notice of a case that left'; end if;
    reset role;
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r4) then raise exception 'the notice was deleted, not hidden'; end if;
    v_log := v_log || E'\n' || 'ok  a forward tells only the receiving committee''s Kagawad, by name (not its staff, not another committee); no Kagawad there, the super admins; a notice of a case that left is no longer shown';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL forward: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
