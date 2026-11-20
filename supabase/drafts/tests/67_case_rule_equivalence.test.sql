-- 67_case_rule_equivalence.sql (UPDATED for 0191: when Ace says apply 0191 this file replaces supabase/tests/67_...; it passes only after 0191): who reads which case, and every row hanging off it, is exactly the 0175 rule (K-04, 20 Nov 2026). Rolled back.
-- Passes on the per-row policies (0001-0188) and on 0189's set-based ones; fails on a rule that drifts from _user_sees_case in any branch.
-- The oracle is _user_sees_case(person, case, ...) itself (0189 does not touch it), checked per person and per table as the API's own role,
-- plus named cases so a wrong oracle cannot hide a mistake, and a revoked assignment that must count from the very next statement.
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

  -- 1. per person and table: what row level security lets them read = the oracle (_user_sees_case for a Kagawad or staff member)
  begin
    for p in select x.id, x.nm, (u.role = 'admin' and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
                                 and coalesce(u.admin_tier, 'super') in ('committee', 'moderator')) scoped,
                    (u.role = 'admin' and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
                                 and coalesce(u.admin_tier, 'super') in ('super', 'captain')) fullv
               from (values (kA, 'kA'), (kB, 'kB'), (sA, 'sA'), (sA2, 'sA2'), (sup, 'sup'), (cap, 'cap'), (res, 'res'), (tan, 'tan'), (kSusp, 'kSusp'), (sRet, 'sRet')) x(id, nm)
               join public.users u on u.id = x.id loop
      -- reports
      select count(*) into n_exp from public.reports r where r.tracking_id like 'RULE-%' and r.deleted_at is null
         and (r.resident_id = p.id or p.fullv or (p.scoped and coalesce(public._user_sees_case(p.id, r.id, r.category, r.handler_id), false))
              or exists (select 1 from public.dispatches d where d.report_id = r.id and d.tanod_id = p.id));
      perform set_config('request.jwt.claim.sub', p.id::text, true);
      execute 'set local role authenticated';
      select count(*) into n_rls from public.reports where tracking_id like 'RULE-%';
      execute 'reset role';
      if n_rls <> n_exp then bad := bad || format(' %s reports %s<>%s;', p.nm, n_rls, n_exp); end if;
      -- the rows hanging off a case (admin side of each policy: the case rule, deleted cases included, as admin_sees_report)
      foreach t in array array['status_logs', 'report_concerns', 'case_handler_log', 'dispatches'] loop
        execute format('select count(*) from public.%I x join public.reports r on r.id = x.report_id where r.tracking_id like ''RULE-%%''
                          and ($2 or ($3 and coalesce(public._user_sees_case($1, r.id, r.category, r.handler_id), false))
                               or (%s))', t,
                       case t when 'status_logs' then 'r.resident_id = $1 or exists (select 1 from public.dispatches d where d.report_id = r.id and d.tanod_id = $1)'
                              when 'dispatches' then 'x.tanod_id = $1' when 'report_concerns' then 'r.resident_id = $1' else 'false' end)
          into n_exp using p.id, p.fullv, p.scoped;
        execute 'set local role authenticated';
        execute format('select count(*) from public.%I x where x.report_id = any (%L::uuid[])', t,
                       array[c_open, c_com, c_away, c_wait, c_hand, c_asg, c_took, c_decl, c_conc, c_del, c_sens, c_tan]) into n_rls;
        execute 'reset role';
        if n_rls <> n_exp then bad := bad || format(' %s %s %s<>%s;', p.nm, t, n_rls, n_exp); end if;
      end loop;
      -- their own notices: a Kagawad or staff member reads a notice of a case only while they see the case
      select count(*) into n_exp from public.notifications x join public.reports r on r.id = x.report_id
       where r.tracking_id like 'RULE-%' and x.user_id = p.id and (not p.scoped or coalesce(public._user_sees_case(p.id, r.id, r.category, r.handler_id), false));
      execute 'set local role authenticated';
      select count(*) into n_rls from public.notifications x where x.message = 'rule';
      execute 'reset role';
      if n_rls <> n_exp then bad := bad || format(' %s notifications %s<>%s;', p.nm, n_rls, n_exp); end if;
    end loop;
    if bad <> '' then raise exception 'drift from the rule:%', bad; end if;
    v_log := v_log || E'\n' || 'ok  for 10 people (every rung, a suspended Kagawad, a retired staff member) the cases, logs, concerns, handler log, dispatches and notices read are exactly the 0175 rule';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL rule: ' || sqlerrm; end;

  -- 2. named cases, so a wrong oracle cannot hide a mistake
  begin
    perform set_config('request.jwt.claim.sub', kA::text, true);
    execute 'set local role authenticated';
    select string_agg(tracking_id, ',' order by tracking_id) into s from public.reports where tracking_id like 'RULE-%';
    if s is distinct from 'RULE-01,RULE-02,RULE-04,RULE-05,RULE-09,RULE-11' then raise exception 'Kagawad A reads %', s; end if;
    perform set_config('request.jwt.claim.sub', sA::text, true);
    select string_agg(tracking_id, ',' order by tracking_id) into s from public.reports where tracking_id like 'RULE-%';
    if s is distinct from 'RULE-04,RULE-06,RULE-07' then raise exception 'staff A reads %', s; end if;
    perform set_config('request.jwt.claim.sub', kB::text, true);
    select string_agg(tracking_id, ',' order by tracking_id) into s from public.reports where tracking_id like 'RULE-%';
    if s is distinct from 'RULE-03,RULE-05,RULE-06,RULE-07,RULE-08,RULE-09,RULE-12' then raise exception 'Kagawad B reads %', s; end if;
    perform set_config('request.jwt.claim.sub', kSusp::text, true);
    if exists (select 1 from public.reports where tracking_id like 'RULE-%') then raise exception 'a suspended Kagawad reads cases'; end if;
    perform set_config('request.jwt.claim.sub', sRet::text, true);
    if exists (select 1 from public.reports where tracking_id like 'RULE-%') then raise exception 'a retired staff member reads cases'; end if;
    perform set_config('request.jwt.claim.sub', tan::text, true);
    select string_agg(tracking_id, ',' order by tracking_id) into s from public.reports where tracking_id like 'RULE-%';
    if s is distinct from 'RULE-12' then raise exception 'the tanod reads %', s; end if;
    perform set_config('request.jwt.claim.sub', sup::text, true);
    if (select count(*) from public.reports where tracking_id like 'RULE-%') <> 11 then raise exception 'the super admin does not read every live case'; end if;
    perform set_config('request.jwt.claim.sub', kA::text, true);
    if (select count(*) from public.status_logs where report_id = c_del) <> 0 then raise exception 'Kagawad A still reads the log of a deleted case (0191: hidden)'; end if;
    if not exists (select 1 from public.users where id = res2) then raise exception 'Kagawad A cannot read the reporter of a case they handle'; end if;
    perform set_config('request.jwt.claim.sub', sA2::text, true);
    if exists (select 1 from public.users where id = res) then raise exception 'staff A2 reads a resident they have no case of'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  named cases: a Kagawad reads no-committee cases of their categories, forwarded-in, handled and concern cases, never forwarded-away ones, nor waiting ones of someone else (their own waiting case, yes: 0191); the rows of a deleted case are hidden; staff only assigned, handled and accepted-before (not declined); suspended and retired read none';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL named: ' || sqlerrm; end;

  -- 3. nothing is remembered between statements: a revoked assignment and a forward away count from the very next statement
  begin
    perform set_config('request.jwt.claim.sub', sA::text, true);
    execute 'set local role authenticated';
    if not exists (select 1 from public.reports where id = c_asg) or not exists (select 1 from public.status_logs where report_id = c_asg) then raise exception 'staff A does not read the assigned case'; end if;
    execute 'reset role';
    set local session_replication_role = replica;
    update public.reports set assigned_to = null, assigned_by = null where id = c_asg;
    update public.reports set committee = cb where id = c_open;
    set local session_replication_role = origin;
    execute 'set local role authenticated';
    if exists (select 1 from public.reports where id = c_asg) or exists (select 1 from public.status_logs where report_id = c_asg)
       or exists (select 1 from public.notifications where report_id = c_asg) then raise exception 'staff A still reads the case after the assignment was taken back'; end if;
    perform set_config('request.jwt.claim.sub', kA::text, true);
    if exists (select 1 from public.reports where id = c_open) or exists (select 1 from public.status_logs where report_id = c_open) then raise exception 'Kagawad A still reads a case forwarded away'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a taken-back assignment and a forward away count from the next statement (the case and its rows drop off at once)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL immediate: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
