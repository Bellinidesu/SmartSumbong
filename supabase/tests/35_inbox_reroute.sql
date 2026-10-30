-- 35_inbox_reroute.sql: the Inbox along the ladder, system messages, and asking the Kagawad before a reroute (0155). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_stf2 uuid := gen_random_uuid(); v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; r2 uuid; d uuid; q bigint; n integer; b uuid;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999951', 'Mail, Super', 'resident'), (v_kpo, '+639999999952', 'Mail, Peace', 'resident'),
                 (v_kenv, '+639999999953', 'Mail, Env', 'resident'), (v_stf, '+639999999954', 'Mail, Staff', 'resident'),
                 (v_stf2, '+639999999955', 'Mail, Env Staff', 'resident'),
                 (v_t1, '+639999999956', 'Mail, Tanod Uno', 'tanod'), (v_t2, '+639999999957', 'Mail, Tanod Dos', 'tanod'),
                 (v_res, '+639999999958', 'Mail, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_stf2, v_t1, v_t2, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'environment' where id = v_stf2;
  -- t1 is Peace and Order's own tanod but off duty; t2 belongs to no committee and is on duty next to the case
  update public.users set duty_status = 'offline' where id = v_t1;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(lng + 0.0003, lat), 4326), last_location_at = now() where id = v_t2;
  insert into public.tanod_committees (tanod_id, committee, status) values (v_t1, 'peace_order', 'approved');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', lat, lng, now() + interval '2 days') returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'peace_order_nuisance', 'Away', 'May nag-aaway sa kanto.', lat, lng + 0.001, now() + interval '2 days') returning id into r2;
  v_log := 'setup ok';

  -- 1. mail runs along the ladder; only the sender and the recipient read it; a case attached must be one the sender sees
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    b := public.send_mail(array[v_kpo], 'Tungkol sa kaso', 'Pakitingnan po ito.', r1, null);
    begin perform public.send_mail(array[v_kenv], 'Hi', 'Hello', null, null); raise exception 'staff wrote to another Kagawad';
    exception when insufficient_privilege then null; end;
    begin perform public.send_mail(array[v_sup], 'Hi', 'Hello', null, null); raise exception 'staff wrote to a super admin';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.send_mail(array[v_sup, v_kenv, v_stf], 'Pulong', 'Bukas ng alas-diyes.', null, null);
    begin perform public.send_mail(array[v_stf2], 'Hi', 'Hello', null, null); raise exception 'a Kagawad wrote to another committee''s staff';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_stf2::text, true);
    begin perform public.send_mail(array[v_kenv], 'Kaso', 'Ito po', r1, null); raise exception 'staff attached a case outside their committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.send_mail(array[v_stf2], 'Paalala', 'Salamat.', null, null);
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if not exists (select 1 from public.inbox_messages where batch = b and recipient = v_kpo and report_id = r1) then raise exception 'the Kagawad cannot read it'; end if;
    if public.mark_mail_read(array(select id from public.inbox_messages where batch = b)) <> 1 then raise exception 'not marked read'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if exists (select 1 from public.inbox_messages where batch = b) then raise exception 'someone else reads it'; end if;
    begin insert into public.inbox_messages (sender, recipient, subject, body) values (v_kenv, v_kpo, 'x', 'y'); raise exception 'mail written by hand';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if not exists (select 1 from public.mail_recipients() where id = v_kpo)
       or exists (select 1 from public.mail_recipients() where id in (v_sup, v_kenv, v_stf2)) then raise exception 'staff may write to the wrong people'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  mail runs along the ladder (staff to their Kagawad only; a Kagawad to their staff, Kagawads and super admins; a super admin to anyone); only the sender and the recipient read it; an attached case must be one the sender sees';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL ladder: ' || sqlerrm; end;

  -- 2. a forward arrives in the receiving Kagawad's Inbox as a system message
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.forward_case(r2, 'environment', 'Basura ang ugat', null);
    if not exists (select 1 from public.inbox_messages where recipient = v_kenv and report_id = r2 and kind = 'system' and sender is null) then raise exception 'no system message'; end if;
    v_log := v_log || E'\n' || 'ok  a forward arrives in the receiving Kagawad''s Inbox as a system message';
  exception when others then v_log := v_log || E'\n' || 'FAIL system: ' || sqlerrm; end;

  -- 3. a reroute with none of the committee's tanods free asks its Kagawad instead of sending anyone; the Kagawad picks
  begin
    perform set_config('request.jwt.claim.sub', '', true);   -- the reroute runs as the system (the sweep), not as anyone signed in
    update public.reports set dispatch_attempts = 1, status = 'validated' where id = r1;
    d := public.auto_dispatch(r1);
    if d is not null then raise exception 'a tanod outside the committee was sent without asking'; end if;
    select id into q from public.reroute_questions where report_id = r1 and state = 'open';
    if q is null then raise exception 'no question'; end if;
    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = r1 and kind::text = 'reroute_question') then raise exception 'Kagawad not notified'; end if;
    if not exists (select 1 from public.inbox_messages where recipient = v_kpo and question_id = q) then raise exception 'no Inbox question'; end if;
    if public.auto_dispatch(r1) is not null or (select count(*) from public.reroute_questions where report_id = r1) <> 1 then raise exception 'asked twice'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.answer_reroute_question(q, v_t2); raise exception 'another committee answered';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    d := public.answer_reroute_question(q, v_t2);
    if d is null or not exists (select 1 from public.dispatches where id = d and tanod_id = v_t2) then raise exception 'the pick was not sent'; end if;
    if (select state from public.reroute_questions where id = q) <> 'picked' then raise exception 'question not closed'; end if;
    v_log := v_log || E'\n' || 'ok  a reroute with none of the case''s committee''s tanods free asks its Kagawad (notification and Inbox, once) instead of sending anyone; only that Kagawad answers, and the tanod they pick is sent';
  exception when others then v_log := v_log || E'\n' || 'FAIL ask: ' || sqlerrm; end;

  -- 4. nobody answers in time: the nearest tanod from any committee is sent, and the trail says so
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    update public.dispatches set state = 'expired' where report_id = r1;
    update public.reports set dispatch_attempts = 2, status = 'validated' where id = r1;
    perform public.auto_dispatch(r1);
    select id into q from public.reroute_questions where report_id = r1 and state = 'open';
    if q is null then raise exception 'no second question'; end if;
    update public.reroute_questions set due_at = now() - interval '1 minute' where id = q;
    perform public.sweep_reroute_questions();
    if (select state from public.reroute_questions where id = q) <> 'timed_out' then raise exception 'not timed out'; end if;
    if not exists (select 1 from public.dispatches where report_id = r1 and tanod_id = v_t2 and state = 'assigned') then raise exception 'the nearest was not sent'; end if;
    if not exists (select 1 from public.status_logs where report_id = r1 and remark like 'Nobody answered in time%') then raise exception 'the trail is silent'; end if;
    v_log := v_log || E'\n' || 'ok  nobody answering in time sends the nearest tanod from any committee, and the case''s trail says so';
  exception when others then v_log := v_log || E'\n' || 'FAIL timeout: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
