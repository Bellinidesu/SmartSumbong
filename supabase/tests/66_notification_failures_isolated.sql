-- notification_failures_isolated (draft). Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.
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
    create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid) returns boolean language plpgsql as $f$ begin raise exception 'injected: visibility rule down'; end $f$;
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.request_reopen(v_case, 'Bumalik ang ingay');
    reset role;
    if not exists (select 1 from public.status_logs where report_id = v_case and remark like 'Resident requested reopening%') then raise exception 'the request was not recorded'; end if;
    v_log := v_log || E'\n' || 'ok  a failing visibility rule inside the notification trigger no longer aborts a reopen request';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL a failing visibility rule inside the notification trigger no longer aborts a reopen request: ' || sqlerrm; end;

  begin
    if not exists (select 1 from public.smart_events where kind = 'notice_error') then raise exception 'no notice_error event was recorded'; end if;
    v_log := v_log || E'\n' || 'ok  and the failure is recorded as a notice_error event an administrator can read';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL and the failure is recorded as a notice_error event an administrator can read: ' || sqlerrm; end;

  begin
    insert into public.notifications (user_id, kind, message) values (gen_random_uuid(), 'status_change', 'for nobody');
    if exists (select 1 from public.notifications where message = 'for nobody') then raise exception 'a notice for a missing user was stored'; end if;
    v_log := v_log || E'\n' || 'ok  a notice for a person who no longer exists is dropped instead of aborting (foreign key)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL a notice for a person who no longer exists is dropped instead of aborting (foreign key): ' || sqlerrm; end;

  begin
    insert into public.notifications (user_id, report_id, kind, message) values (v_res, gen_random_uuid(), 'status_change', 'for a gone case');
    if exists (select 1 from public.notifications where message = 'for a gone case') then raise exception 'a notice for a missing case was stored'; end if;
    v_log := v_log || E'\n' || 'ok  a notice about a case that no longer exists is dropped instead of aborting (foreign key)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL a notice about a case that no longer exists is dropped instead of aborting (foreign key): ' || sqlerrm; end;

  begin
    create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat complaint_category, p_handler uuid)
     RETURNS boolean
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public'
    AS $function$
      select case
        -- 19 Nov 2026 (Rose): staff see a complaint only once their councilor (or a super admin) has assigned it to them
        when r.tier = 'moderator' then
             (p_handler is not null and p_handler = p_user)
          or (r.assigned_to is not null and r.assigned_to = p_user)
          or exists (select 1 from public.case_handler_log l
                      where l.report_id = p_report and l.admin_id = p_user and l.action in ('take', 'take_over', 'accept'))
        when r.awaiting_placement then false
        when r.committee is not null then
             coalesce((select u.committee = r.committee and u.role = 'admin' and not coalesce(u.is_suspended, false) from public.users u where u.id = p_user), false)
          or (p_handler is not null and p_handler = p_user)
        else coalesce(public._user_sees_category(p_user, p_cat), false)
          or (p_handler is not null and p_handler = p_user)
          or exists (select 1 from public.report_concerns rc where rc.report_id = p_report and public._user_sees_category(p_user, rc.category))
      end
        from (select x.committee, coalesce(x.awaiting_placement, false) as awaiting_placement, x.assigned_to,
                     (select u.admin_tier from public.users u where u.id = p_user and u.role = 'admin' and not coalesce(u.is_suspended, false)) as tier
                from (select 1) one left join public.reports x on x.id = p_report) r
    $function$;
    perform public._notify_admins('probe notice', null);
    insert into public.notifications (user_id, report_id, kind, message) values (v_kpo, v_case, 'status_change', 'scoped notice'), (v_kenv, v_case, 'status_change', 'scoped notice');
    if not exists (select 1 from public.notifications where user_id = v_kpo and message = 'scoped notice') then raise exception 'the committee Kagawad was not told'; end if;
    if exists (select 1 from public.notifications where user_id = v_kenv and message = 'scoped notice') then raise exception 'another committee was told'; end if;
    v_log := v_log || E'\n' || 'ok  with the rule working again the scope is unchanged: the Kagawad of the committee is told, an administrator of another committee is not';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL with the rule working again the scope is unchanged: the Kagawad of the committee is told, an administrator of another committee is not: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
