-- 71_case_rule_consistency.sql (test for 0191, applied 21 Nov 2026). Rolled back.
-- The four intended changes, each against an unchanged baseline: fails before 0191, passes after. (The 0189 equivalence stays pgTAP 67's.)
do $sweep$
declare
  v_log text := 'setup ok';
  ca text; cb text; cat_a public.complaint_category; cat_b public.complaint_category; n integer; b boolean;
  kA uuid := gen_random_uuid(); kA2 uuid := gen_random_uuid(); kOff uuid := gen_random_uuid(); kRet uuid := gen_random_uuid(); sA uuid := gen_random_uuid();
  sOff uuid := gen_random_uuid(); sup uuid := gen_random_uuid(); cap uuid := gen_random_uuid(); res uuid := gen_random_uuid();
  c_plain uuid; c_del uuid; c_ret uuid; c_off uuid; c_offh uuid; c_wait uuid; c_wait2 uuid;
  img text := 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/';
begin
  select c.key into ca from public.committees c where c.active and exists (select 1 from public.committee_categories cc where cc.committee = c.key) order by c.sort, c.key limit 1;
  select c.key into cb from public.committees c where c.active and c.key <> ca and exists (select 1 from public.committee_categories cc where cc.committee = c.key
          and cc.category not in (select category from public.committee_categories where committee = ca)) order by c.sort, c.key limit 1;
  select cc.category into cat_a from public.committee_categories cc where cc.committee = ca and cc.category not in (select category from public.committee_categories where committee = cb) limit 1;
  select cc.category into cat_b from public.committee_categories cc where cc.committee = cb and cc.category not in (select category from public.committee_categories where committee = ca) limit 1;
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', img || 'ids/' || gen_random_uuid() || '.jpg', 'selfie_url', img || 'selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (kA, '+639999997101', 'Cons, Kagawad A'), (kA2, '+639999997102', 'Cons, Kagawad A Two'), (kOff, '+639999997103', 'Cons, Kagawad Off'),
                 (kRet, '+639999997104', 'Cons, Kagawad Retired'), (sA, '+639999997105', 'Cons, Staff A'), (sOff, '+639999997106', 'Cons, Staff Off'),
                 (sup, '+639999997107', 'Cons, Super'), (cap, '+639999997108', 'Cons, Captain'), (res, '+639999997109', 'Cons, Resident')) as x(id, mob, nm);
  set local session_replication_role = replica;
  update public.users set verification_status = 'verified', verified_at = now() where id in (kA, kA2, kOff, kRet, sA, sOff, sup, cap, res);
  update public.users set role = 'admin', admin_tier = 'committee', committee = ca where id in (kA, kA2, kRet);
  update public.users set role = 'admin', admin_tier = 'committee', committee = cb where id = kOff;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = ca where id = sA;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = cb where id = sOff;
  update public.users set role = 'admin', admin_tier = 'super' where id = sup;
  update public.users set role = 'admin', admin_tier = 'captain' where id = cap;
  update public.users set is_retired = true where id = kRet;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-01', res, cat_a, 'Plain', 'ordinary case of committee A', 14.519, 121.012, ca, false, null, null) returning id into c_plain;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-02', res, cat_a, 'Deleted', 'a deleted case of committee A', 14.519, 121.012, ca, false, null, now()) returning id into c_del;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-03', res, cat_a, 'Retired handler', 'handled by a retired Kagawad', 14.519, 121.012, ca, false, kRet, null) returning id into c_ret;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-04', res, cat_b, 'Off committee', 'with committee B, which is switched off below', 14.519, 121.012, cb, false, null, null) returning id into c_off;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-05', res, cat_b, 'Off committee handled', 'with committee B, handled by its Kagawad', 14.519, 121.012, cb, false, kOff, null) returning id into c_offh;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-06', res, cat_a, 'Awaiting, handled by A', 'waiting for placement, handled by Kagawad A', 14.519, 121.012, null, true, kA, null) returning id into c_wait;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, deleted_at)
  values ('CONS-07', res, cat_a, 'Awaiting, handled by A2', 'waiting for placement, handled by another Kagawad of A', 14.519, 121.012, null, true, kA2, null) returning id into c_wait2;
  insert into public.status_logs (report_id, changed_by, new_status, remark, is_system) select id, res, 'pending_review', 'cons', true from public.reports where subject in
    ('Plain', 'Deleted', 'Retired handler', 'Off committee', 'Off committee handled', 'Awaiting, handled by A', 'Awaiting, handled by A2');
  set local session_replication_role = origin;
  update public.committees set active = false where key = cb;   -- (3) committee B is switched off from here on

  -- the baseline that must not change: an ordinary case of the Kagawad's committee is read by both Kagawads of it and by the staff only once assigned
  begin
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_plain; execute 'reset role';
    if n <> 1 then raise exception 'Kagawad A does not read the ordinary case'; end if;
    if not public._user_sees_case(kA, c_plain, cat_a, null) or not public._user_sees_case(kA2, c_plain, cat_a, null) then raise exception 'the function says a Kagawad of the committee does not see it'; end if;
    if public._user_sees_case(sA, c_plain, cat_a, null) then raise exception 'unassigned staff see it'; end if;
    v_log := v_log || E'\nok  baseline: an ordinary case of committee A is read by its Kagawads and not by unassigned staff';
  exception when others then reset role; v_log := v_log || E'\nFAIL baseline: ' || sqlerrm; end;

  -- 1. deleted cases
  begin
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n <> 0 then raise exception 'a Kagawad reads the status log of a deleted case (% rows)', n; end if;
    if public._user_sees_case(kA, c_del, cat_a, null) then raise exception 'the function says a Kagawad sees the deleted case'; end if;
    perform set_config('request.jwt.claim.sub', sup::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n = 0 then raise exception 'a super admin no longer reads a deleted case''s rows'; end if;
    perform set_config('request.jwt.claim.sub', cap::text, true); execute 'set local role authenticated';
    select count(*) into n from public.status_logs where report_id = c_del; execute 'reset role';
    if n = 0 then raise exception 'the captain no longer reads a deleted case''s rows'; end if;
    v_log := v_log || E'\nok  (1) a deleted case and its rows are hidden from a Kagawad (policy and function); the super admin and the captain still read them';
  exception when others then reset role; v_log := v_log || E'\nFAIL (1) deleted: ' || sqlerrm; end;

  -- 2. retired
  begin
    if public._user_sees_case(kRet, c_ret, cat_a, kRet) or public._user_sees_case(kRet, c_plain, cat_a, null) then raise exception 'the function says a retired Kagawad sees a case'; end if;
    perform set_config('request.jwt.claim.sub', kRet::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id in (c_ret, c_plain); execute 'reset role';
    if n <> 0 then raise exception 'a retired Kagawad reads % cases', n; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (kRet, c_ret, 'status_change', 'for a retired admin about a case');
    insert into public.notifications (user_id, kind, message) values (kRet, 'status_change', 'for a retired admin, no case');
    if exists (select 1 from public.notifications where message = 'for a retired admin about a case') then raise exception 'a case notice reached a retired admin'; end if;
    if not exists (select 1 from public.notifications where message = 'for a retired admin, no case') then raise exception 'a notice with no case no longer reaches a retired admin'; end if;
    v_log := v_log || E'\nok  (2) a retired Kagawad sees nothing (not even the case they handled) and case notices to them are dropped; a notice with no case still arrives';
  exception when others then reset role; v_log := v_log || E'\nFAIL (2) retired: ' || sqlerrm; end;

  -- 3. committee switched on
  begin
    if public._user_sees_case(kOff, c_off, cat_b, null) then raise exception 'the function says the Kagawad of a switched-off committee sees its case'; end if;
    perform set_config('request.jwt.claim.sub', kOff::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_off; execute 'reset role';
    if n <> 0 then raise exception 'the Kagawad of a switched-off committee reads its case'; end if;
    perform set_config('request.jwt.claim.sub', kOff::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_offh; execute 'reset role';
    if n <> 1 then raise exception 'the Kagawad no longer reads the case they handle'; end if;
    perform set_config('request.jwt.claim.sub', sup::text, true); execute 'set local role authenticated';
    begin perform public.assign_case(c_plain, sOff, 'probe'); raise exception 'assign_case placed a case with a switched-off committee';
    exception when check_violation then null; end;
    select count(*) into n from public.reports where id = c_off; execute 'reset role';
    if n <> 1 then raise exception 'a super admin no longer reads the case'; end if;
    v_log := v_log || E'\nok  (3) a switched-off committee''s Kagawad no longer sees its cases (the one they handle stays); a super admin sees it and cannot place a case with that committee';
  exception when others then reset role; v_log := v_log || E'\nFAIL (3) committee on: ' || sqlerrm; end;

  -- 4. awaiting placement
  begin
    if not public._user_sees_case(kA, c_wait, cat_a, kA) then raise exception 'the function says the handling Kagawad does not see their awaiting case'; end if;
    if public._user_sees_case(kA, c_wait2, cat_a, kA2) then raise exception 'the function says a Kagawad sees another Kagawad''s awaiting case'; end if;
    perform set_config('request.jwt.claim.sub', kA::text, true); execute 'set local role authenticated';
    select count(*) into n from public.reports where id = c_wait; if n <> 1 then raise exception 'the handling Kagawad does not read their awaiting case'; end if;
    select count(*) into n from public.status_logs where report_id = c_wait; if n <> 1 then raise exception 'the handling Kagawad does not read its status log'; end if;
    select count(*) into n from public.reports where id = c_wait2; execute 'reset role';
    if n <> 0 then raise exception 'a Kagawad reads another Kagawad''s awaiting case'; end if;
    v_log := v_log || E'\nok  (4) the Kagawad who handles a case that awaits placement still sees it (case and rows); another Kagawad of the committee does not';
  exception when others then reset role; v_log := v_log || E'\nFAIL (4) awaiting placement: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
