-- 51_mail_state.sql: BarangayMail keeps its state the way Gmail does, and the case chats remember where each person was (0173). Rolled back.
-- The writing checks call the functions as each person (auth.uid() from the claim); the reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; b1 uuid; b2 uuid; m_kpo bigint; m_stf bigint; n integer; lbl bigint; lbl2 bigint; d1 bigint; d2 bigint; t1 uuid;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'State, Super'), (v_kpo, '+639999999962', 'State, Peace'), (v_kenv, '+639999999963', 'State, Env'),
                 (v_stf, '+639999999964', 'State, Staff'), (v_res, '+639999999965', 'State, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', lat, lng, now() + interval '2 days') returning id into r1;

  -- 1. Cc and Bcc: each recipient row says how they were addressed; a reply stays in the first message's thread; who sees whom
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    b1 := public.send_mail(array[v_kpo], 'Pulong', 'Bukas ng alas-diyes.', null, null, array[v_stf], array[v_kenv], null);
    if (select count(*) from public.inbox_messages where batch = b1) <> 3 then raise exception 'not one row per person'; end if;
    if (select role from public.inbox_messages where batch = b1 and recipient = v_kpo) <> 'to' or (select role from public.inbox_messages where batch = b1 and recipient = v_stf) <> 'cc'
       or (select role from public.inbox_messages where batch = b1 and recipient = v_kenv) <> 'bcc' then raise exception 'the roles are wrong'; end if;
    if exists (select 1 from public.inbox_messages where batch = b1 and thread_id <> b1) then raise exception 'a first message is not its own thread'; end if;
    select id into m_kpo from public.inbox_messages where batch = b1 and recipient = v_kpo;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    b2 := public.send_mail(array[v_sup], 'Re: Pulong', 'Sige po.', null, m_kpo);
    if (select thread_id from public.inbox_messages where batch = b2) <> b1 then raise exception 'the reply left the thread'; end if;
    -- the staff member (a cc) sees the to and cc but not the bcc; the bcc sees themself; the sender sees all
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if exists (select 1 from public.mail_batch_people(b1) where role = 'bcc') or (select count(*) from public.mail_batch_people(b1)) <> 2 then raise exception 'a cc sees the bcc'; end if;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if (select count(*) from public.mail_batch_people(b1) where role = 'bcc' and user_id = v_kenv) <> 1 then raise exception 'the bcc cannot see themself'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if (select count(*) from public.mail_batch_people(b1)) <> 3 then raise exception 'the sender does not see all three'; end if;
    -- a stranger sees no one
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    if (select count(*) from public.mail_batch_people(b1)) <> 0 then raise exception 'a stranger sees the people'; end if;
    -- the ladder still holds for a cc and a bcc: staff may not write to a super admin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.send_mail(array[v_kpo], 'x', 'y', null, null, array[v_sup], '{}', null); raise exception 'staff copied a super admin';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  cc and bcc are kept per recipient, a reply stays in its thread, a bcc is hidden from the others, and the ladder still applies to every list';
  exception when others then v_log := v_log || E'\n' || 'FAIL cc/bcc/thread: ' || sqlerrm; end;

  -- 2. stars, archive, trash, snooze: one person's own marks on a message they sent or received, and no one else's
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if public.mail_flag(array[b1], true, true, null, null, null, false) <> 1 then raise exception 'not flagged'; end if;
    if not exists (select 1 from public.mail_state where user_id = v_kpo and batch = b1 and starred and archived and trashed_at is null) then raise exception 'star and archive not kept'; end if;
    perform public.mail_flag(array[b1], null, false, true, null, null, false);
    if not exists (select 1 from public.mail_state where user_id = v_kpo and batch = b1 and starred and not archived and trashed_at is not null) then raise exception 'trash not kept, or it undid the star'; end if;
    perform public.mail_flag(array[b1], null, null, false, null, null, false);
    if (select trashed_at from public.mail_state where user_id = v_kpo and batch = b1) is not null then raise exception 'not taken out of the trash'; end if;
    perform public.mail_flag(array[b1], null, null, null, null, now() + interval '1 day', false);
    if (select snoozed_until from public.mail_state where user_id = v_kpo and batch = b1) is null then raise exception 'snooze not kept'; end if;
    perform public.mail_flag(array[b1], null, null, null, null, null, true);
    if (select snoozed_until from public.mail_state where user_id = v_kpo and batch = b1) is not null then raise exception 'snooze not cleared'; end if;
    -- the sender marks their own sent copy too; a person outside the message cannot mark it at all
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if public.mail_flag(array[b1], true, null, null, null, null, false) <> 1 then raise exception 'the sender could not star their sent mail'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.mail_flag(array[b1], true, null, null, null, null, false); raise exception 'a resident flagged mail';
    exception when insufficient_privilege then null; end;
    -- b2 went from the Kagawad to the super admin: staff are not in it
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if public.mail_flag(array[b2], true, null, null, null, null, false) <> 0 then raise exception 'staff flagged a message they are not in'; end if;
    -- unread and read again
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    select id into m_kpo from public.inbox_messages where batch = b1 and recipient = v_kpo;
    perform public.mark_mail_read(array[m_kpo]);
    n := public.mail_set_read(array[m_kpo], false);
    if n <> 1 or (select read_at from public.inbox_messages where id = m_kpo) is not null then raise exception 'not marked unread'; end if;
    n := public.mail_set_read(array[m_kpo], true);
    if n <> 1 or (select read_at from public.inbox_messages where id = m_kpo) is null then raise exception 'not marked read again'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if public.mail_set_read(array[m_kpo], false) <> 0 then raise exception 'the sender changed the recipient''s read mark'; end if;
    v_log := v_log || E'\n' || 'ok  star, archive, trash, snooze and read/unread are one person''s own marks, kept and undone, on mail they sent or received only';
  exception when others then v_log := v_log || E'\n' || 'FAIL state: ' || sqlerrm; end;

  -- 3. labels: made, renamed, put on a message and taken off; one name once; never on or from someone else's
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    lbl := public.mail_label_save(null, 'Para sa komite', '#1E9E4A');
    begin perform public.mail_label_save(null, 'PARA SA KOMITE', '#1E9E4A'); raise exception 'the same label twice';
    exception when unique_violation then null; end;
    begin perform public.mail_label_save(null, 'Bad', 'green'); raise exception 'a colour that is not hex';
    exception when check_violation then null; end;
    perform public.mail_label_save(lbl, 'Komite', null);
    if (select name from public.mail_labels where id = lbl) <> 'Komite' then raise exception 'not renamed'; end if;
    if public.mail_label_apply(array[b1, b2], lbl, true) <> 2 then raise exception 'label not put on both messages'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.mail_label_apply(array[b1], lbl, true); raise exception 'someone used another person''s label';
    exception when check_violation then null; end;
    lbl2 := public.mail_label_save(null, 'Akin', '#00308F');
    if public.mail_label_apply(array[b2], lbl2, true) <> 0 then raise exception 'a label went on a message the person is not in'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if public.mail_label_apply(array[b1], lbl, false) <> 1 then raise exception 'label not taken off'; end if;
    perform public.mail_label_delete(lbl);
    if exists (select 1 from public.mail_label_links where label_id = lbl) then raise exception 'a deleted label left its links'; end if;
    v_log := v_log || E'\n' || 'ok  labels are made, renamed, applied and removed by their owner only, one name once, and deleting one clears its links';
  exception when others then v_log := v_log || E'\n' || 'FAIL labels: ' || sqlerrm; end;

  -- 4. drafts: kept, changed, never another person's, and removed when sent
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    d1 := public.mail_draft_save(null, array[v_sup], '{}', '{}', 'Sulat', 'Una pa lang.', null, null);
    d1 := public.mail_draft_save(d1, array[v_sup], array[v_stf], '{}', 'Sulat', 'Mas buo na.', r1, null);
    if (select body from public.mail_drafts where id = d1) <> 'Mas buo na.' or (select report_id from public.mail_drafts where id = d1) <> r1 then raise exception 'draft not kept'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.mail_draft_save(d1, '{}', '{}', '{}', 'x', 'y', null, null); raise exception 'someone changed another person''s draft';
    exception when check_violation then null; end;
    perform public.mail_draft_delete(d1);
    if not exists (select 1 from public.mail_drafts where id = d1) then raise exception 'someone deleted another person''s draft'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.send_mail(array[v_sup], 'Sulat', 'Mas buo na.', r1, null, '{}', '{}', d1);
    if exists (select 1 from public.mail_drafts where id = d1) then raise exception 'a sent draft is still a draft'; end if;
    d2 := public.mail_draft_save(null, '{}', '{}', '{}', '', '', null, null);
    perform public.mail_draft_delete(d2);
    if exists (select 1 from public.mail_drafts where id = d2) then raise exception 'draft not deleted'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.mail_draft_save(null, '{}', '{}', '{}', 'x', 'y', null, null); raise exception 'a resident kept a draft';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  drafts are kept and changed by their owner only, removed when sent, and only an administrator has them';
  exception when others then v_log := v_log || E'\n' || 'FAIL drafts: ' || sqlerrm; end;

  -- 5. the case chats remember where each person was: read up to (never backwards), muted, pinned, put away; only for a case they can see
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.chat_state_set(r1, 'r', '2026-11-12 10:00+00', true, null, null);
    perform public.chat_state_set(r1, 'r', '2026-11-12 09:00+00', null, true, null);
    if (select seen_at from public.chat_state where user_id = v_kpo and report_id = r1 and conv = 'r') <> '2026-11-12 10:00+00' then raise exception 'reading went backwards'; end if;
    if not exists (select 1 from public.chat_state where user_id = v_kpo and report_id = r1 and conv = 'r' and muted and pinned) then raise exception 'mute and pin not kept together'; end if;
    perform public.chat_state_set(r1, 'd-' || gen_random_uuid(), null, null, null, true);
    begin perform public.chat_state_set(r1, 'someone', null, true, null, null); raise exception 'a made-up conversation was accepted';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.chat_state_set(r1, 'r', null, true, null, null); raise exception 'a case outside the committee was kept';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.chat_state_set(r1, 'r', null, true, null, null); raise exception 'a resident kept a chat state';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  chat state is kept per person and conversation, reading never goes backwards, and it needs a case the person can see';
  exception when others then v_log := v_log || E'\n' || 'FAIL chat state: ' || sqlerrm; end;

  -- 6. reading: as the API's own role, a person reads only their own marks, labels, drafts and chat state; signed out reads nothing
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_kpo, 'role', 'authenticated')::text, true);
    if (select count(*) from public.mail_state where user_id <> v_kpo) <> 0 or (select count(*) from public.mail_labels where user_id <> v_kpo) <> 0
       or (select count(*) from public.mail_drafts where user_id <> v_kpo) <> 0 or (select count(*) from public.chat_state where user_id <> v_kpo) <> 0
       or (select count(*) from public.mail_label_links where user_id <> v_kpo) <> 0 then raise exception 'a person reads another person''s marks'; end if;
    if (select count(*) from public.mail_state where user_id = v_kpo) = 0 or (select count(*) from public.chat_state where user_id = v_kpo) = 0 then raise exception 'a person cannot read their own marks'; end if;
    begin insert into public.mail_state (user_id, batch, starred) values (v_kpo, b1, true); raise exception 'a mark was written by hand';
    exception when insufficient_privilege then null; end;
    begin insert into public.mail_drafts (user_id, subject, body) values (v_kpo, 'x', 'y'); raise exception 'a draft was written by hand';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform count(*) from public.mail_state; raise exception 'signed out read the marks';
    exception when insufficient_privilege then null; end;
    begin perform public.mail_flag(array[b1], true, null, null, null, null, false); raise exception 'signed out called mail_flag';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a person reads only their own marks, labels, drafts and chat state, cannot write them by hand, and signed out reaches none of it';
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    v_log := v_log || E'\n' || 'FAIL reading: ' || sqlerrm;
  end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
