-- 0186 (backend sweep 2, 20 Nov 2026): applied after Ace said "apply 0186".
-- 0186_revoke_dead_trigger_functions: revoke the API's right to run 34 trigger functions (a trigger needs no EXECUTE right to fire)
--
-- tools/sweep/callgraph.py: _ask_if_fixed, _case_guard_report, _case_guard_row, _catalogue_change_note, _close_concerns, _committee_colour_check, _concern_snapshot, _dispatch_cap_guard, _flag_sensitive, _guard_case_committee, _guard_official_fields, _inbox_alert, _main_concern, _status_log_no_repeat, _super_colour_check, _triage_rules_version, assign_tracking_id, chain_account_audit, chain_status_log, confirm_synthetic_auth_email, dispatch_on_file, enforce_daily_report_limit, enforce_media_cap, guard_last_admin, guard_privileged_user_fields, handle_new_auth_user, refuse_audit_write, reset_verification_overdue_mark, set_accept_deadline, set_report_deadline, set_verification_deadline, sync_dispatchable, touch_settings, touch_updated_at are trigger functions attached to no trigger yet still executable by signed-out and signed-in callers.
-- Nothing calls them; a direct call only errors, but the right is dead surface. supabase/grants.txt must be regenerated when this is applied (these lines go to anon=- authenticated=-).
--
-- UNDO (plain language): grant execute on function _ask_if_fixed(), _case_guard_report(), _case_guard_row(), _catalogue_change_note(), _close_concerns(), _committee_colour_check(), _concern_snapshot(), _dispatch_cap_guard(), _flag_sensitive(), _guard_case_committee(), _guard_official_fields(), _inbox_alert(), _main_concern(), _status_log_no_repeat(), _super_colour_check(), _triage_rules_version(), assign_tracking_id(), chain_account_audit(), chain_status_log(), confirm_synthetic_auth_email(), dispatch_on_file(), enforce_daily_report_limit(), enforce_media_cap(), guard_last_admin(), guard_privileged_user_fields(), handle_new_auth_user(), refuse_audit_write(), reset_verification_overdue_mark(), set_accept_deadline(), set_report_deadline(), set_verification_deadline(), sync_dispatchable(), touch_settings(), touch_updated_at() to anon, authenticated;   (they are attached to no trigger, so nothing depends on it)
-- Proof: supabase/drafts/tests/0186_revoke_dead_trigger_functions.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_revoke_unused.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

revoke all on function _ask_if_fixed() from public, anon, authenticated;
revoke all on function _case_guard_report() from public, anon, authenticated;
revoke all on function _case_guard_row() from public, anon, authenticated;
revoke all on function _catalogue_change_note() from public, anon, authenticated;
revoke all on function _close_concerns() from public, anon, authenticated;
revoke all on function _committee_colour_check() from public, anon, authenticated;
revoke all on function _concern_snapshot() from public, anon, authenticated;
revoke all on function _dispatch_cap_guard() from public, anon, authenticated;
revoke all on function _flag_sensitive() from public, anon, authenticated;
revoke all on function _guard_case_committee() from public, anon, authenticated;
revoke all on function _guard_official_fields() from public, anon, authenticated;
revoke all on function _inbox_alert() from public, anon, authenticated;
revoke all on function _main_concern() from public, anon, authenticated;
revoke all on function _status_log_no_repeat() from public, anon, authenticated;
revoke all on function _super_colour_check() from public, anon, authenticated;
revoke all on function _triage_rules_version() from public, anon, authenticated;
revoke all on function assign_tracking_id() from public, anon, authenticated;
revoke all on function chain_account_audit() from public, anon, authenticated;
revoke all on function chain_status_log() from public, anon, authenticated;
revoke all on function confirm_synthetic_auth_email() from public, anon, authenticated;
revoke all on function dispatch_on_file() from public, anon, authenticated;
revoke all on function enforce_daily_report_limit() from public, anon, authenticated;
revoke all on function enforce_media_cap() from public, anon, authenticated;
revoke all on function guard_last_admin() from public, anon, authenticated;
revoke all on function guard_privileged_user_fields() from public, anon, authenticated;
revoke all on function handle_new_auth_user() from public, anon, authenticated;
revoke all on function refuse_audit_write() from public, anon, authenticated;
revoke all on function reset_verification_overdue_mark() from public, anon, authenticated;
revoke all on function set_accept_deadline() from public, anon, authenticated;
revoke all on function set_report_deadline() from public, anon, authenticated;
revoke all on function set_verification_deadline() from public, anon, authenticated;
revoke all on function sync_dispatchable() from public, anon, authenticated;
revoke all on function touch_settings() from public, anon, authenticated;
revoke all on function touch_updated_at() from public, anon, authenticated;

-- UNDO SQL (not run; for the person applying this):
-- grant execute on function _ask_if_fixed(), _case_guard_report(), _case_guard_row(), _catalogue_change_note(), _close_concerns(), _committee_colour_check(), _concern_snapshot(), _dispatch_cap_guard(), _flag_sensitive(), _guard_case_committee(), _guard_official_fields(), _inbox_alert(), _main_concern(), _status_log_no_repeat(), _super_colour_check(), _triage_rules_version(), assign_tracking_id(), chain_account_audit(), chain_status_log(), confirm_synthetic_auth_email(), dispatch_on_file(), enforce_daily_report_limit(), enforce_media_cap(), guard_last_admin(), guard_privileged_user_fields(), handle_new_auth_user(), refuse_audit_write(), reset_verification_overdue_mark(), set_accept_deadline(), set_report_deadline(), set_verification_deadline(), sync_dispatchable(), touch_settings(), touch_updated_at() to anon, authenticated;   (they are attached to no trigger, so nothing depends on it)
