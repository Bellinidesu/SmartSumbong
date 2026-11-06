-- 46_roster_committee.sql: the dispatch list puts the case's committee's tanods first (0167). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; s text; first_id uuid; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999991', 'Roster, Super', 'resident'), (v_t1, '+639999999992', 'Roster, Committee Tanod', 'tanod'),
                 (v_t2, '+639999999993', 'Roster, Nearer Tanod', 'tanod'), (v_res, '+639999999994', 'Roster, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_t1, v_t2, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  -- both on duty and free; the one outside the committee is the nearer of the two
  update public.users set duty_status = 'on_duty', last_location_at = now(),
                          last_geom = st_setsrid(st_makepoint(lng + 0.004, lat), 4326)::geography where id = v_t1;
  update public.users set duty_status = 'on_duty', last_location_at = now(),
                          last_geom = st_setsrid(st_makepoint(lng + 0.0001, lat), 4326)::geography where id = v_t2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', lat, lng, 'validated') returning id into r1;
  update public.reports set committee = 'peace_order' where id = r1;
  perform set_config('request.jwt.claim.sub', v_sup::text, true);
  s := public.propose_tanod_committee(v_t1, 'peace_order', null, null);
  if s <> 'approved' then perform public.decide_tanod_committee(v_t1, 'peace_order', true, null); end if;
  v_log := 'setup ok';

  -- 1. among the tanods who can take it, the committee's come first, and each row says whether the tanod is the committee's
  begin
    select count(*) into n from public.tanod_roster(r1) t where t.tanod_id in (v_t1, v_t2) and t.assignable;
    if n <> 2 then raise exception 'both should be assignable, % are', n; end if;
    select t.tanod_id into first_id from public.tanod_roster(r1) t where t.tanod_id in (v_t1, v_t2) limit 1;
    if first_id <> v_t1 then raise exception 'the nearer tanod outside the committee came first'; end if;
    if not (select t.in_committee from public.tanod_roster(r1) t where t.tanod_id = v_t1) then raise exception 'the committee tanod is not marked'; end if;
    if (select t.in_committee from public.tanod_roster(r1) t where t.tanod_id = v_t2) then raise exception 'the other tanod is marked'; end if;
    v_log := v_log || E'\n' || 'ok  the committee''s tanods come first among those who can take the case, and are marked; the others are still listed';
  exception when others then v_log := v_log || E'\n' || 'FAIL roster: ' || sqlerrm; end;

  -- 2. a case with no committee yet: nobody is marked, and nearest still comes first
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    update public.reports set committee = null, awaiting_placement = true where id = r1;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if exists (select 1 from public.tanod_roster(r1) t where t.in_committee) then raise exception 'a tanod is marked on a case with no committee'; end if;
    select t.tanod_id into first_id from public.tanod_roster(r1) t where t.tanod_id in (v_t1, v_t2) limit 1;
    if first_id <> v_t2 then raise exception 'the nearest did not come first'; end if;
    v_log := v_log || E'\n' || 'ok  a case with no committee marks nobody and lists the nearest first';
  exception when others then v_log := v_log || E'\n' || 'FAIL no committee: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
