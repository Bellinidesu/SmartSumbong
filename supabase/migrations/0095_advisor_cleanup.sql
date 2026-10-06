-- 0095 - Database advisor clean-up (industry pass, 7 Oct 2026). No behaviour changes:
-- same rules, same data; generated from the live definitions.

-- Pin the search path of every remaining public function (advisor: function_search_path_mutable).
alter function assign_tracking_id() set search_path = public, extensions;
alter function auth_email_for(text) set search_path = public, extensions;
alter function display_name(text) set search_path = public, extensions;
alter function enforce_media_cap() set search_path = public, extensions;
alter function guard_last_admin() set search_path = public, extensions;
alter function guard_privileged_user_fields() set search_path = public, extensions;
alter function is_barangay_media_url(text) set search_path = public, extensions;
alter function is_evidence_media_url(text) set search_path = public, extensions;
alter function is_media_url(text) set search_path = public, extensions;
alter function reset_verification_overdue_mark() set search_path = public, extensions;
alter function set_accept_deadline() set search_path = public, extensions;
alter function set_report_deadline() set search_path = public, extensions;
alter function set_verification_deadline() set search_path = public, extensions;
alter function sync_dispatchable() set search_path = public, extensions;
alter function touch_settings() set search_path = public, extensions;
alter function touch_updated_at() set search_path = public, extensions;

-- Ask for the signed-in user once per query, not once per row (advisor: auth_rls_initplan).
alter policy dispatch_media_read on public.dispatch_media using ((EXISTS ( SELECT 1
   FROM (dispatches d
     JOIN reports r ON ((r.id = d.report_id)))
  WHERE ((d.id = dispatch_media.dispatch_id) AND ((d.tanod_id = (select auth.uid())) OR is_admin() OR ((r.resident_id = (select auth.uid())) AND (r.deleted_at IS NULL) AND (dispatch_media.update_id IS NULL)))))));
alter policy dispatch_updates_read on public.dispatch_updates using ((is_admin() OR (EXISTS ( SELECT 1
   FROM dispatches d
  WHERE ((d.id = dispatch_updates.dispatch_id) AND (d.tanod_id = (select auth.uid())))))));
alter policy escalation_requests_read on public.escalation_requests using ((is_admin() OR (requested_by = (select auth.uid()))));
alter policy report_messages_read on public.report_messages using ((is_admin() OR (EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_messages.report_id) AND (r.resident_id = (select auth.uid())) AND (r.deleted_at IS NULL))))));

-- Index every foreign key (advisor: unindexed_foreign_keys): faster joins, and deletes no longer scan.
create index if not exists account_audit_actor_id_fk_idx on account_audit (actor_id);
create index if not exists case_handler_log_admin_id_fk_idx on case_handler_log (admin_id);
create index if not exists case_handler_log_previous_id_fk_idx on case_handler_log (previous_id);
create index if not exists case_handler_log_report_id_fk_idx on case_handler_log (report_id);
create index if not exists detail_requests_requested_by_fk_idx on detail_requests (requested_by);
create index if not exists dispatch_media_update_id_fk_idx on dispatch_media (update_id);
create index if not exists dispatch_updates_author_id_fk_idx on dispatch_updates (author_id);
create index if not exists dispatches_assigned_by_fk_idx on dispatches (assigned_by);
create index if not exists dispatches_rerouted_to_fk_idx on dispatches (rerouted_to);
create index if not exists escalation_requests_decided_by_fk_idx on escalation_requests (decided_by);
create index if not exists escalation_requests_dispatch_id_fk_idx on escalation_requests (dispatch_id);
create index if not exists escalation_requests_requested_by_fk_idx on escalation_requests (requested_by);
create index if not exists feedback_resident_id_fk_idx on feedback (resident_id);
create index if not exists notifications_report_id_fk_idx on notifications (report_id);
create index if not exists notifications_subject_user_id_fk_idx on notifications (subject_user_id);
create index if not exists operational_settings_updated_by_fk_idx on operational_settings (updated_by);
create index if not exists profile_requests_decided_by_fk_idx on profile_requests (decided_by);
create index if not exists report_evidence_log_id_fk_idx on report_evidence (log_id);
create index if not exists report_evidence_posted_by_fk_idx on report_evidence (posted_by);
create index if not exists report_messages_author_id_fk_idx on report_messages (author_id);
create index if not exists reports_referred_by_fk_idx on reports (referred_by);
create index if not exists retirement_requests_decided_by_fk_idx on retirement_requests (decided_by);
create index if not exists sla_extensions_approved_by_fk_idx on sla_extensions (approved_by);
create index if not exists sla_extensions_requested_by_fk_idx on sla_extensions (requested_by);
create index if not exists users_admin_handover_successor_id_fk_idx on users (admin_handover_successor_id);
create index if not exists users_verified_by_fk_idx on users (verified_by);
