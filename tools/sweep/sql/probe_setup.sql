-- Fixtures for the dynamic probers (THROWAWAY database sweep_probe only). Run once; every probe then builds its own case inside a subtransaction
-- that is rolled back, so nothing here changes between probes.
create schema if not exists sweep;
create table if not exists sweep.actors (name text primary key, id uuid not null);
create table if not exists sweep.results (fn text, kind text, data jsonb);
create or replace function sweep.a(p text) returns uuid language sql stable as $$ select id from sweep.actors where name = p $$;

do $setup$
declare r record; v_id uuid;
begin
  for r in select * from (values ('res1','Probe, Resident One','+639770000001'),('res2','Probe, Resident Two','+639770000002'),('tan1','Probe, Tanod One','+639770000003'),
      ('tan2','Probe, Tanod Two','+639770000004'),('stf1','Probe, Staff Peace','+639770000005'),('stf2','Probe, Staff Env','+639770000006'),('kag1','Probe, Kagawad Peace','+639770000007'),
      ('kag2','Probe, Kagawad Env','+639770000008'),('cap','Probe, Captain','+639770000009'),('sup','Probe, Super','+639770000010')) x(name, full_name, mob)
  loop
    if exists (select 1 from sweep.actors where name = r.name) then continue; end if;
    v_id := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', public.auth_email_for(r.mob),
            jsonb_build_object('full_name', r.full_name, 'mobile_number', r.mob, 'role', 'resident', 'id_type', 'barangay_id',
              'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
              'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now());
    insert into sweep.actors values (r.name, v_id);
  end loop;
  update public.users set verification_status = 'verified', verified_at = now() where full_name like 'Probe, %';
  update public.users set role = 'tanod', duty_status = 'on_duty', is_dispatchable = true where id in (sweep.a('tan1'), sweep.a('tan2'));
  update public.users set role = 'admin', admin_tier = 'super' where id = sweep.a('sup');
  update public.users set role = 'admin', admin_tier = 'captain' where id = sweep.a('cap');
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = sweep.a('kag1');
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = sweep.a('kag2');
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = sweep.a('stf1');
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'environment' where id = sweep.a('stf2');
end $setup$;

-- one pristine case in a given state; variant 1 = handled by kag1 and assigned to stf1. Extras (requests) are always made so every function has a target.
drop function if exists sweep.mk_ctx(text, int);
create or replace function sweep.mk_ctx(p_state text, p_variant int, p_reqs boolean default true) returns jsonb language plpgsql as $$
declare r uuid; d uuid; e uuid; dr uuid; rt uuid; pr uuid; c uuid; st text := split_part(p_state, '+', 1); done boolean := p_state like '%+submitted';
begin
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (sweep.a('res1'), 'peace_order_nuisance', 'Probe case', 'Videoke hanggang hatinggabi sa kanto.', 14.51944, 121.01219) returning id into r;
  set local session_replication_role = replica;
  update public.reports set status = st::public.report_status, committee = 'peace_order',
         handler_id = case p_variant when 1 then sweep.a('kag1') when 2 then sweep.a('stf1') end, handled_since = case when p_variant > 0 then now() end,
         assigned_to = case when p_variant > 0 then sweep.a('stf1') end, assigned_by = case when p_variant > 0 then sweep.a('kag1') end,
         assigned_at = case when p_variant > 0 then now() end,
         resolution_submitted_at = case when done then now() end, resolved_at = case when st in ('resolved', 'closed') then now() end,
         closed_at = case when st = 'closed' then now() end
   where id = r;
  if st in ('in_progress', 'offline_investigation', 'resolved', 'closed') then
    insert into public.dispatches (report_id, tanod_id, assigned_by, state, accepted_at, is_primary)
    values (r, sweep.a('tan1'), sweep.a('kag1'), (case when st in ('resolved', 'closed') or done then 'resolved' else 'accepted' end)::public.dispatch_state, now(), true) returning id into d;
    if p_reqs then insert into public.escalation_requests (report_id, dispatch_id, requested_by, reason, status) values (r, d, sweep.a('tan1'), 'probe', 'pending') returning id into e; end if;
  end if;
  if p_reqs then
    insert into public.detail_requests (report_id, requested_by, message) values (r, sweep.a('kag1'), 'probe') returning id into dr;
    insert into public.retirement_requests (tanod_id, status) values (sweep.a('tan1'), 'pending') returning id into rt;
    insert into public.profile_requests (user_id, kind, new_full_name, reason, status) values (sweep.a('res1'), 'full_name', 'Probe, Renamed', 'probe', 'pending') returning id into pr;
  end if;
  select id into c from public.report_concerns where report_id = r limit 1;
  set local session_replication_role = origin;
  return jsonb_build_object('report', r, 'dispatch', d, 'esc', e, 'detail', dr, 'retire', rt, 'profile', pr, 'concern', c);
end $$;
