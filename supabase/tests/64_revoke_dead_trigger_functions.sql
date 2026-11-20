-- revoke_dead_trigger_functions (draft). Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.
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
    if has_function_privilege('anon', '_ask_if_fixed()', 'execute') or has_function_privilege('authenticated', '_ask_if_fixed()', 'execute') then raise exception '_ask_if_fixed is still executable by the API'; end if;
    if has_function_privilege('anon', '_case_guard_report()', 'execute') or has_function_privilege('authenticated', '_case_guard_report()', 'execute') then raise exception '_case_guard_report is still executable by the API'; end if;
    if has_function_privilege('anon', '_case_guard_row()', 'execute') or has_function_privilege('authenticated', '_case_guard_row()', 'execute') then raise exception '_case_guard_row is still executable by the API'; end if;
    if has_function_privilege('anon', '_catalogue_change_note()', 'execute') or has_function_privilege('authenticated', '_catalogue_change_note()', 'execute') then raise exception '_catalogue_change_note is still executable by the API'; end if;
    if has_function_privilege('anon', '_close_concerns()', 'execute') or has_function_privilege('authenticated', '_close_concerns()', 'execute') then raise exception '_close_concerns is still executable by the API'; end if;
    if has_function_privilege('anon', '_committee_colour_check()', 'execute') or has_function_privilege('authenticated', '_committee_colour_check()', 'execute') then raise exception '_committee_colour_check is still executable by the API'; end if;
    if has_function_privilege('anon', '_concern_snapshot()', 'execute') or has_function_privilege('authenticated', '_concern_snapshot()', 'execute') then raise exception '_concern_snapshot is still executable by the API'; end if;
    if has_function_privilege('anon', '_dispatch_cap_guard()', 'execute') or has_function_privilege('authenticated', '_dispatch_cap_guard()', 'execute') then raise exception '_dispatch_cap_guard is still executable by the API'; end if;
    if has_function_privilege('anon', '_flag_sensitive()', 'execute') or has_function_privilege('authenticated', '_flag_sensitive()', 'execute') then raise exception '_flag_sensitive is still executable by the API'; end if;
    if has_function_privilege('anon', '_guard_case_committee()', 'execute') or has_function_privilege('authenticated', '_guard_case_committee()', 'execute') then raise exception '_guard_case_committee is still executable by the API'; end if;
    if has_function_privilege('anon', '_guard_official_fields()', 'execute') or has_function_privilege('authenticated', '_guard_official_fields()', 'execute') then raise exception '_guard_official_fields is still executable by the API'; end if;
    if has_function_privilege('anon', '_inbox_alert()', 'execute') or has_function_privilege('authenticated', '_inbox_alert()', 'execute') then raise exception '_inbox_alert is still executable by the API'; end if;
    if has_function_privilege('anon', '_main_concern()', 'execute') or has_function_privilege('authenticated', '_main_concern()', 'execute') then raise exception '_main_concern is still executable by the API'; end if;
    if has_function_privilege('anon', '_status_log_no_repeat()', 'execute') or has_function_privilege('authenticated', '_status_log_no_repeat()', 'execute') then raise exception '_status_log_no_repeat is still executable by the API'; end if;
    if has_function_privilege('anon', '_super_colour_check()', 'execute') or has_function_privilege('authenticated', '_super_colour_check()', 'execute') then raise exception '_super_colour_check is still executable by the API'; end if;
    if has_function_privilege('anon', '_triage_rules_version()', 'execute') or has_function_privilege('authenticated', '_triage_rules_version()', 'execute') then raise exception '_triage_rules_version is still executable by the API'; end if;
    if has_function_privilege('anon', 'assign_tracking_id()', 'execute') or has_function_privilege('authenticated', 'assign_tracking_id()', 'execute') then raise exception 'assign_tracking_id is still executable by the API'; end if;
    if has_function_privilege('anon', 'chain_account_audit()', 'execute') or has_function_privilege('authenticated', 'chain_account_audit()', 'execute') then raise exception 'chain_account_audit is still executable by the API'; end if;
    if has_function_privilege('anon', 'chain_status_log()', 'execute') or has_function_privilege('authenticated', 'chain_status_log()', 'execute') then raise exception 'chain_status_log is still executable by the API'; end if;
    if has_function_privilege('anon', 'confirm_synthetic_auth_email()', 'execute') or has_function_privilege('authenticated', 'confirm_synthetic_auth_email()', 'execute') then raise exception 'confirm_synthetic_auth_email is still executable by the API'; end if;
    if has_function_privilege('anon', 'dispatch_on_file()', 'execute') or has_function_privilege('authenticated', 'dispatch_on_file()', 'execute') then raise exception 'dispatch_on_file is still executable by the API'; end if;
    if has_function_privilege('anon', 'enforce_daily_report_limit()', 'execute') or has_function_privilege('authenticated', 'enforce_daily_report_limit()', 'execute') then raise exception 'enforce_daily_report_limit is still executable by the API'; end if;
    if has_function_privilege('anon', 'enforce_media_cap()', 'execute') or has_function_privilege('authenticated', 'enforce_media_cap()', 'execute') then raise exception 'enforce_media_cap is still executable by the API'; end if;
    if has_function_privilege('anon', 'guard_last_admin()', 'execute') or has_function_privilege('authenticated', 'guard_last_admin()', 'execute') then raise exception 'guard_last_admin is still executable by the API'; end if;
    if has_function_privilege('anon', 'guard_privileged_user_fields()', 'execute') or has_function_privilege('authenticated', 'guard_privileged_user_fields()', 'execute') then raise exception 'guard_privileged_user_fields is still executable by the API'; end if;
    if has_function_privilege('anon', 'handle_new_auth_user()', 'execute') or has_function_privilege('authenticated', 'handle_new_auth_user()', 'execute') then raise exception 'handle_new_auth_user is still executable by the API'; end if;
    if has_function_privilege('anon', 'refuse_audit_write()', 'execute') or has_function_privilege('authenticated', 'refuse_audit_write()', 'execute') then raise exception 'refuse_audit_write is still executable by the API'; end if;
    if has_function_privilege('anon', 'reset_verification_overdue_mark()', 'execute') or has_function_privilege('authenticated', 'reset_verification_overdue_mark()', 'execute') then raise exception 'reset_verification_overdue_mark is still executable by the API'; end if;
    if has_function_privilege('anon', 'set_accept_deadline()', 'execute') or has_function_privilege('authenticated', 'set_accept_deadline()', 'execute') then raise exception 'set_accept_deadline is still executable by the API'; end if;
    if has_function_privilege('anon', 'set_report_deadline()', 'execute') or has_function_privilege('authenticated', 'set_report_deadline()', 'execute') then raise exception 'set_report_deadline is still executable by the API'; end if;
    if has_function_privilege('anon', 'set_verification_deadline()', 'execute') or has_function_privilege('authenticated', 'set_verification_deadline()', 'execute') then raise exception 'set_verification_deadline is still executable by the API'; end if;
    if has_function_privilege('anon', 'sync_dispatchable()', 'execute') or has_function_privilege('authenticated', 'sync_dispatchable()', 'execute') then raise exception 'sync_dispatchable is still executable by the API'; end if;
    if has_function_privilege('anon', 'touch_settings()', 'execute') or has_function_privilege('authenticated', 'touch_settings()', 'execute') then raise exception 'touch_settings is still executable by the API'; end if;
    if has_function_privilege('anon', 'touch_updated_at()', 'execute') or has_function_privilege('authenticated', 'touch_updated_at()', 'execute') then raise exception 'touch_updated_at is still executable by the API'; end if;
    v_log := v_log || E'\n' || 'ok  no trigger function is executable by the API any more (34 functions)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL no trigger function is executable by the API any more (34 functions): ' || sqlerrm; end;

  begin
    perform '_ask_if_fixed()'::regprocedure;
    perform '_case_guard_report()'::regprocedure;
    perform '_case_guard_row()'::regprocedure;
    perform '_catalogue_change_note()'::regprocedure;
    perform '_close_concerns()'::regprocedure;
    perform '_committee_colour_check()'::regprocedure;
    perform '_concern_snapshot()'::regprocedure;
    perform '_dispatch_cap_guard()'::regprocedure;
    perform '_flag_sensitive()'::regprocedure;
    perform '_guard_case_committee()'::regprocedure;
    perform '_guard_official_fields()'::regprocedure;
    perform '_inbox_alert()'::regprocedure;
    perform '_main_concern()'::regprocedure;
    perform '_status_log_no_repeat()'::regprocedure;
    perform '_super_colour_check()'::regprocedure;
    perform '_triage_rules_version()'::regprocedure;
    perform 'assign_tracking_id()'::regprocedure;
    perform 'chain_account_audit()'::regprocedure;
    perform 'chain_status_log()'::regprocedure;
    perform 'confirm_synthetic_auth_email()'::regprocedure;
    perform 'dispatch_on_file()'::regprocedure;
    perform 'enforce_daily_report_limit()'::regprocedure;
    perform 'enforce_media_cap()'::regprocedure;
    perform 'guard_last_admin()'::regprocedure;
    perform 'guard_privileged_user_fields()'::regprocedure;
    perform 'handle_new_auth_user()'::regprocedure;
    perform 'refuse_audit_write()'::regprocedure;
    perform 'reset_verification_overdue_mark()'::regprocedure;
    perform 'set_accept_deadline()'::regprocedure;
    perform 'set_report_deadline()'::regprocedure;
    perform 'set_verification_deadline()'::regprocedure;
    perform 'sync_dispatchable()'::regprocedure;
    perform 'touch_settings()'::regprocedure;
    perform 'touch_updated_at()'::regprocedure;
    v_log := v_log || E'\n' || 'ok  they still exist (a revoke, not a drop; nothing is lost)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL they still exist (a revoke, not a drop; nothing is lost): ' || sqlerrm; end;

  begin
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Revoke probe', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);
    reset role; if not exists (select 1 from public.reports where subject = 'Revoke probe') then raise exception 'filing failed after the revoke'; end if;
    v_log := v_log || E'\n' || 'ok  and the triggers still fire for signed-in people: a resident files a report, an update touches settings';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL and the triggers still fire for signed-in people: a resident files a report, an update touches settings: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
