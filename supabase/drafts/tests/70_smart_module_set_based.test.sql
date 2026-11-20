-- 70_smart_module_set_based.sql (DRAFT test for 0190; moves to supabase/tests/ when Ace says apply). Rolled back.
-- Fails before 0190 on the structure check (smart_module still calls the case rule per case); the equivalence check passes before and after: the old body
-- is compared with the new one for every rung on the exhaustive fixture of test 67, in three fixture variants (statuses and due dates, referral and taken-over cases,
-- moved assignments and a case waiting for placement).
do $sweep$
declare
  v_log text := 'setup ok';
  ca text; cb text; cat_a public.complaint_category; cat_b public.complaint_category;
  p record; t text; n_rls int; n_exp int; bad text := ''; s text;
  kA uuid := gen_random_uuid(); kB uuid := gen_random_uuid(); sA uuid := gen_random_uuid(); sA2 uuid := gen_random_uuid(); sup uuid := gen_random_uuid();
  cap uuid := gen_random_uuid(); res uuid := gen_random_uuid(); res2 uuid := gen_random_uuid(); tan uuid := gen_random_uuid();
  kSusp uuid := gen_random_uuid(); sRet uuid := gen_random_uuid();
  c_open uuid; c_com uuid; c_away uuid; c_wait uuid; c_hand uuid; c_asg uuid; c_took uuid; c_decl uuid; c_conc uuid; c_del uuid; c_sens uuid; c_tan uuid;
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
    from (values (kA, '+639999996701', 'Rule, Kagawad A'), (kB, '+639999996702', 'Rule, Kagawad B'), (sA, '+639999996703', 'Rule, Staff A'),
                 (sA2, '+639999996704', 'Rule, Staff A Two'), (sup, '+639999996705', 'Rule, Super'), (cap, '+639999996706', 'Rule, Captain'),
                 (res, '+639999996707', 'Rule, Resident'), (res2, '+639999996708', 'Rule, Resident Two'), (tan, '+639999996709', 'Rule, Tanod'),
                 (kSusp, '+639999996710', 'Rule, Kagawad Suspended'), (sRet, '+639999996711', 'Rule, Staff Retired')) as x(id, mob, nm);
  set local session_replication_role = replica;
  update public.users set verification_status = 'verified', verified_at = now() where id in (kA, kB, sA, sA2, sup, cap, res, res2, tan, kSusp, sRet);
  update public.users set role = 'admin', admin_tier = 'committee', committee = ca where id in (kA, kSusp);
  update public.users set role = 'admin', admin_tier = 'committee', committee = cb where id = kB;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = ca where id in (sA, sA2, sRet);
  update public.users set role = 'admin', admin_tier = 'super' where id = sup;
  update public.users set role = 'admin', admin_tier = 'captain' where id = cap;
  update public.users set role = 'tanod', duty_status = 'on_duty' where id = tan;
  update public.users set is_suspended = true where id = kSusp;
  update public.users set is_retired = true where id = sRet;
  -- the cases (written as the superuser: the point is reading them back)
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-01', res, cat_a, 'Open, no committee', 'A case of committee A''s category with no committee yet', 14.519, 121.012, null, false, null, null, null, null, false) returning id into c_open;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-02', res, cat_b, 'Forwarded in', 'A case of B''s category forwarded to committee A', 14.519, 121.012, ca, false, null, null, null, null, false) returning id into c_com;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-03', res, cat_a, 'Forwarded away', 'A case of A''s category forwarded away to committee B', 14.519, 121.012, cb, false, null, null, null, null, false) returning id into c_away;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-04', res, cat_a, 'Waiting for placement', 'Handled by Kagawad A but waiting for placement', 14.519, 121.012, null, true, kA, sA, kA, null, false) returning id into c_wait;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-05', res2, cat_b, 'Handled out of scope', 'Kagawad A handles a case of B''s category (an escalation)', 14.519, 121.012, null, false, kA, null, null, null, false) returning id into c_hand;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-06', res, cat_b, 'Assigned to staff', 'Assigned to staff A, not yet accepted', 14.519, 121.012, cb, false, kB, sA, kB, null, false) returning id into c_asg;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-07', res, cat_b, 'Previously handled', 'Staff A accepted it once; now Kagawad B has it', 14.519, 121.012, cb, false, kB, null, null, null, false) returning id into c_took;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-08', res, cat_b, 'Declined', 'Staff A declined it: that is no hold on the case', 14.519, 121.012, cb, false, kB, null, null, null, false) returning id into c_decl;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-09', res, cat_b, 'Concern in A', 'A case of B''s category with a concern in A''s', 14.519, 121.012, null, false, null, null, null, null, false) returning id into c_conc;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-10', res2, cat_a, 'Deleted', 'A deleted case of A''s category', 14.519, 121.012, null, false, null, null, null, now(), false) returning id into c_del;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-11', res, cat_a, 'Sensitive', 'A sensitive case of A''s category', 14.519, 121.012, null, false, null, null, null, null, true) returning id into c_sens;
  insert into public.reports (tracking_id, resident_id, category, subject, description, latitude, longitude, committee, awaiting_placement, handler_id, assigned_to, assigned_by, deleted_at, is_sensitive)
  values ('RULE-12', res2, cat_b, 'Dispatched', 'A case of B with the tanod dispatched', 14.519, 121.012, cb, false, kB, null, null, null, false) returning id into c_tan;
  insert into public.report_concerns (report_id, category) select id, category from public.reports where tracking_id like 'RULE-%';
  insert into public.report_concerns (report_id, category) values (c_conc, cat_a);
  insert into public.case_handler_log (report_id, admin_id, action) values (c_took, sA, 'accept'), (c_decl, sA, 'decline'), (c_decl, sA, 'assign');
  insert into public.dispatches (report_id, tanod_id, assigned_by, state, accepted_at, is_primary) values (c_tan, tan, kB, 'accepted', now(), true);
  insert into public.status_logs (report_id, changed_by, new_status, remark, is_system) select id, resident_id, 'pending_review', 'rule', true from public.reports where tracking_id like 'RULE-%';
  insert into public.notifications (user_id, report_id, kind, message)
  select u, r.id, 'status_change', 'rule' from public.reports r, unnest(array[kA, kB, sA, sA2, sup, cap, res, tan, kSusp, sRet]) u where r.tracking_id like 'RULE-%';
  set local session_replication_role = origin;


  -- 0190: smart_module() reads the case set once. Old body kept as _smart_module_old for the comparison (this test only; rolled back).
  declare v_old text := $oldfn$create or replace function public._smart_module_old()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
declare
  v_me   uuid := auth.uid();
  v_tier text := public.admin_tier();
  v_full boolean := coalesce(public.is_full_viewer(), false);
  v_com  text;
  v_mod  text;
  v_cats text[];
  v jsonb;
begin
  if v_tier is null then raise exception 'Only an administrator has a SMART module.' using errcode = 'insufficient_privilege'; end if;
  select u.committee into v_com from public.users u where u.id = v_me;
  v_mod := case when v_full then 'barangay' when v_tier = 'committee' then 'committee' else 'staff' end;
  if not v_full then
    select coalesce(array_agg(cc.category::text order by cc.category), '{}') into v_cats
      from public.committee_categories cc join public.committees c on c.key = cc.committee and c.active
     where cc.committee = v_com;
  end if;

  with open_cases as (
    select r.id, r.tracking_id, r.category, r.status, r.due_at, r.handler_id, r.awaiting_placement, r.subject
      from public.reports r
     where r.deleted_at is null and r.referred_to is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and (v_full or public._user_sees_case(v_me, r.id, r.category, r.handler_id))
  ),
  waiting as (   -- validated or still in review, and no tanod on it: what the triage level is for
    select o.id, t.effective_level as lvl from open_cases o join public.report_triage t on t.report_id = o.id
     where o.status in ('pending_review', 'validated')
       and not exists (select 1 from public.dispatches d where d.report_id = o.id and d.state in ('assigned', 'accepted'))
  ),
  members as (   -- the tanods this module watches: every active tanod, or the committee's approved ones
    select u.id, u.duty_status,
           exists (select 1 from public.dispatches d where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) as busy
      from public.users u
     where u.role = 'tanod' and u.removed_at is null and u.verification_status = 'verified'
       and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
       and (v_full or exists (select 1 from public.tanod_committees tc where tc.tanod_id = u.id and tc.committee = v_com and tc.status = 'approved'))
  )
  select jsonb_build_object(
    'module', v_mod,
    'committee', case when v_full then null else v_com end,
    'categories', case when v_full then null else to_jsonb(v_cats) end,
    'counts', jsonb_build_object(
      'open',           (select count(*) from open_cases),
      'urgent_waiting', (select count(*) from waiting where lvl = 'urgent'),
      'high_waiting',   (select count(*) from waiting where lvl = 'high'),
      'overdue',        (select count(*) from open_cases where due_at < now()),
      'due_24h',        (select count(*) from open_cases where due_at >= now() and due_at < now() + interval '24 hours'),
      'untaken',        (select count(*) from open_cases where handler_id is null and not awaiting_placement),
      'mine',           (select count(*) from open_cases where handler_id = v_me),
      'to_accept',      (select count(*) from public.reports r where r.assigned_to = v_me and r.deleted_at is null)),
    'decisions', case
      when v_mod = 'staff' or v_tier = 'captain' then null
      else jsonb_build_object(
        'escalations', (select count(*) from public.escalation_requests e join open_cases o on o.id = e.report_id where e.status = 'pending'),
        'reroute',     (select count(*) from public.reroute_questions q where q.state = 'open' and (v_full or q.committee = v_com)),
        'forwarded',   (select count(*) from public.notifications n where n.user_id = v_me and n.kind = 'case_forwarded' and not n.is_read),
        'flags',       (select count(*) from public.case_forward_flags f where (v_full and f.to_super) or (not v_full and f.from_committee = v_com)),
        'to_place',    case when v_full then (select count(*) from public.reports r where r.awaiting_placement and r.deleted_at is null) end,
        'tanods_proposed', case when v_full then (select count(*) from public.tanod_committees where status = 'proposed') end)
    end,
    'deadline_risk', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.hours_left) from (
        select d.report_id, d.tracking_id, d.due_at, round(d.hours_left, 1) as hours_left, d.risk, d.reasons
          from public._snap_deadline_risk() d join open_cases o on o.id = d.report_id
         order by d.hours_left limit 8) x), '[]'::jsonb),
    'quiet', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.days_quiet desc) from (
        select s.report_id, s.tracking_id, s.status, s.days_quiet, s.last_activity
          from public._snap_stuck() s join open_cases o on o.id = s.report_id
         order by s.days_quiet desc limit 8) x), '[]'::jsonb),
    'spikes', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.times_usual desc) from (
        select s.category, s.this_week, s.usual, s.times_usual, s.place
          from public._snap_spikes() s where v_full or s.category::text = any (v_cats)) x), '[]'::jsonb),
    'patterns', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.still_open desc, x.reports desc) from (
        select p.pattern_key, p.category, p.reports, p.weeks, p.residents, p.still_open, p.hazard, p.last_at, case when v_tier = 'moderator' then array(select r.tracking_id from public.reports r where r.tracking_id = any (p.tracking_ids[1:3]) and public._user_sees_case(v_me, r.id, r.category, r.handler_id)) else p.tracking_ids[1:3] end as tracking_ids
          from public._snap_patterns() p where v_full or p.category::text = any (v_cats)
         order by p.still_open desc, p.reports desc limit 6) x), '[]'::jsonb),
    'tanods', jsonb_build_object(
      'total',    (select count(*) from members),
      'on_duty',  (select count(*) from members where duty_status = 'on_duty' and not busy),
      'busy',     (select count(*) from members where busy),
      'lunch',    (select count(*) from members where duty_status = 'lunch'),
      'break',    (select count(*) from members where duty_status = 'break'),
      'offline',  (select count(*) from members where coalesce(duty_status, 'offline') = 'offline' and not busy)),
    'at', now())
  into v;
  return v;
end $function$;$oldfn$; src text; a record; jo jsonb; jn jsonb; e1 text; e2 text; sd text := ''; k text; nkeys int := 0; vr int; ntests int := 0;
  begin
    begin
      select prosrc into src from pg_proc where oid = 'public.smart_module()'::regprocedure;
      if src like '%_user_sees_case%' then raise exception 'smart_module still runs the case rule once per case'; end if;
      if src not like '%_my_scoped_case_ids%' then raise exception 'smart_module does not read the set helper'; end if;
      v_log := v_log || E'\nok  smart_module reads the case set once (_my_scoped_case_ids) and never calls _user_sees_case per case';
    exception when others then v_log := v_log || E'\nFAIL structure: ' || sqlerrm; end;
    execute v_old;
    -- a pattern's tracking ids are compared as sets (the old body listed them in an unspecified order)
    create function pg_temp.norm(j jsonb) returns jsonb language sql as $n$
      select case when jsonb_typeof(j) = 'array' then coalesce((select jsonb_agg(case when jsonb_typeof(e) = 'object' and e ? 'tracking_ids'
             then (e - 'tracking_ids') || jsonb_build_object('tracking_ids', (select coalesce(jsonb_agg(t order by t), '[]') from jsonb_array_elements_text(e->'tracking_ids') t)) else e end order by ord)
             from jsonb_array_elements(j) with ordinality x(e, ord)), '[]') else j end $n$;
    perform public._smart_snapshot_refresh(true);
    for vr in 1..3 loop
      set local session_replication_role = replica;
      if vr = 1 then
        update public.reports set due_at = now() - interval '2 days' where tracking_id in ('RULE-01', 'RULE-05');
        update public.reports set due_at = now() + interval '12 hours' where tracking_id in ('RULE-02', 'RULE-09');
        update public.reports set status = 'validated' where tracking_id in ('RULE-01', 'RULE-02', 'RULE-09', 'RULE-12');
      elsif vr = 2 then   -- statuses, a referral, finished cases, a case taken over
        update public.reports set status = 'in_progress' where tracking_id in ('RULE-02', 'RULE-05');
        update public.reports set status = 'resolved' where tracking_id in ('RULE-03', 'RULE-12');
        update public.reports set referred_to = 'barangay court' where tracking_id = 'RULE-09';
        update public.reports set handler_id = (select id from public.users where full_name = 'Rule, Kagawad A') where tracking_id in ('RULE-07', 'RULE-12');
      else                -- assignments moved, a handler removed, a case waiting for placement, escalations pending
        update public.reports set handler_id = null, awaiting_placement = true where tracking_id = 'RULE-05';
        update public.reports set assigned_to = (select id from public.users where full_name = 'Rule, Staff A Two') where tracking_id in ('RULE-06', 'RULE-12');
        update public.reports set status = 'pending_review' where tracking_id in ('RULE-03', 'RULE-12', 'RULE-07');
        delete from public.case_handler_log where action = 'accept';
      end if;
      set local session_replication_role = origin;
      perform public.smart_triage(id) from public.reports where tracking_id like 'RULE-%' and deleted_at is null;
      for a in select * from (values (kA, 'kA'), (kB, 'kB'), (sA, 'sA'), (sA2, 'sA2'), (sup, 'sup'), (cap, 'cap'), (kSusp, 'kSusp'), (sRet, 'sRet'), (res, 'res'), (tan, 'tan')) x(id, nm) loop
        perform set_config('request.jwt.claim.sub', a.id::text, true); e1 := null; e2 := null; jo := null; jn := null;
        begin jo := public._smart_module_old() - 'at'; exception when others then e1 := sqlstate; end;
        begin jn := public.smart_module() - 'at'; exception when others then e2 := sqlstate; end;
        ntests := ntests + 1;
        if jo is not null then jo := jo || jsonb_build_object('patterns', pg_temp.norm(jo->'patterns')); end if;
        if jn is not null then jn := jn || jsonb_build_object('patterns', pg_temp.norm(jn->'patterns')); end if;
        if jo is not null then jo := jo || jsonb_build_object('quiet', (select coalesce(jsonb_agg(e->'days_quiet' order by (e->>'days_quiet')::numeric), '[]') from jsonb_array_elements(jo->'quiet') e)); end if;
        if jn is not null then jn := jn || jsonb_build_object('quiet', (select coalesce(jsonb_agg(e->'days_quiet' order by (e->>'days_quiet')::numeric), '[]') from jsonb_array_elements(jn->'quiet') e)); end if;
        if e1 is distinct from e2 then sd := sd || format(' v%s %s error %s<>%s;', vr, a.nm, e1, e2);
        elsif jo is distinct from jn then
          for k in select key from (select key, value from jsonb_each(jo) except select key, value from jsonb_each(jn)
                                    union select key, value from jsonb_each(jn) except select key, value from jsonb_each(jo)) d group by key loop
            sd := sd || format(' v%s %s differs in %s;', vr, a.nm, k);
          end loop;
        end if;
      end loop;
    end loop;
    if sd <> '' then v_log := v_log || E'\nFAIL equivalence:' || sd;
    else v_log := v_log || format(E'\nok  smart_module() and the old body return the same document (symmetric difference 0) for every rung (Kagawad, suspended Kagawad, staff, retired staff, super, captain; resident and tanod refused alike) in 3 fixture variants: %s comparisons', ntests); end if;
  end;
  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
