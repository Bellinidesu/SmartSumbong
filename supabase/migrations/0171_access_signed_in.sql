-- 0171: access rules for signed-in users (11 Nov 2026, the backend sweep).
--
-- 174 of the 177 row-level-security policies were written without a role, so PostgreSQL applies them to every role, signed-out
-- callers (anon) included, and each relied on its own condition to keep them out. Every one of those conditions comes down to
-- auth.uid() (directly, or through is_admin(), admin_tier(), my_role(), is_full_viewer(), admin_sees_report(),
-- _user_sees_case(), _sees_punch_card(), admin_can_write(), _ws_is_lead() and the like), which is empty for a signed-out caller,
-- so they never let one in. Scoping them TO authenticated says so in the rule itself: defence in depth (a future condition
-- that forgets the sign-in check cannot open a table to the internet), and PostgreSQL no longer evaluates them for anon at all.
-- This is Supabase's own advice for policies.
--
-- Eight stay for every role, because signed-out callers do read them (the app before sign-in, the keep-awake ping):
--   barangay_boundary.boundary_read
--   barangay_profile.barangay_profile_read
--   complaint_categories.complaint_categories_read
--   complaint_options.complaint_options_read
--   hazard_zones.hazard_zones_read
--   hotline_groups.hotline_groups_read
--   hotline_numbers.hotline_numbers_read
--   wording.wording_read
-- Their conditions are `true`, `active`, `is_active` or `active OR is_admin()`.
--
-- Nothing a signed-in user may do changes, and nothing a signed-out caller can read today changes (test 50 checks both).
-- New policies: write them `to authenticated` unless signed-out callers must read the table.

alter policy account_audit_read on public.account_audit to authenticated;
alter policy admin_punches_read on public.admin_punches to authenticated;
alter policy app_releases_read on public.app_releases to authenticated;
alter policy attendance_insert on public.attendance to authenticated;
alter policy attendance_read on public.attendance to authenticated;
alter policy barangay_profile_super_update on public.barangay_profile to authenticated;
alter policy case_forwards_read on public.case_forwards to authenticated;
alter policy case_handler_log_read on public.case_handler_log to authenticated;
alter policy checkpoint_scans_delete on public.checkpoint_scans to authenticated;
alter policy checkpoint_scans_insert on public.checkpoint_scans to authenticated;
alter policy checkpoint_scans_read on public.checkpoint_scans to authenticated;
alter policy command_checklist_read on public.command_checklist to authenticated;
alter policy command_checks_read on public.command_checks to authenticated;
alter policy command_display_links_read on public.command_display_links to authenticated;
alter policy command_handovers_read on public.command_handovers to authenticated;
alter policy command_modes_read on public.command_modes to authenticated;
alter policy command_place_checks_read on public.command_place_checks to authenticated;
alter policy command_place_kinds_read on public.command_place_kinds to authenticated;
alter policy command_sessions_read on public.command_sessions to authenticated;
alter policy command_state_read on public.command_state to authenticated;
alter policy command_tags_read on public.command_tags to authenticated;
alter policy command_words_read on public.command_words to authenticated;
alter policy committee_categories_read on public.committee_categories to authenticated;
alter policy committee_for_category_admin_read on public.committee_for_category to authenticated;
alter policy committee_for_category_super_delete on public.committee_for_category to authenticated;
alter policy committee_for_category_super_insert on public.committee_for_category to authenticated;
alter policy committee_for_category_super_update on public.committee_for_category to authenticated;
alter policy committees_read on public.committees to authenticated;
alter policy dev_level_switches_read on public.dev_level_switches to authenticated;
alter policy dev_test_accounts_own on public.dev_test_accounts to authenticated;
alter policy device_tokens_own_read on public.device_tokens to authenticated;
alter policy dispatch_media_insert on public.dispatch_media to authenticated;
alter policy dispatch_media_read on public.dispatch_media to authenticated;
alter policy dispatch_updates_read on public.dispatch_updates to authenticated;
alter policy dispatches_admin_delete on public.dispatches to authenticated;
alter policy dispatches_admin_insert on public.dispatches to authenticated;
alter policy dispatches_admin_update on public.dispatches to authenticated;
alter policy dispatches_read on public.dispatches to authenticated;
alter policy duty_roster_delete on public.duty_roster to authenticated;
alter policy duty_roster_insert on public.duty_roster to authenticated;
alter policy duty_roster_read on public.duty_roster to authenticated;
alter policy engine_jobs_admin_read on public.engine_jobs to authenticated;
alter policy escalation_requests_read on public.escalation_requests to authenticated;
alter policy feature_switches_read on public.feature_switches to authenticated;
alter policy feedback_insert on public.feedback to authenticated;
alter policy feedback_read on public.feedback to authenticated;
alter policy game_scores_read on public.game_scores to authenticated;
alter policy hotline_groups_admin_read on public.hotline_groups to authenticated;
alter policy hotline_groups_super_delete on public.hotline_groups to authenticated;
alter policy hotline_groups_super_insert on public.hotline_groups to authenticated;
alter policy hotline_groups_super_update on public.hotline_groups to authenticated;
alter policy hotline_numbers_admin_read on public.hotline_numbers to authenticated;
alter policy hotline_numbers_super_delete on public.hotline_numbers to authenticated;
alter policy hotline_numbers_super_insert on public.hotline_numbers to authenticated;
alter policy hotline_numbers_super_update on public.hotline_numbers to authenticated;
alter policy inbox_messages_read on public.inbox_messages to authenticated;
alter policy look_shares_admin_delete on public.look_shares to authenticated;
alter policy look_shares_admin_insert on public.look_shares to authenticated;
alter policy look_shares_admin_read on public.look_shares to authenticated;
alter policy look_shares_admin_update on public.look_shares to authenticated;
alter policy look_shares_tanod_read on public.look_shares to authenticated;
alter policy look_shares_tanod_seen on public.look_shares to authenticated;
alter policy notifications_read on public.notifications to authenticated;
alter policy notifications_update on public.notifications to authenticated;
alter policy settings_read on public.operational_settings to authenticated;
alter policy settings_write on public.operational_settings to authenticated;
alter policy patrol_checkpoints_delete on public.patrol_checkpoints to authenticated;
alter policy patrol_checkpoints_insert on public.patrol_checkpoints to authenticated;
alter policy patrol_checkpoints_read on public.patrol_checkpoints to authenticated;
alter policy patrol_checkpoints_update on public.patrol_checkpoints to authenticated;
alter policy places_refresh_admin_read on public.places_refresh to authenticated;
alter policy poll_votes_insert on public.poll_votes to authenticated;
alter policy poll_votes_read on public.poll_votes to authenticated;
alter policy poll_votes_update on public.poll_votes to authenticated;
alter policy polls_insert on public.polls to authenticated;
alter policy polls_read on public.polls to authenticated;
alter policy polls_update on public.polls to authenticated;
alter policy portal_errors_admin_read on public.portal_errors to authenticated;
alter policy portal_outages_admin_read on public.portal_outages to authenticated;
alter policy preview_sessions_own on public.preview_sessions to authenticated;
alter policy profile_requests_read on public.profile_requests to authenticated;
alter policy relief_tally_delete on public.relief_tally to authenticated;
alter policy relief_tally_insert on public.relief_tally to authenticated;
alter policy relief_tally_read on public.relief_tally to authenticated;
alter policy report_concerns_admin_read on public.report_concerns to authenticated;
alter policy report_concerns_owner_read on public.report_concerns to authenticated;
alter policy report_evidence_read on public.report_evidence to authenticated;
alter policy report_media_insert on public.report_media to authenticated;
alter policy report_media_read on public.report_media to authenticated;
alter policy report_messages_read on public.report_messages to authenticated;
alter policy report_triage_admin_read on public.report_triage to authenticated;
alter policy reports_admin_update on public.reports to authenticated;
alter policy reports_resident_insert on public.reports to authenticated;
alter policy reports_resident_read on public.reports to authenticated;
alter policy reroute_questions_read on public.reroute_questions to authenticated;
alter policy resolution_checks_admin_read on public.resolution_checks to authenticated;
alter policy resolution_checks_owner_read on public.resolution_checks to authenticated;
alter policy retirement_requests_read on public.retirement_requests to authenticated;
alter policy retirement_requests_super_delete on public.retirement_requests to authenticated;
alter policy retirement_requests_super_insert on public.retirement_requests to authenticated;
alter policy retirement_requests_super_update on public.retirement_requests to authenticated;
alter policy safe_point_notes_delete on public.safe_point_notes to authenticated;
alter policy safe_point_notes_insert on public.safe_point_notes to authenticated;
alter policy safe_point_notes_read on public.safe_point_notes to authenticated;
alter policy safe_point_notes_update on public.safe_point_notes to authenticated;
alter policy shift_checkins_insert on public.shift_checkins to authenticated;
alter policy shift_checkins_read on public.shift_checkins to authenticated;
alter policy shift_checkins_update on public.shift_checkins to authenticated;
alter policy sla_extensions_admin_delete on public.sla_extensions to authenticated;
alter policy sla_extensions_admin_insert on public.sla_extensions to authenticated;
alter policy sla_extensions_admin_update on public.sla_extensions to authenticated;
alter policy sla_extensions_read on public.sla_extensions to authenticated;
alter policy sla_policies_admin_read on public.sla_policies to authenticated;
alter policy sla_policies_read on public.sla_policies to authenticated;
alter policy sla_policies_super_delete on public.sla_policies to authenticated;
alter policy sla_policies_super_insert on public.sla_policies to authenticated;
alter policy sla_policies_super_update on public.sla_policies to authenticated;
alter policy smart_events_admin_read on public.smart_events to authenticated;
alter policy smart_lexicon_admin_read on public.smart_lexicon to authenticated;
alter policy smart_lexicon_super_delete on public.smart_lexicon to authenticated;
alter policy smart_lexicon_super_insert on public.smart_lexicon to authenticated;
alter policy smart_lexicon_super_update on public.smart_lexicon to authenticated;
alter policy smart_overrides_admin_read on public.smart_overrides to authenticated;
alter policy smart_patterns_seen_admin_read on public.smart_patterns_seen to authenticated;
alter policy smart_rule_versions_admin_read on public.smart_rule_versions to authenticated;
alter policy smart_rules_admin_read on public.smart_rules to authenticated;
alter policy smart_rules_admin_write on public.smart_rules to authenticated;
alter policy smart_word_decisions_admin_read on public.smart_word_decisions to authenticated;
alter policy smart_work_orders_admin_read on public.smart_work_orders to authenticated;
alter policy staff_credentials_delete on public.staff_credentials to authenticated;
alter policy staff_credentials_insert on public.staff_credentials to authenticated;
alter policy staff_credentials_read on public.staff_credentials to authenticated;
alter policy staff_credentials_update on public.staff_credentials to authenticated;
alter policy staff_dates_delete on public.staff_dates to authenticated;
alter policy staff_dates_insert on public.staff_dates to authenticated;
alter policy staff_dates_read on public.staff_dates to authenticated;
alter policy staff_dates_update on public.staff_dates to authenticated;
alter policy staff_leave_delete on public.staff_leave to authenticated;
alter policy staff_leave_insert on public.staff_leave to authenticated;
alter policy staff_leave_read on public.staff_leave to authenticated;
alter policy status_logs_insert on public.status_logs to authenticated;
alter policy status_logs_read on public.status_logs to authenticated;
alter policy system_alerts_admin_read on public.system_alerts to authenticated;
alter policy tanod_committee_log_read on public.tanod_committee_log to authenticated;
alter policy tanod_committees_read on public.tanod_committees to authenticated;
alter policy team_post_reads_insert on public.team_post_reads to authenticated;
alter policy team_post_reads_read on public.team_post_reads to authenticated;
alter policy team_posts_insert on public.team_posts to authenticated;
alter policy team_posts_read on public.team_posts to authenticated;
alter policy team_posts_update on public.team_posts to authenticated;
alter policy users_self_read on public.users to authenticated;
alter policy users_self_update on public.users to authenticated;
alter policy users_super_delete on public.users to authenticated;
alter policy users_super_insert on public.users to authenticated;
alter policy users_super_update on public.users to authenticated;
alter policy web_push_own_delete on public.web_push_subscriptions to authenticated;
alter policy web_push_own_read on public.web_push_subscriptions to authenticated;
alter policy wording_super_delete on public.wording to authenticated;
alter policy wording_super_insert on public.wording to authenticated;
alter policy wording_super_update on public.wording to authenticated;
alter policy workspace_prefs_delete on public.workspace_prefs to authenticated;
alter policy workspace_prefs_insert on public.workspace_prefs to authenticated;
alter policy workspace_prefs_read on public.workspace_prefs to authenticated;
alter policy workspace_prefs_update on public.workspace_prefs to authenticated;
alter policy workspace_settings_read on public.workspace_settings to authenticated;
alter policy workspace_settings_update on public.workspace_settings to authenticated;
