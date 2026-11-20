-- 63_barangay_notices.sql: barangay notices (0185, 20 Nov 2026). Rolled back.
-- The writing checks run as the API's own role ("authenticated"), where row level security and the function guards apply.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_cap uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); v_ben uuid := gen_random_uuid(); v_sus uuid := gen_random_uuid(); v_new uuid := gen_random_uuid();
  r1 uuid; r2 uuid; n1 uuid; n2 uuid; n3 uuid; n4 uuid; p jsonb; c integer; c2 integer; expect integer; s text; keys text[];
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999911', 'Notice, Super'), (v_kpo, '+639999999912', 'Notice, Peace'), (v_kenv, '+639999999913', 'Notice, Env'),
                 (v_stf, '+639999999914', 'Notice, Staff'), (v_cap, '+639999999915', 'Notice, Captain'), (v_ana, '+639999999916', 'Notice, Ana'),
                 (v_ben, '+639999999917', 'Notice, Ben'), (v_sus, '+639999999918', 'Notice, Suspended'), (v_new, '+639999999919', 'Notice, Unverified')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_cap, v_ana, v_ben, v_sus);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'captain' where id = v_cap;
  update public.users set is_suspended = true where id = v_sus;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto, gabi-gabi.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Pananakit', 'May nananakit sa bahay na ito gabi-gabi.', lat + 0.001, lng) returning id into r2;
  update public.reports set is_sensitive = true where id = r2;
  select count(*) into expect from public.users u
   where u.role = 'resident' and u.verification_status = 'verified' and not u.is_suspended and u.removed_at is null and not coalesce(u.is_test, false);

  -- 1. a super admin publishes: one notification for each verified, active resident (not the suspended or unverified, not the administrators), the headline as its words
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    n1 := public.publish_notice('Road closed on 9th Street', 'The road is closed for the water pipe repair until 5 PM. Please use Andrews Avenue.', 'street_obstruction', 14.5201, 121.0115, 250, '9th Street', null, 'ref-sup-0001');
    reset role;
    select count(*) into c from public.notifications where notice_id = n1 and kind = 'notice';
    if c <> expect or c < 2 then raise exception 'told % residents, expected % (at least the two)', c, expect; end if;
    if (select notified_count from public.notices where id = n1) <> expect then raise exception 'the count is not kept'; end if;
    if exists (select 1 from public.notifications where notice_id = n1 and user_id in (v_sus, v_new, v_sup, v_kpo, v_stf)) then raise exception 'told someone who should not be'; end if;
    if not exists (select 1 from public.notifications where notice_id = n1 and user_id = v_ana and message = 'Road closed on 9th Street' and report_id is null and not is_read) then raise exception 'Ana was not told in the headline'; end if;
    if (select count(*) from public.notice_log where notice_id = n1 and action = 'publish' and actor = v_sup) <> 1 then raise exception 'no log line'; end if;
    v_log := v_log || E'\n' || 'ok  a super admin publishes: one notification per verified active resident (not the suspended, unverified or administrators), the headline as its words, one log line';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL publish: ' || sqlerrm; end;

  -- 2. the same reference is the same notice: nothing new is made or sent
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    n2 := public.publish_notice('Road closed on 9th Street', 'The road is closed for the water pipe repair until 5 PM. Please use Andrews Avenue.', 'street_obstruction', 14.5201, 121.0115, 250, '9th Street', null, 'ref-sup-0001');
    reset role;
    if n2 <> n1 then raise exception 'a second id'; end if;
    if (select count(*) from public.notices where created_by = v_sup) <> 1 or (select count(*) from public.notifications where notice_id = n1) <> expect then raise exception 'a repeat made more'; end if;
    v_log := v_log || E'\n' || 'ok  the same reference gives the same notice and sends nothing more';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL repeat: ' || sqlerrm; end;

  -- 3. who may publish: a Kagawad for their committee's categories only (and must choose one), not staff, the view-only captain, or a resident
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    n3 := public.publish_notice('Barangay assembly tonight', 'Peace and order committee meeting at the hall at 7 PM. All are welcome.', 'peace_order_nuisance', null, null, null, null, null, 'ref-kpo-0001');
    begin perform public.publish_notice('Wrong committee', 'This is the environment committee''s category, not ours.', 'environmental_waste_hazard', null, null, null, null, null, 'ref-kpo-0002');
      raise exception 'a Kagawad published for another committee';
    exception when insufficient_privilege then null; end;
    begin perform public.publish_notice('No category given', 'A Kagawad must choose a category of their own committee.', null, null, null, null, null, null, 'ref-kpo-0003');
      raise exception 'a Kagawad published with no category';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform public.publish_notice('Staff cannot publish', 'Staff ask their Kagawad to publish a notice for the barangay.', 'peace_order_nuisance', null, null, null, null, null, 'ref-stf-0001');
      raise exception 'staff published';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_cap::text, true);
    begin perform public.publish_notice('Captain only reads', 'The view-only captain tier changes nothing in the system.', null, null, null, null, null, null, 'ref-cap-0001');
      raise exception 'the captain published';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    begin perform public.publish_notice('A resident tries', 'Residents read notices; they cannot publish one at all.', null, null, null, null, null, null, 'ref-ana-0001');
      raise exception 'a resident published';
    exception when insufficient_privilege then null; end;
    reset role;
    if (select count(*) from public.notices) <> 2 then raise exception 'a refused call still made a notice'; end if;
    v_log := v_log || E'\n' || 'ok  a Kagawad publishes for their own committee''s category only (and must choose one); staff, the captain tier and residents are refused and nothing is made';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  -- 4. nobody writes the tables by hand, whatever their rung
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin insert into public.notices (headline, message) values ('Sneaky headline', 'A direct insert is not allowed here.'); raise exception 'insert';
    exception when insufficient_privilege then null; end;
    begin update public.notices set headline = 'Changed by hand'; raise exception 'update';
    exception when insufficient_privilege then null; end;
    begin delete from public.notices; raise exception 'delete';
    exception when insufficient_privilege then null; end;
    begin insert into public.notice_log (notice_id, action) values (n1, 'edit'); raise exception 'log insert';
    exception when insufficient_privilege then null; end;
    begin delete from public.notice_log; raise exception 'log delete';
    exception when insufficient_privilege then null; end;
    reset role;
    if has_table_privilege('anon', 'public.notices', 'select') or has_function_privilege('anon', 'public.notices_for_residents()', 'execute')
       or has_function_privilege('anon', 'public.publish_notice(text, text, public.complaint_category, double precision, double precision, integer, text, uuid, text)', 'execute') then
      raise exception 'the signed-out role reaches notices';
    end if;
    v_log := v_log || E'\n' || 'ok  nobody inserts, edits or deletes a notice or its log by hand, a super admin included; the signed-out role reaches nothing';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL hand: ' || sqlerrm; end;

  -- 5. what a resident reads: the notice's own words, place and status, and no author, no report, no counts
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_ben::text, true);
    if (select count(*) from public.notices_for_residents()) <> 2 then raise exception 'a resident does not read both notices'; end if;
    select array_agg(k order by k collate "C") into keys from jsonb_object_keys((select to_jsonb(x) from public.notices_for_residents() x limit 1)) k;
    if keys <> array['category','created_at','headline','id','latitude','longitude','message','place_label','radius_m','resolved_at','status','updated_at'] then
      raise exception 'a resident reads the columns %', keys;
    end if;
    if exists (select 1 from public.notices) or exists (select 1 from public.notice_log) then raise exception 'a resident reads the table directly'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a resident reads the notice''s headline, message, category, place, status and times, and nothing else (no author, report, count), and cannot read the tables';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL read: ' || sqlerrm; end;

  -- 6. from a case: its category and a place rounded to about 100 m, never a sensitive case, one active notice per case, the report id never shown
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    n4 := public.publish_notice('Loud karaoke reminder', 'Please keep the volume down after 10 PM. Thank you for being a good neighbour.', null, null, null, null, null, r1, 'ref-sup-0002');
    if (select category from public.notices where id = n4) <> 'peace_order_nuisance' then raise exception 'category not taken from the case'; end if;
    if (select latitude from public.notices where id = n4) <> round(lat::numeric, 3)::double precision then raise exception 'place not rounded'; end if;
    begin perform public.publish_notice('Duplicate of the case', 'The same case cannot be an active notice twice over.', null, null, null, null, null, r1, 'ref-sup-0003');
      raise exception 'a case became two notices';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A sensitive case', 'A sensitive case is never the source of a notice at all.', null, null, null, null, null, r2, 'ref-sup-0004');
      raise exception 'a sensitive case became a notice';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.publish_notice('Not their case', 'The environment Kagawad cannot publish from a peace and order case.', 'environmental_waste_hazard', null, null, null, null, r1, 'ref-ken-0001');
      raise exception 'a Kagawad published from a case outside the committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_ben::text, true);
    if exists (select 1 from public.notices_for_residents() x where to_jsonb(x) ? 'source_report_id') then raise exception 'the report id is shown'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  from a case: its category and a place rounded to about 100 m; a sensitive case, a second active notice for one case and a case outside the committee are refused';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL source: ' || sqlerrm; end;

  -- 7. words and place are checked and tidied
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin perform public.publish_notice('Hi', 'A headline under four characters is not allowed.', null, null, null, null, null, null, 'ref-bad-0001'); raise exception 'short headline';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', 'short', null, null, null, null, null, null, 'ref-bad-0002'); raise exception 'short message';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', repeat('x', 601), null, null, null, null, null, null, 'ref-bad-0003'); raise exception 'long message';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', 'A message that is long enough to pass.', null, 14.5, null, null, null, null, 'ref-bad-0004'); raise exception 'half a point';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', 'A message that is long enough to pass.', null, 40.0, 10.0, null, null, null, 'ref-bad-0005'); raise exception 'abroad';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', 'A message that is long enough to pass.', null, null, null, 500, null, null, 'ref-bad-0006'); raise exception 'a radius with no point';
    exception when check_violation then null; end;
    begin perform public.publish_notice('A fine headline', 'A message that is long enough to pass.', null, null, null, null, null, null, 'x'); raise exception 'a short reference';
    exception when check_violation then null; end;
    if (select count(*) from public.notices) <> 3 then raise exception 'a refused call made a notice'; end if;
    perform public.edit_notice(n4, E'  Loud   karaoke\treminder  ', E'Please keep the volume down\r\n\r\n\r\n\r\nafter 10 PM, thank you.', 'peace_order_nuisance', null, null, null, null);
    if (select headline from public.notices where id = n4) <> 'Loud karaoke reminder' or (select message from public.notices where id = n4) <> E'Please keep the volume down\n\nafter 10 PM, thank you.' then
      raise exception 'the text was not tidied: %', (select headline || '|' || message from public.notices where id = n4);
    end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  headline 4-90, message 10-600, a whole point inside the Philippines, a reach only around a point, a usable reference: refused otherwise; spaces and blank lines tidied';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL words: ' || sqlerrm; end;

  -- 8. editing and resolving send nothing; resolved ones stay readable; another committee cannot touch a notice; a withdrawn one leaves the map and the reason is kept
  begin
    select count(*) into c from public.notifications where kind = 'notice';
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.edit_notice(n3, 'Barangay assembly moved', 'The peace and order committee meeting is moved to 8 PM at the hall.', 'peace_order_nuisance', null, null, null, null);
    begin perform public.edit_notice(n3, 'Moved to another category', 'A Kagawad cannot hand a notice to another committee.', 'environmental_waste_hazard', null, null, null, null);
      raise exception 'a notice moved to another committee';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.resolve_notice(n3); raise exception 'another committee resolved it';
    exception when insufficient_privilege then null; end;
    begin perform public.withdraw_notice(n3, 'Not theirs to withdraw'); raise exception 'another committee withdrew it';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.resolve_notice(n3);
    perform public.resolve_notice(n3);   -- again: nothing happens
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin perform public.withdraw_notice(n4, ' '); raise exception 'withdrawn with no reason';
    exception when check_violation then null; end;
    perform public.withdraw_notice(n4, 'Posted by mistake, the noise stopped');
    perform set_config('request.jwt.claim.sub', v_ben::text, true);
    if (select status from public.notices_for_residents() where id = n3) <> 'resolved' then raise exception 'a resolved notice is not read as resolved'; end if;
    if exists (select 1 from public.notices_for_residents() where id = n4) then raise exception 'a withdrawn notice is still on the map'; end if;
    if (select count(*) from public.notices_for_residents()) <> 2 or (select id from public.notices_for_residents() limit 1) <> n1 then raise exception 'the active notice does not come first'; end if;
    reset role;
    if (select count(*) from public.notifications where kind = 'notice') <> c then raise exception 'an edit, resolve or withdraw sent a notification'; end if;
    if (select count(*) from public.notice_log where notice_id = n3) <> 3 or (select count(*) from public.notice_log where notice_id = n4 and action = 'withdraw' and detail like 'Posted by mistake%') <> 1 then
      raise exception 'the log is not right'; end if;
    update public.notices set resolved_at = now() - interval '91 days' where id = n3;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_ben::text, true);
    if exists (select 1 from public.notices_for_residents() where id = n3) then raise exception 'a notice resolved 91 days ago is still listed'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  edit, resolve and withdraw send nothing; resolved notices stay readable for 90 days, withdrawn ones leave the map; another committee cannot edit, resolve or withdraw; the log keeps who and why';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL manage: ' || sqlerrm; end;

  -- 9. administrators read what they manage: a Kagawad only their committee's, the captain and a super admin all, staff are refused
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if exists (select 1 from public.notices_admin_list()) or exists (select 1 from public.notices) or exists (select 1 from public.notice_log) then raise exception 'the environment Kagawad reads another committee''s notices'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if (select count(*) from public.notices_admin_list()) <> 2 or (select count(*) from public.notice_log) < 3 then raise exception 'the Kagawad does not read their own'; end if;
    perform set_config('request.jwt.claim.sub', v_cap::text, true);
    if (select count(*) from public.notices_admin_list()) <> 3 or (select can_manage from public.notices_admin_list() limit 1) then raise exception 'the captain reads all and manages none'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if (select count(*) from public.notices_admin_list()) <> 3 or (select count(*) from public.notices_admin_list('active')) <> 1 then raise exception 'the super admin reads all'; end if;
    if not exists (select 1 from public.notices_admin_list() where id = n4 and source_tracking_id is not null and author = 'Notice, Super' and withdrawn_at is not null) then raise exception 'the list lacks the author, case or withdrawn mark'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    begin perform * from public.notices_admin_list(); raise exception 'staff read the list';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    begin perform * from public.notices_admin_list(); raise exception 'a resident read the list';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a Kagawad reads and manages only their committee''s notices, the captain reads all and manages none, a super admin reads all with author and case; staff and residents are refused';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL list: ' || sqlerrm; end;

  -- 10. the push: a notice goes to residents who have not muted the kind, carries its notice id, and a resolved one is not buzzed late
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_ben::text, true);
    perform public.set_notification_mute('notice', true);
    reset role;
    p := public.push_plan((select id from public.notifications where notice_id = n1 and user_id = v_ben));
    if (p ->> 'send')::boolean or p ->> 'why' <> 'muted' then raise exception 'a muted resident would be buzzed: %', p; end if;
    p := public.push_plan((select id from public.notifications where notice_id = n1 and user_id = v_ana));
    if not (p ->> 'send')::boolean or p -> 'record' ->> 'notice_id' <> n1::text or p -> 'record' ->> 'kind' <> 'notice' then raise exception 'Ana would not be buzzed, or the notice id is missing: %', p; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.resolve_notice(n1);
    reset role;
    p := public.push_plan((select id from public.notifications where notice_id = n1 and user_id = v_ana));
    if (p ->> 'send')::boolean or p ->> 'why' <> 'notice no longer active' then raise exception 'a resolved notice is still pushed: %', p; end if;
    -- the in-app row stays for a resident who muted it
    if not exists (select 1 from public.notifications where notice_id = n1 and user_id = v_ben) then raise exception 'muting removed the row'; end if;
    v_log := v_log || E'\n' || 'ok  push: a resident who muted notices is not buzzed (the inbox row stays), others are, the plan carries the notice id, and a notice resolved before its push goes out is held';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL push: ' || sqlerrm; end;

  -- 11. flood guards: 5 an hour for one administrator (a sixth is refused, with a message that says so), 20 a day for the barangay
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    -- the super admin has made two (n1, n4); three more fill the hour
    for i in 1..3 loop
      perform public.publish_notice('Flood check number ' || i, 'One of five notices an administrator may publish in an hour.', null, null, null, null, null, null, 'ref-flood-000' || i);
    end loop;
    begin perform public.publish_notice('The sixth one', 'This one is over the hour''s limit and must be refused.', null, null, null, null, null, null, 'ref-flood-0009');
      raise exception 'a sixth notice in an hour';
    exception when check_violation then get stacked diagnostics s = message_text; if s not like 'Slow down%' then raise exception 'the refusal says: %', s; end if; end;
    reset role;
    -- the barangay's day: make it twenty with other authors' notices, then a Kagawad is refused too
    insert into public.notices (headline, message, created_by, created_at)
    select 'Filler ' || g, 'A filler notice to reach the barangay''s limit.', v_kenv, now() - interval '2 hours' from generate_series(1, 20 - (select count(*) from public.notices where created_at > now() - interval '24 hours')::int) g;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    begin perform public.publish_notice('Over the day', 'The barangay has reached its limit for the day.', 'peace_order_nuisance', null, null, null, null, null, 'ref-day-0001');
      raise exception 'a twenty-first notice in a day';
    exception when check_violation then get stacked diagnostics s = message_text; if s not like 'Slow down%day%' then raise exception 'the refusal says: %', s; end if; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  flood guards: five an hour for one administrator and twenty a day for the barangay are refused with a "Slow down" message; nothing is made past them';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL flood: ' || sqlerrm; end;

  -- 12. the old way is untouched: set_report_public and public_incidents still work
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.set_report_public(r1, true);
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    if not exists (select 1 from public.public_incidents() where id = r1) then raise exception 'public_incidents lost a published case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  the published-incident toggle and public_incidents() still work as before';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL old: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
