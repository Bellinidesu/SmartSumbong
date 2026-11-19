-- 58_smart_queue_scope.sql: the queue lists the cases a person may open, for every rung (0180, backend sweep). A case forwarded away
-- leaves the old committee's queue and joins the new one's. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid();
  r1 uuid; tid text;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999951', 'Queue, Super'), (v_kpo, '+639999999952', 'Queue, Peace'), (v_kenv, '+639999999953', 'Queue, Env'),
                 (v_ana, '+639999999954', 'Queue, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_ana);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set admin_tier = 'super', committee = null where role = 'admin' and committee = 'health_sanitation' and admin_tier in ('committee', 'moderator');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'environmental_waste_hazard', 'Basura', 'Tambak na basura sa tabi ng kanal, ilang linggo na.', lat, lng) returning id, tracking_id into r1, tid;

  -- 1. before forwarding: the Environment Kagawad and the super admin list it, the Peace and Order Kagawad does not
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if not exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'the owning Kagawad''s queue misses the case'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'another committee''s Kagawad lists the case'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if not exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'the super admin''s queue misses the case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a case is in its own committee''s queue and the super admin''s, and in no other committee''s';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL before forwarding: ' || sqlerrm; end;

  -- 2. forwarded to Peace and Order: gone from the Environment queue, in the Peace and Order queue
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    perform public.take_case(r1);
    perform public.forward_case(r1, 'peace_order', 'wrong committee', null);
    if exists (select 1 from public.reports where id = r1) then raise exception 'the old committee still reads the case'; end if;
    if exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'the old committee''s queue still lists a case it can no longer open'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if not exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'the receiving committee''s queue does not list the forwarded case'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if not exists (select 1 from public.smart_queue(null, 500) q where q.report_id = r1) then raise exception 'the super admin''s queue lost the case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a forwarded case leaves the old committee''s queue and joins the receiving one''s';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL forwarded: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
