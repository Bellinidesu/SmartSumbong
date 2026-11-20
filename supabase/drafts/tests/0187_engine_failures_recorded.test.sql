-- engine_failures_recorded (draft). Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.
do $sweep$
declare
  v_log text := 'setup ok';
  v_res uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_case uuid; n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999901', 'Draft, Resident'), (v_sup, '+639999999902', 'Draft, Super'), (v_kpo, '+639999999903', 'Draft, Kagawad Peace'),
                 (v_kenv, '+639999999904', 'Draft, Kagawad Env'), (v_stf, '+639999999905', 'Draft, Staff Peace')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_sup, v_kpo, v_kenv, v_stf);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'super', committee = null where role = 'admin' and id not in (v_sup, v_kpo, v_kenv, v_stf) and admin_tier in ('committee', 'moderator');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', 14.51944, 121.01219) returning id into v_case;
  set local session_replication_role = replica;
  update public.reports set status = 'resolved', resolved_at = now(), committee = 'peace_order', handler_id = v_kpo, handled_since = now() where id = v_case;
  set local session_replication_role = origin;

  begin
    create or replace function public.smart_triage(p_report uuid) returns report_triage language plpgsql as $f$ begin raise exception 'injected: engine down'; end $f$;
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Probe file', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);
    reset role;
    if not exists (select 1 from public.reports where subject = 'Probe file') then raise exception 'the report was not filed'; end if;
    v_log := v_log || E'\n' || 'ok  filing still succeeds when SMART triage fails';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL filing still succeeds when SMART triage fails: ' || sqlerrm; end;

  begin
    if not exists (select 1 from public.smart_events where kind = 'engine_error' and report_id = (select id from public.reports where subject = 'Probe file')) then raise exception 'no engine_error row was recorded'; end if;
    v_log := v_log || E'\n' || 'ok  and the failure is recorded in smart_events (kind engine_error), where an administrator can see it';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL and the failure is recorded in smart_events (kind engine_error), where an administrator can see it: ' || sqlerrm; end;

  begin
    alter table public.smart_events rename to smart_events_x;
    perform public._smart_event('probe', null, 'probe');
    alter table public.smart_events_x rename to smart_events;
    v_log := v_log || E'\n' || 'ok  a log line that cannot be written no longer aborts the action it describes';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL a log line that cannot be written no longer aborts the action it describes: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
