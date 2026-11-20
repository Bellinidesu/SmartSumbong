-- DRAFT: not applied until Ace says apply 0192
-- 0192_mechanical_fixes: mechanical fixes: revoke the API's right on database-only helpers (proved safe), record _command_auto's swallowed race
--
-- Ace: 'mechanical fixes do'. Three parts.
-- (a) C-03: 16 functions are callable by the API but only other database code calls them; revoking the API's right is safe for exactly these because EVERY caller is
-- SECURITY DEFINER (runs as the owner, which keeps its right) and nothing else in the catalog depends on them (pg_depend: no policy, default, check, index or view):
--   _committee_label, _notify_committee_heads, _notify_tanod_committee, _places_grp, _places_query, _smart_common_words, _smart_id_number_ok, _smart_name_match, _smart_tokens, _smart_vocab, auth_email_for, display_name, feature_on, is_identity_media_url, is_within_barangay, nearest_available_tanod.
-- EXCLUDED, with the reason (revoking would break them):
--   _case_committee: a SECURITY INVOKER caller runs it as the signed-in user: tanod_roster
--   _colour_clash: a SECURITY INVOKER caller runs it as the signed-in user: _committee_colour_check
--   _colour_dist: a SECURITY INVOKER caller runs it as the signed-in user: _super_colour_check
--   _is_sensitive_text: a SECURITY INVOKER caller runs it as the signed-in user: _flag_sensitive
--   _one_category_refuse: a SECURITY INVOKER caller runs it as the signed-in user: file_report
--   _smart_id_number: a SECURITY INVOKER caller runs it as the signed-in user: _smart_id_number_ok
--   _smart_name_words: a SECURITY INVOKER caller runs it as the signed-in user: _smart_name_match
--   location_is_fresh: a SECURITY INVOKER caller runs it as the signed-in user: assignable_tanods, nearest_available_tanod, tanod_roster
--   places_norm: a SECURITY INVOKER caller runs it as the signed-in user: _places_text, search_places
--   smart_eta: pgTAP 04_smart calls it directly as a signed-in administrator (the resolution-time estimate is part of the contract): revoking made that check fail
--   tanod_dispatch_cap: a SECURITY INVOKER caller runs it as the signed-in user: _dispatch_cap_guard, assignable_tanods, nearest_available_tanod
-- (b) D2-06: _command_auto() swallowed one specific, benign error (unique_violation: an administrator turned a mode on in the same moment) without a trace; it now records a
-- 'command_auto_skipped' event, best-effort. D2-07 (file_report) is accepted as it is: the core filing path, proved to survive failures.
-- (c) D3-07: assign_case's notices without a case link are deliberate (the staff member who lost the case must not be sent a link they can no longer open): left as is.
--
-- UNDO (plain language): supabase/drafts/0192_undo.sql restores the grants on the revoked functions and _command_auto word for word (tested); no data changes.
-- Proof: supabase/drafts/tests/76_mechanical_fixes.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_mechanical_fixes.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

set search_path = public, extensions;
set local lock_timeout = '5s';

-- (a) C-03: API rights nothing needs
revoke all on function _committee_label(text) from public, anon, authenticated;   -- called only by: _notify_committee_heads, _reroute_ask, decide_tanod_committee, escalation_target
revoke all on function _notify_committee_heads(text,uuid,text,text) from public, anon, authenticated;   -- called only by: flag_case_for_forward, forward_case
revoke all on function _notify_tanod_committee(uuid,uuid,text) from public, anon, authenticated;   -- called only by: decide_tanod_committee, propose_tanod_committee, remove_tanod_committee
revoke all on function _places_grp(jsonb) from public, anon, authenticated;   -- called only by: places_refresh_file
revoke all on function _places_query() from public, anon, authenticated;   -- called only by: places_refresh_ask
revoke all on function _smart_common_words() from public, anon, authenticated;   -- called only by: _smart_word_candidates
revoke all on function _smart_id_number_ok(id_document_type,text) from public, anon, authenticated;   -- called only by: _smart_verify
revoke all on function _smart_name_match(text,text) from public, anon, authenticated;   -- called only by: _smart_verify
revoke all on function _smart_tokens(text) from public, anon, authenticated;   -- called only by: _command_read, _command_words_all, _smart_category_hint, _smart_read
revoke all on function _smart_vocab() from public, anon, authenticated;   -- called only by: _command_read, _smart_read, _smart_word_candidates
revoke all on function auth_email_for(text) from public, anon, authenticated;   -- called only by: handle_new_auth_user
revoke all on function display_name(text) from public, anon, authenticated;   -- called only by: _case_guard, _case_guard_report, _inbox_alert, _smart_verify
revoke all on function feature_on(text) from public, anon, authenticated;   -- called only by: _command_auto, command_board, command_hall, command_now
revoke all on function is_identity_media_url(text) from public, anon, authenticated;   -- called only by: queue_media_trash
revoke all on function is_within_barangay(double precision,double precision) from public, anon, authenticated;   -- called only by: auto_dispatch
revoke all on function nearest_available_tanod(uuid) from public, anon, authenticated;   -- called only by: _smart_tanod_ranking, auto_dispatch

-- (b) D2-06: _command_auto records its swallowed race
create or replace function public._command_auto()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb; v_id uuid;
begin
  if not public.feature_on('command_center') then return; end if;
  if not coalesce((select auto_switch from public.command_state where id = 1), false) then return; end if;
  if (public._command_active()).id is not null then return; end if;
  s := public._command_suggestion(null);
  if s is null then return; end if;
  insert into public.command_sessions (mode, how, reason, started_by) values (s ->> 'mode', 'auto', left('SMART switched this on: ' || (s ->> 'why_en'), 300), null)
  returning id into v_id;
  perform public._smart_event('command_on', null, format('%s on (SMART, auto switch): %s', s ->> 'name_en', s ->> 'why_en'), jsonb_build_object('session', v_id, 'mode', s ->> 'mode', 'how', 'auto'));
  perform public._notify_admins(format('SMART turned on %s: %s An administrator ends it with a note.', s ->> 'name_en', s ->> 'why_en'));
exception when unique_violation then
  -- an administrator turned one on at the same moment: nothing to do, but leave a trace (0187's best-effort event log)
  begin
    perform public._smart_event('command_auto_skipped', null, 'SMART auto switch skipped: an administrator turned a mode on at the same moment', '{}'::jsonb);
  exception when others then null;
  end;
end $function$;

-- UNDO SQL (not run; for the person applying this):
-- -- see supabase/drafts/0192_undo.sql
