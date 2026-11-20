-- notice_report_id (draft). Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.
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
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.request_reopen(v_case, 'Bumalik ang ingay');
    reset role;
    if exists (select 1 from public.notifications where message like 'Reopen requested%' and report_id is null) then raise exception 'a reopen notice has no report_id'; end if;
    v_log := v_log || E'\n' || 'ok  the notice carries the case (Review link): every notice about the reopen request has a report_id';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL the notice carries the case (Review link): every notice about the reopen request has a report_id: ' || sqlerrm; end;

  begin
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = v_case and message like 'Reopen requested%') then raise exception 'the Kagawad was not told'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and report_id = v_case and message like 'Reopen requested%') then raise exception 'the super admin was not told'; end if;
    v_log := v_log || E'\n' || 'ok  the Kagawad of the case''s committee and the super admin are told';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL the Kagawad of the case''s committee and the super admin are told: ' || sqlerrm; end;

  begin
    if exists (select 1 from public.notifications where user_id in (v_kenv, v_stf) and message like 'Reopen requested%') then raise exception 'an administrator who cannot open the case was told'; end if;
    v_log := v_log || E'\n' || 'ok  nobody who cannot open the case is told (other committee''s Kagawad, staff nobody assigned)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL nobody who cannot open the case is told (other committee''s Kagawad, staff nobody assigned): ' || sqlerrm; end;

  begin
    set local session_replication_role = replica; update public.reports set status = 'rejected' where id = v_case; set local session_replication_role = origin;
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.request_appeal(v_case, 'Hindi po ito tama');
    reset role;
    if exists (select 1 from public.notifications where user_id in (v_kenv, v_stf) and message like 'Appeal requested%') then raise exception 'an appeal notice reached an administrator who cannot open the case'; end if;
    if exists (select 1 from public.notifications where message like 'Appeal requested%' and report_id is null) then raise exception 'an appeal notice has no report_id'; end if;
    v_log := v_log || E'\n' || 'ok  an appeal request is scoped the same way';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL an appeal request is scoped the same way: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
