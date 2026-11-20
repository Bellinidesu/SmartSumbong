-- mechanical_fixes (draft test for 0192; moves to supabase/tests when Ace says apply 0192). Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.
do $sweep$
declare
  v_log text := 'setup ok';
  v_res uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_case uuid; n integer; s text;
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
    foreach s in array array['_case_committee(uuid)', '_committee_label(text)', '_notify_committee_heads(text,uuid,text,text)', '_notify_tanod_committee(uuid,uuid,text)', '_places_grp(jsonb)', '_places_query()', '_smart_common_words()', '_smart_id_number_ok(id_document_type,text)', '_smart_name_match(text,text)', '_smart_tokens(text)', '_smart_vocab()', 'auth_email_for(text)', 'display_name(text)', 'feature_on(text)', 'is_identity_media_url(text)', 'is_within_barangay(double precision,double precision)', 'nearest_available_tanod(uuid)', 'smart_eta(complaint_category)'] loop
      perform s::regprocedure;
      if has_function_privilege('authenticated', s::regprocedure, 'execute') or has_function_privilege('anon', s::regprocedure, 'execute') then raise exception '% is still executable by the API', s; end if;
    end loop;
    v_log := v_log || E'\n' || 'ok  the 18 database-only functions are no longer executable by signed-in or signed-out callers (and still exist)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL the 18 database-only functions are no longer executable by signed-in or signed-out callers (and still exist): ' || sqlerrm; end;

  begin
    foreach s in array array['_colour_clash(text,text)', '_colour_dist(text,text)', '_is_sensitive_text(text)', '_one_category_refuse(complaint_category)', '_smart_id_number(text)', '_smart_name_words(text)', 'location_is_fresh(timestamp with time zone)', 'places_norm(text)', 'tanod_dispatch_cap()'] loop
      if not has_function_privilege('authenticated', s::regprocedure, 'execute') then raise exception '% lost a right it needs', s; end if;
    end loop;
    v_log := v_log || E'\n' || 'ok  the 9 excluded functions keep their rights (a SECURITY INVOKER caller or a dependent object needs them)';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL the 9 excluded functions keep their rights (a SECURITY INVOKER caller or a dependent object needs them): ' || sqlerrm; end;

  begin
    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', v_res::text, true);
    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Mech probe', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);
    if not exists (select 1 from public.reports where subject = 'Mech probe') then raise exception 'filing failed'; end if;
    begin perform public.display_name('Reyes, Maria'); raise exception 'a signed-in resident can still call display_name'; exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a resident still files a report (triggers and the invoker chain through the excluded helpers still work) and a signed-in call to a revoked helper is refused';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL a resident still files a report (triggers and the invoker chain through the excluded helpers still work) and a signed-in call to a revoked helper is refused: ' || sqlerrm; end;

  begin
    update public.command_state set auto_switch = true where id = 1;
    create or replace function public.feature_on(p_key text) returns boolean language sql as 'select true';
    create or replace function public._command_active() returns public.command_sessions language sql as 'select null::public.command_sessions';
    create or replace function public._command_suggestion(p_signal smallint default null) returns jsonb language sql as $f$ select '{"mode":"fire","name_en":"Probe","why_en":"probe"}'::jsonb $f$;
    insert into public.command_sessions (mode, how, reason) values ('fire', 'admin', 'an administrator got there first');
    perform public._command_auto();
    if not exists (select 1 from public.smart_events where kind = 'command_auto_skipped') then raise exception 'the skipped auto switch left no event'; end if;
    v_log := v_log || E'\n' || 'ok  _command_auto records the race with an administrator instead of swallowing it silently';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL _command_auto records the race with an administrator instead of swallowing it silently: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
