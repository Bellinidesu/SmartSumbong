-- UNDO of 0192_mechanical_fixes: the grants as they were and _command_auto as it was (tested). No data changes.
set search_path = public, extensions;
revoke all on function _case_committee(uuid) from public, anon, authenticated, service_role;
grant execute on function _case_committee(uuid) to authenticated, service_role;
revoke all on function _committee_label(text) from public, anon, authenticated, service_role;
grant execute on function _committee_label(text) to anon, authenticated, public, service_role;
revoke all on function _notify_committee_heads(text,uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function _notify_committee_heads(text,uuid,text,text) to authenticated, service_role;
revoke all on function _notify_tanod_committee(uuid,uuid,text) from public, anon, authenticated, service_role;
grant execute on function _notify_tanod_committee(uuid,uuid,text) to authenticated, service_role;
revoke all on function _places_grp(jsonb) from public, anon, authenticated, service_role;
grant execute on function _places_grp(jsonb) to anon, authenticated, public, service_role;
revoke all on function _places_query() from public, anon, authenticated, service_role;
grant execute on function _places_query() to anon, authenticated, public, service_role;
revoke all on function _smart_common_words() from public, anon, authenticated, service_role;
grant execute on function _smart_common_words() to anon, authenticated, public, service_role;
revoke all on function _smart_id_number_ok(id_document_type,text) from public, anon, authenticated, service_role;
grant execute on function _smart_id_number_ok(id_document_type,text) to anon, authenticated, public, service_role;
revoke all on function _smart_name_match(text,text) from public, anon, authenticated, service_role;
grant execute on function _smart_name_match(text,text) to anon, authenticated, public, service_role;
revoke all on function _smart_tokens(text) from public, anon, authenticated, service_role;
grant execute on function _smart_tokens(text) to anon, authenticated, public, service_role;
revoke all on function _smart_vocab() from public, anon, authenticated, service_role;
grant execute on function _smart_vocab() to authenticated, service_role;
revoke all on function auth_email_for(text) from public, anon, authenticated, service_role;
grant execute on function auth_email_for(text) to anon, authenticated, public, service_role;
revoke all on function display_name(text) from public, anon, authenticated, service_role;
grant execute on function display_name(text) to anon, authenticated, public, service_role;
revoke all on function feature_on(text) from public, anon, authenticated, service_role;
grant execute on function feature_on(text) to authenticated, service_role;
revoke all on function is_identity_media_url(text) from public, anon, authenticated, service_role;
grant execute on function is_identity_media_url(text) to anon, authenticated, public, service_role;
revoke all on function is_within_barangay(double precision,double precision) from public, anon, authenticated, service_role;
grant execute on function is_within_barangay(double precision,double precision) to authenticated, service_role;
revoke all on function nearest_available_tanod(uuid) from public, anon, authenticated, service_role;
grant execute on function nearest_available_tanod(uuid) to authenticated, service_role;
revoke all on function smart_eta(complaint_category) from public, anon, authenticated, service_role;
grant execute on function smart_eta(complaint_category) to authenticated, service_role;

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
exception when unique_violation then null;   -- an administrator turned one on at the same moment
end $function$;
