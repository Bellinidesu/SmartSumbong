-- 33_forwarding.sql: forwarding a case between committees (0152). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_res uuid := gen_random_uuid();
  r1 uuid; r2 uuid; r3 uuid; f bigint; n integer;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999921', 'Fwd, Super'), (v_kpo, '+639999999922', 'Fwd, Peace'), (v_kenv, '+639999999923', 'Fwd, Env'),
                 (v_stf, '+639999999924', 'Fwd, Staff'), (v_res, '+639999999925', 'Fwd, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Away', 'May nag-aaway sa kanto.', lat, lng + 0.001) returning id into r2;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Tambay', 'Mga tambay hanggang madaling araw.', lat + 0.001, lng) returning id into r3;
  update public.reports set handler_id = v_kpo, handled_since = now() where id = r1;
  v_log := 'setup ok';

  -- 1. a Kagawad forwards a case to another committee: it moves there, leaves its handler, and the other Kagawad is told
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.forward_case(r1, 'environment', 'Basura ang ugat nito', null);
    if (select committee || '/' || coalesce(handler_id::text, 'none') from public.reports where id = r1) <> 'environment/none' then raise exception 'not moved'; end if;
    if not exists (select 1 from public.case_handler_log where report_id = r1 and action = 'release' and previous_id = v_kpo) then raise exception 'release not logged'; end if;
    if not exists (select 1 from public.notifications where user_id = v_kenv and report_id = r1 and kind::text = 'case_forwarded') then raise exception 'not told'; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if not exists (select 1 from public.reports where id = r1) then raise exception 'the receiving committee cannot see it'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if exists (select 1 from public.reports where id = r1) then raise exception 'the sending committee still sees it'; end if;
    if not exists (select 1 from public.case_forwards where report_id = r1 and kind = 'forward' and from_committee = 'peace_order') then raise exception 'the sender cannot see what left'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a Kagawad forwards a case: it moves to the other committee alone, leaves its handler (logged), and that Kagawad is told';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL forward: ' || sqlerrm; end;

  -- 2. a case changes committee only by forwarding; the log cannot be written or changed by hand
  begin
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin update public.reports set committee = 'peace_order' where id = r1; raise exception 'moved by hand';
    exception when insufficient_privilege then null; end;
    execute 'set local role authenticated';
    begin insert into public.case_forwards (report_id, kind) values (r1, 'forward'); raise exception 'a forward written by hand';
    exception when insufficient_privilege then null; end;
    delete from public.case_forwards where report_id = r1;
    get diagnostics n = row_count;
    reset role;
    if n <> 0 then raise exception 'a forward was deleted'; end if;
    v_log := v_log || E'\n' || 'ok  a case changes committee only by forwarding; the forward log cannot be written, changed or deleted by hand';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL guard: ' || sqlerrm; end;

  -- 3. staff flag (with a reason); the Kagawad forwards to the super admins, who place it with a committee
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.forward_case(r2, 'environment', null, null); raise exception 'staff forwarded';
    exception when insufficient_privilege then null; end;
    begin perform public.flag_case_for_forward(r2, 'no', null); raise exception 'a flag without a reason';
    exception when check_violation then null; end;
    f := public.flag_case_for_forward(r2, 'Hindi ito usapin ng kapayapaan', null);
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r2 and kind::text = 'forward_flag') then raise exception 'Kagawad not told of the flag'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.forward_case(r2, null, 'Saan ito dapat?', f);
    if not (select awaiting_placement from public.reports where id = r2) then raise exception 'not waiting for the super admins'; end if;
    if exists (select 1 from public.case_forward_flags where id = f) then raise exception 'the flag is still open'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and report_id = r2 and kind::text = 'case_forwarded') then raise exception 'super admins not told'; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if exists (select 1 from public.reports where id = r2) then raise exception 'a committee sees a case waiting for the super admins'; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.forward_case(r3, null, null, null); exception when others then raise exception 'Kagawad could not hand r3 up: %', sqlerrm; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.forward_case(r2, 'health_sanitation', null, null);
    if (select committee from public.reports where id = r2) <> 'health_sanitation' or (select awaiting_placement from public.reports where id = r2) then raise exception 'not placed'; end if;
    v_log := v_log || E'\n' || 'ok  staff cannot forward but flag with a reason (their Kagawad is told); the Kagawad hands it to the super admins (no committee sees it), who place it';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL flag: ' || sqlerrm; end;

  -- 4. only the flagging committee's Kagawad (or a super admin) dismisses a flag; the staff member is told
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.forward_case(r3, 'peace_order', null, null);
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    f := public.flag_case_for_forward(r3, 'Mukhang sa kalusugan ito', 'health_sanitation');
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.dismiss_forward_flag(f, null); raise exception 'another committee dismissed the flag';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.dismiss_forward_flag(f, 'Sa atin pa rin ito');
    if exists (select 1 from public.case_forward_flags where id = f) then raise exception 'still open'; end if;
    if not exists (select 1 from public.notifications where user_id = v_stf and report_id = r3 and message like '%dismissed%') then raise exception 'staff not told'; end if;
    v_log := v_log || E'\n' || 'ok  only the flagging committee''s Kagawad or a super admin dismisses a flag, and the staff member is told';
  exception when others then v_log := v_log || E'\n' || 'FAIL dismiss: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
