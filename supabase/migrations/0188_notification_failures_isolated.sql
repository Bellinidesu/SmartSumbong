-- 0188 (backend sweep 2, 20 Nov 2026): applied after Ace said "apply 0188"
-- 0188_notification_failures_isolated: a failing notification no longer aborts the press (review, dispatch, message, reopen/appeal...)
--
-- tools/sweep/inject.py (failure injection, 20 Nov): with the notification trigger made to raise, review_report, admin_dispatch, post_report_message and request_reopen all FAILED:
-- a notice (a side effect) aborted the real action. The notifications table has one trigger and 59 functions insert into it (59 directly, 3 helpers), so the one trigger is made best-effort
-- instead of wrapping each call site. Foreign-key and NOT NULL problems are repaired or the notice dropped; any other error records a 'notice_error' event and drops that notice (fail closed).
-- Function touched: public._notifications_scope() only. Functions protected by it (every writer of notifications): _ask_if_fixed, _inbox_alert, _look_share_notice, _notify_admins, _notify_committee_heads, _notify_tanod_committee, _reroute_ask, admin_barangay_update, admin_dispatch, admin_reroute_dispatch, admin_set_status, admin_update_user, answer_case_assignment, appeal_report, approve_escalation, approve_resolution, assign_case, auto_dispatch, confirm_fix, decide_profile_request, deny_escalation, dismiss_forward_flag, endorse_retirement, escalate_in_barangay, finalize_retirement, follow_up_report, hand_to_higher_official, post_dispatch_update, post_report_message, promote_to_admin, push_test, redispatch_report, refer_report, reject_resolution, request_additional_details, request_appeal, request_escalation, request_ocr_rescan, request_reopen, request_retirement, reroute_dispatch, return_from_official, review_report, run_admin_handover_expirations, set_account_suspension, set_concern_status, set_dispatch_step, set_resolution_target, smart_watch, step_down_as_admin, submit_additional_details, submit_field_report, sweep_awaiting_units, sweep_overdue_reports, sweep_overdue_verifications, sweep_reroute_questions, sweep_unaccepted_dispatches, take_over_case, verify_user_account
--
-- UNDO (plain language): restore _notifications_scope() from 0175/0185 (create or replace with the previous body: the scope rule without the sanitising and the exception block). Recorded notice_error events can be deleted.
-- Proof: supabase/drafts/tests/0188_notification_failures_isolated.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_notif_isolation.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

create or replace function public._notifications_scope()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_role text; v_tier text;
begin
  begin
    -- what would make the INSERT itself fail (foreign keys, NOT NULLs) is repaired or the notice dropped, so a press never aborts on a notice
    if new.user_id is null or not exists (select 1 from public.users where id = new.user_id) then return null; end if;       -- the person is gone
    if new.report_id is not null and not exists (select 1 from public.reports where id = new.report_id) then return null; end if;   -- the case is gone
    if new.subject_user_id is not null and not exists (select 1 from public.users where id = new.subject_user_id) then new.subject_user_id := null; end if;
    new.message := coalesce(nullif(new.message, ''), '(no text)');
    -- the scope rule (unchanged from 0175/0185)
    select role::text, coalesce(admin_tier, 'super') into v_role, v_tier from public.users where id = new.user_id;
    if v_role <> 'admin' or v_tier not in ('committee', 'moderator') then return new; end if;
    if new.report_id is null then
      if new.subject_user_id is null
         and (new.message like 'System check:%' or new.message like 'The admin portal %' or new.message like 'SMART:%') then
        return null;
      end if;
      return new;
    end if;
    if not coalesce((select public._user_sees_case(new.user_id, r.id, r.category, r.handler_id) from public.reports r where r.id = new.report_id), false) then
      return null;
    end if;
    return new;
  exception when others then
    -- fail closed (a notice that cannot be scoped is not sent) and leave a trace an administrator can read (0187's event log, itself best-effort)
    begin
      perform public._smart_event('notice_error', null, 'Notification not delivered: ' || sqlerrm, jsonb_build_object('user', new.user_id, 'case', new.report_id, 'kind', new.kind));
    exception when others then null;
    end;
    return null;
  end;
end $$;

-- UNDO SQL (not run; for the person applying this):
-- -- restore _notifications_scope() from 0175/0185
