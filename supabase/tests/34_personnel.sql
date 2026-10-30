-- 34_personnel.sql: tanods in committees and the punch card (0153). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; n integer; s text; j jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999931', 'Pers, Super', 'resident'), (v_kpo, '+639999999932', 'Pers, Peace', 'resident'),
                 (v_kenv, '+639999999933', 'Pers, Env', 'resident'), (v_stf, '+639999999934', 'Pers, Staff', 'resident'),
                 (v_t1, '+639999999935', 'Pers, Tanod Uno', 'tanod'), (v_t2, '+639999999936', 'Pers, Tanod Dos', 'tanod'),
                 (v_res, '+639999999937', 'Pers, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_t1, v_t2, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', 14.51944, 121.01219) returning id into r1;
  v_log := 'setup ok';

  -- 1. a Kagawad proposes a tanod for their committee; the super admins are told and approve; only that committee sees the tanod
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    s := public.propose_tanod_committee(v_t1, 'peace_order', 'Lead sa gabi', null);
    if s <> 'proposed' then raise exception 'a Kagawad''s proposal was %', s; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and subject_user_id = v_t1 and kind::text = 'tanod_committee') then raise exception 'super admins not told'; end if;
    begin perform public.propose_tanod_committee(v_t2, 'environment', null, null); raise exception 'proposed for another committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.propose_tanod_committee(v_t2, 'peace_order', null, null); raise exception 'staff proposed';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.decide_tanod_committee(v_t1, 'peace_order', true, null); raise exception 'a Kagawad approved their own proposal';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.decide_tanod_committee(v_t1, 'peace_order', true, null);
    if (select status from public.tanod_committees where tanod_id = v_t1 and committee = 'peace_order') <> 'approved' then raise exception 'not approved'; end if;
    if not exists (select 1 from public.notifications where user_id = v_kpo and subject_user_id = v_t1 and message like '%approved%') then raise exception 'Kagawad not told'; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    select count(*) into n from public.account_directory('tanod') where id in (v_t1, v_t2);
    if n <> 1 then raise exception 'the Kagawad sees % of the two tanods', n; end if;
    if exists (select 1 from public.account_directory('resident')) then raise exception 'a Kagawad lists residents'; end if;
    if not exists (select 1 from public.tanod_pick_list() where id = v_t2) then raise exception 'the pick list misses a tanod'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if exists (select 1 from public.account_directory('tanod') where id in (v_t1, v_t2)) then raise exception 'another committee sees the tanod'; end if;
    if exists (select 1 from public.tanod_committees where tanod_id = v_t1) then raise exception 'another committee reads the role'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a Kagawad proposes a tanod for their own committee (not another; staff cannot), the super admins approve and the Kagawad is told; only that committee sees the tanod and its role, and a Kagawad lists no residents';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL propose: ' || sqlerrm; end;

  -- 2. a super admin assigns at once or denies a proposal; a Kagawad takes a tanod out of their committee; every step is logged
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    s := public.propose_tanod_committee(v_t1, 'environment', null, null);
    if s <> 'approved' then raise exception 'a super admin''s assignment was %', s; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.propose_tanod_committee(v_t2, 'peace_order', null, 'Taga-Purok 2');
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.decide_tanod_committee(v_t2, 'peace_order', false, 'Nasa ibang shift');
    if exists (select 1 from public.tanod_committees where tanod_id = v_t2) then raise exception 'a denied proposal stayed'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.remove_tanod_committee(v_t1, 'peace_order', null); raise exception 'another committee took the tanod out';
    exception when insufficient_privilege then null; end;
    perform public.remove_tanod_committee(v_t1, 'environment', 'Hindi na kailangan');
    select count(*) into n from public.tanod_committee_log where tanod_id in (v_t1, v_t2);
    if n <> 6 then raise exception '% log rows, expected 6', n; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin insert into public.tanod_committees (tanod_id, committee, status) values (v_t2, 'peace_order', 'approved'); raise exception 'written by hand';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a super admin assigns at once or denies a proposal; a Kagawad takes a tanod out of their own committee only; every step is in the log, and nobody writes the table by hand';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL decide: ' || sqlerrm; end;

  -- 3. a tanod on a case: other committees see that committee's pill, never the case
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.propose_tanod_committee(v_t2, 'environment', null, null);
    insert into public.dispatches (report_id, tanod_id, assigned_by, state) values (r1, v_t2, v_sup, 'accepted');
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    select busy_committee into s from public.personnel_committees() where tanod_id = v_t2;
    if s is distinct from 'peace_order' then raise exception 'the busy pill reads %', coalesce(s, 'nothing'); end if;
    if exists (select 1 from public.reports where id = r1) then raise exception 'another committee reads the case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a tanod on a case shows that case''s committee to the tanod''s other committees, who still cannot read the case';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL busy: ' || sqlerrm; end;

  -- 4. the punch card: sign-in and sign-out, and the cases touched; a Kagawad sees their staff's, nobody else's
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    perform public.punch('in');
    perform public.punch('in');
    insert into public.case_handler_log (report_id, admin_id, action) values (r1, v_stf, 'take');
    perform public.punch('out');
    if (select count(*) from public.admin_punches where user_id = v_stf) <> 2 then raise exception 'a repeat sign-in was punched twice'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.punch('in');
    if exists (select 1 from public.admin_punches where user_id = v_sup) then raise exception 'a super admin was punched'; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    j := public.punch_cards(7, v_stf);
    if jsonb_array_length(j) <> 1 or (j -> 0 -> 'days' -> 0 ->> 'touched')::int <> 1 or j -> 0 -> 'days' -> 0 ->> 'first_in' is null then
      raise exception 'the Kagawad''s view of the card: %', left(j::text, 200); end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if jsonb_array_length(public.punch_cards(7, v_stf)) <> 0 or exists (select 1 from public.admin_punches where user_id = v_stf) then raise exception 'another committee sees the card'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if jsonb_array_length(public.punch_cards(7, v_kpo)) <> 0 then raise exception 'staff see their Kagawad''s card'; end if;
    begin insert into public.admin_punches (user_id, kind) values (v_stf, 'in'); raise exception 'punched by hand';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  the punch card keeps a Kagawad''s and staff''s sign-ins and sign-outs (a repeat within a minute once; nothing for a super admin) and the cases touched; a Kagawad sees their staff''s card, another committee and staff do not, and nobody punches by hand';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL punch: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
