-- Synthetic data for the sweep (THROWAWAY database only). Tops the database up to :n_cases cases and :n_res residents, with the
-- whole role ladder present. Idempotent: run at 1x (82 cases, 23 users), again at 250x (20000 cases). Names are invented.
-- usage: psql -v n_cases=20000 -v n_res=2000 -f seed.sql
\set ON_ERROR_STOP on
select set_config('sweep.n_cases', :'n_cases', false), set_config('sweep.n_res', :'n_res', false) \gset
do $seed$
declare
  n_cases int := current_setting('sweep.n_cases')::int;
  n_res   int := current_setting('sweep.n_res')::int;
  have_r  int; have_c int; i int;
  coms text[] := array(select key from public.committees where active order by sort);
  cats text[] := array['street_obstruction','public_safety_infrastructure','environmental_waste_hazard','animal_welfare','traffic_violation','barangay_service','peace_order_nuisance'];
  sts  text[] := array['pending_review','validated','in_progress','resolved','closed','rejected','in_progress','resolved','closed','pending_review'];
  ids uuid[]; res uuid[]; tan uuid[]; stf uuid[]; kag uuid[]; sup uuid;
begin
  -- 1. the ladder: 2 super, 1 captain, a Kagawad and 2 staff per committee, 12 tanods
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
           'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
           'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (select '+63900000' || lpad(g::text, 4, '0') as mob, 'Sweep, Rung ' || g as nm from generate_series(1, 40) g) x
   where not exists (select 1 from public.users u where u.full_name = x.nm);
  update public.users set verification_status = 'verified', verified_at = now() where full_name like 'Sweep, Rung %' and verification_status <> 'verified';
  update public.users set role = 'admin', admin_tier = 'super' where full_name in ('Sweep, Rung 1', 'Sweep, Rung 2');
  update public.users set role = 'admin', admin_tier = 'captain' where full_name = 'Sweep, Rung 3';
  for i in 1 .. coalesce(array_length(coms, 1), 0) loop
    update public.users set role = 'admin', admin_tier = 'committee', committee = coms[i] where full_name = 'Sweep, Rung ' || (3 + i);
    update public.users set role = 'admin', admin_tier = 'moderator', committee = coms[i] where full_name in ('Sweep, Rung ' || (10 + 2 * i), 'Sweep, Rung ' || (11 + 2 * i));
  end loop;
  update public.users set role = 'tanod', duty_status = 'on_duty', is_dispatchable = true where full_name in (select 'Sweep, Rung ' || g from generate_series(25, 36) g);
  -- 2. residents
  select count(*) into have_r from public.users where full_name like 'Sweep, Resident %';
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', public.auth_email_for('+63901' || lpad(g::text, 7, '0')),
         jsonb_build_object('full_name', 'Sweep, Resident ' || g, 'mobile_number', '+63901' || lpad(g::text, 7, '0'), 'role', 'resident', 'id_type', 'barangay_id',
           'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
           'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from generate_series(have_r + 1, n_res) g;
  update public.users set verification_status = 'verified', verified_at = now() where full_name like 'Sweep, Resident %' and verification_status <> 'verified';
  select array_agg(id) into res from public.users where full_name like 'Sweep, Resident %';
  select array_agg(id) into tan from public.users where role = 'tanod' and full_name like 'Sweep%';
  select array_agg(id) into stf from public.users where admin_tier = 'moderator' and full_name like 'Sweep%';
  select array_agg(id) into kag from public.users where admin_tier = 'committee' and full_name like 'Sweep%';
  -- 3. cases. Bulk history is loaded with the triage trigger OFF (as supabase/tests/perf does; scoring 20,000 rows one by one is O(n^2) on nearby
  -- reports); the engine's own filing cost is measured separately by smart.py, and the newest open cases are triaged below.
  alter table public.reports disable trigger reports_smart_triage;
  select count(*) into have_c from public.reports where subject like 'Sweep case %';
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, created_at, is_public)
  select res[1 + (g % array_length(res, 1))], cats[1 + (g % 7)]::public.complaint_category, 'Sweep case ' || g,
         (array['May baha sa kanto at tulong po','Sunog sa bahay malapit sa palengke','Maingay na videoke hanggang madaling araw','Tambak na basura sa tabi ng kanal','Walang ilaw ang poste sa kanto'])[1 + g % 5],
         14.5165 + ((g * 37) % 100 - 50) / 20000.0, 121.0162 + ((g * 53) % 100 - 50) / 20000.0,
         sts[1 + g % 10]::public.report_status, now() - make_interval(hours => (g * 7919) % 17500), (g % 4 = 0)
    from generate_series(have_c + 1, n_cases) g;
  alter table public.reports enable trigger reports_smart_triage;
  perform public.smart_triage(id) from (select id from public.reports where subject like 'Sweep case %' and status in ('pending_review','validated','in_progress')
     and not exists (select 1 from public.report_triage t where t.report_id = id) order by created_at desc limit 3000) x;
  -- handlers / assignments / dispatches / logs / notifications for the new cases (superuser writes: nothing here is a user path)
  update public.reports r set handler_id = kag[1 + (abs(hashtext(r.id::text)) % array_length(kag, 1))], handled_since = r.created_at
   where r.subject like 'Sweep case %' and r.handler_id is null and r.status in ('validated','in_progress','resolved','closed') and array_length(kag, 1) > 0;
  update public.reports r set assigned_to = stf[1 + (abs(hashtext(r.id::text)) % array_length(stf, 1))], assigned_by = r.handler_id, assigned_at = r.created_at
   where r.subject like 'Sweep case %' and r.assigned_to is null and r.handler_id is not null and abs(hashtext(r.id::text)) % 3 = 0 and array_length(stf, 1) > 0;
  set local session_replication_role = replica;   -- the 5-open-dispatch cap is a user rule; the seed spreads work thin
  insert into public.dispatches (report_id, tanod_id, assigned_by, state, accepted_at, is_primary)
  select r.id, tan[1 + (abs(hashtext(r.id::text)) % array_length(tan, 1))], coalesce(r.handler_id, kag[1]), 'accepted', r.created_at, true
    from public.reports r
   where r.subject like 'Sweep case %' and r.status in ('in_progress','resolved','closed') and array_length(tan, 1) > 0
     and not exists (select 1 from public.dispatches d where d.report_id = r.id);
  set local session_replication_role = origin;
  insert into public.status_logs (report_id, changed_by, new_status, remark, is_system, created_at)
  select r.id, r.resident_id, r.status, 'sweep seed ' || k, true, r.created_at + make_interval(mins => k)
    from public.reports r cross join generate_series(1, 3) k
   where r.subject like 'Sweep case %' and not exists (select 1 from public.status_logs l where l.report_id = r.id and l.remark like 'sweep seed%');
  insert into public.notifications (user_id, report_id, kind, message, is_read, created_at)
  select r.resident_id, r.id, 'status_change', 'Sweep notice ' || k, k = 1, r.created_at + make_interval(mins => k)
    from public.reports r cross join generate_series(1, 2) k
   where r.subject like 'Sweep case %' and not exists (select 1 from public.notifications n where n.report_id = r.id and n.message like 'Sweep notice%');
end
$seed$;
analyze;
select (select count(*) from public.reports) as reports, (select count(*) from public.users) as users, (select count(*) from public.status_logs) as status_logs,
       (select count(*) from public.notifications) as notifications, (select count(*) from public.report_triage) as triage;
