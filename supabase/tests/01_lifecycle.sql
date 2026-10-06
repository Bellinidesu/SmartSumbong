do $sweep$
declare
  v_log text := '';
  v_res uuid; v_res2 uuid; v_tan uuid; v_adm uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; r5 uuid; r6 uuid; r7 uuid;
  d1 uuid; d3 uuid; d6 uuid;
begin

  -- four throwaway accounts, through the real sign-up trigger
  v_res  := gen_random_uuid(); v_res2 := gen_random_uuid(); v_tan := gen_random_uuid(); v_adm := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from (values (v_res, '+639999999901', 'Sweep, Resident', 'resident'),
                 (v_res2, '+639999999902', 'Sweep, Neighbour', 'resident'),
                 (v_tan, '+639999999903', 'Sweep, Tanod', 'tanod'),
                 (v_adm, '+639999999904', 'Sweep, Admin', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_res2, v_tan, v_adm);
  update public.users set role = 'admin' where id = v_adm;
  update public.users set duty_status = 'on_duty', last_geom = st_setsrid(st_makepoint(121.0155, 14.5269), 4326), last_location_at = now() where id = v_tan;
  v_log := 'setup ok: 4 accounts';

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    if not (current_user = 'authenticated' and auth.uid() = v_res) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  role switch works (acting as the resident, not postgres)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL role switch works (acting as the resident, not postgres): ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r1', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r1 from public.reports where resident_id = v_res and subject = 'Sweep test r1';
    if r1 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r1' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r1: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    if not (exists (select 1 from public.reports where id = r1)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident reads own report' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident reads own report: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    if not (not exists (select 1 from public.reports where id = r1)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  other resident cannot read it (RLS)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL other resident cannot read it (RLS): ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    if not (not exists (select 1 from public.reports where id = r1)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod cannot read it before dispatch (RLS)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod cannot read it before dispatch (RLS): ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r1, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot validate own report' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  resident cannot validate own report (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r1, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin validates' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin validates: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_dispatch(r1, v_tan, 'Check the sidewalk');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD dispatch refused without a target date' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  dispatch refused without a target date (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r1, now() + interval '2 days');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin sets target date' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin sets target date: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    if not (exists (select 1 from public.tanod_roster(r1) t where t.tanod_id = v_tan and t.assignable)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod roster lists the tanod as assignable' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod roster lists the tanod as assignable: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_dispatch(r1, v_tan, 'Check the sidewalk');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin dispatches' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin dispatches: ' || left(sqlerrm, 220);
  end;
  begin
        select id into d1 from public.dispatches where report_id = r1 and state in ('assigned','accepted') order by assigned_at desc limit 1; if d1 is null then raise exception 'no live dispatch'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  d1 found' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL d1 found: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    if not (exists (select 1 from public.reports where id = r1)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod now reads the report' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod now reads the report: ' || left(sqlerrm, 220);
  end;
  begin
        if not (exists (select 1 from public.notifications where user_id = v_tan and report_id = r1)) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod got an assignment notification' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod got an assignment notification: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.accept_dispatch(d1);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod accepts' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod accepts: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r1) = 'in_progress') then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  report is in progress after accept' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL report is in progress after accept: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.set_dispatch_step(d1, 'on_the_way');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod: on the way' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod: on the way: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.set_dispatch_step(d1, 'arrived');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod: arrived' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod: arrived: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.post_dispatch_update(d1, 'Owner is moving the cart.', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/dispatch/aaaaaaaa-1111-4111-8111-111111111111.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod posts an update with a photo' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod posts an update with a photo: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.post_dispatch_update(d1, 'x', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/aaaaaaaa-1111-4111-8111-111111111112.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD tanod photo outside the pinned folder refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  tanod photo outside the pinned folder refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.post_dispatch_update(d1, 'Thanks, take a photo after.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin replies in the dispatch thread' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin replies in the dispatch thread: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.request_additional_details(r1, 'Which store exactly?');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin asks the resident for details' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin asks the resident for details: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.submit_additional_details((select id from public.detail_requests where report_id = r1 and responded_at is null limit 1), 'The one beside the bakery.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident answers the details request' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident answers the details request: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.post_report_message(r1, 'Any news?');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident asks the barangay' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident asks the barangay: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.post_report_message(r1, 'A tanod is there now.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin answers the resident' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin answers the resident: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.submit_field_report(d1, 'Cart moved, sidewalk clear.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod resolves (field report)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod resolves (field report): ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r1) = 'in_progress' and (select resolution_submitted_at from public.reports where id = r1) is not null) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resolution waits for approval (still in progress)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resolution waits for approval (still in progress): ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.reject_resolution(r1, 'Please attach a photo.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin returns the resolution' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin returns the resolution: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.submit_field_report((select id from public.dispatches where report_id = r1 order by assigned_at desc limit 1), 'Photo attached this time.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod resolves again' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod resolves again: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.approve_resolution(r1);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin approves the resolution' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin approves the resolution: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r1) = 'resolved') then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  report is resolved' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL report is resolved: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    insert into public.feedback (report_id, resident_id, rating, comment) values (r1, v_res, 5, 'Fast.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident rates it' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident rates it: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    insert into public.feedback (report_id, resident_id, rating, comment) values (r1, v_res, 1, 'Again');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD second rating refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  second rating refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    insert into public.feedback (report_id, resident_id, rating) values (r1, v_res2, 1);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD other resident cannot rate it' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  other resident cannot rate it (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_reopen(r1, 'The cart came back.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident requests reopening' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident requests reopening: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.reopen_report(r1, 'Confirmed on site.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin reopens' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin reopens: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r1) not in ('resolved','closed')) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  reopened report is back with the barangay' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL reopened report is back with the barangay: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_report_public(r1, true);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin publishes it to the residents map' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin publishes it to the residents map: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    if not (exists (select 1 from public.public_incidents())) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  residents map lists it' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL residents map lists it: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    if not ((select bool_and(intact) and count(*) > 10 from public.verify_report_trail(r1))) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r1 trail (30+ entries, many in one transaction) fully intact' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r1 trail (30+ entries, many in one transaction) fully intact: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    if not ((select bool_and(intact) from public.verify_report_trail(r1))) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident may verify own trail' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident may verify own trail: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.verify_report_trail(r1);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD other resident may not verify it' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  other resident may not verify it (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    if not ((select count(*) from public.notifications where report_id = r1) >= 3) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident sees notifications for it' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident sees notifications for it: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r2', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r2 from public.reports where resident_id = v_res and subject = 'Sweep test r2';
    if r2 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r2' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r2: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r2, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin validates r2' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin validates r2: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '1 day');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin sets r2 target' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin sets r2 target: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '2 days');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD extension without a reason refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  extension without a reason refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '2 days', 'Owner away until Monday');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  extension 1 with a reason' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL extension 1 with a reason: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '3 days', 'Waiting for the city crew');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  extension 2 with a reason' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL extension 2 with a reason: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '4 days', 'One more week please');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD extension 3 refused (cap 2)' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  extension 3 refused (cap 2) (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
        if not ((select count(*) from public.sla_extensions where report_id = r2) = 2) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  extensions recorded in sla_extensions' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL extensions recorded in sla_extensions: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.hand_to_higher_official(r2, 'Punong Barangay');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot hand a case up' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  resident cannot hand a case up (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.hand_to_higher_official(r2, 'Punong Barangay', 'For mediation.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin hands r2 to a higher official' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin hands r2 to a higher official: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select higher_official from public.reports where id = r2) = 'Punong Barangay' and (select status from public.reports where id = r2) = 'in_progress') then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r2 handled by the official, still open' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r2 handled by the official, still open: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r2, now() + interval '5 days', 'New official needs time');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  fresh extension after the hand-up' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL fresh extension after the hand-up: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_barangay_update(r2, 'Talked to the owner.', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/barangay/bbbbbbbb-2222-4222-8222-222222222222.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin posts an update with a photo, no tanod' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin posts an update with a photo, no tanod: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_barangay_update(r2, 'x', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/reports/bbbbbbbb-2222-4222-8222-222222222223.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD admin photo outside the barangay folder refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  admin photo outside the barangay folder refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_barangay_update(r2, '  ');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD empty update refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  empty update refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_set_status(r2, 'resolved', 'Cleared by the barangay.', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/barangay/bbbbbbbb-2222-4222-8222-222222222224.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin resolves r2 with proof photos' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin resolves r2 with proof photos: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    if not ((select count(*) from public.report_evidence where report_id = r2) = 2) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident sees both barangay photos' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident sees both barangay photos: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    if not ((select count(*) from public.report_evidence where report_id = r2) = 0) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  other resident sees none' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL other resident sees none: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    insert into public.report_evidence (report_id, posted_by, kind, media_url, mime_type, bytes) values (r2, v_res, 'update', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/barangay/bbbbbbbb-2222-4222-8222-222222222225.jpg', 'image/jpeg', 10);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD resident cannot insert evidence directly' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  resident cannot insert evidence directly (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('peace_order_nuisance', 'Sweep test r3', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r3 from public.reports where resident_id = v_res and subject = 'Sweep test r3';
    if r3 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r3' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r3: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r3, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin validates r3' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin validates r3: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r3, now() + interval '1 day');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin sets r3 target' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin sets r3 target: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_dispatch(r3, v_tan, 'Talk to both sides');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin dispatches r3' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin dispatches r3: ' || left(sqlerrm, 220);
  end;
  begin
        select id into d3 from public.dispatches where report_id = r3 and state in ('assigned','accepted') order by assigned_at desc limit 1; if d3 is null then raise exception 'no live dispatch'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  d3 found' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL d3 found: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.accept_dispatch(d3);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod accepts r3' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod accepts r3: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.request_escalation(d3, 'Domestic dispute, needs VAWC', 'VAWC Desk');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod requests escalation' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod requests escalation: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.approve_escalation((select id from public.escalation_requests where report_id = r3 and status = 'pending' limit 1), 'VAWC Desk', 'Bring an ID.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin approves the escalation' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin approves the escalation: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select referred_to from public.reports where id = r3) is not null) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r3 referred out' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r3 referred out: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r4', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r4 from public.reports where resident_id = v_res and subject = 'Sweep test r4';
    if r4 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r4' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r4: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r4, 'reject', 'Outside the barangay.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin rejects r4' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin rejects r4: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_appeal(r4, 'It is inside, near the chapel.', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/dispatch/cccccccc-3333-4333-8333-333333333333.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD appeal photo from the tanod folder refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  appeal photo from the tanod folder refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.request_appeal(r4, 'It is inside, near the chapel.', jsonb_build_array(jsonb_build_object('media_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/reports/cccccccc-3333-4333-8333-333333333334.jpg', 'mime_type', 'image/jpeg', 'bytes', 1000)));
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident appeals with a photo' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident appeals with a photo: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.appeal_report(r4, 'Checked the map.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin grants the appeal' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin grants the appeal: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r4) = 'validated') then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r4 back to validated' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r4 back to validated: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r5', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r5 from public.reports where resident_id = v_res and subject = 'Sweep test r5';
    if r5 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r5' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r5: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res2::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res2::text, true);
    execute 'set local role authenticated';
    perform public.cancel_report(r5);
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD other resident cannot cancel it' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  other resident cannot cancel it (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.cancel_report(r5, 'Sorted it out myself.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident cancels r5' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident cancels r5: ' || left(sqlerrm, 220);
  end;
  begin
        if not ((select status from public.reports where id = r5) = 'cancelled') then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r5 cancelled' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r5 cancelled: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r6', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r6 from public.reports where resident_id = v_res and subject = 'Sweep test r6';
    if r6 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r6' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r6: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r6, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin validates r6' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin validates r6: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.set_resolution_target(r6, now() + interval '1 day');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin sets r6 target' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin sets r6 target: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.admin_dispatch(r6, v_tan, 'Check it');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin dispatches r6' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin dispatches r6: ' || left(sqlerrm, 220);
  end;
  begin
        select id into d6 from public.dispatches where report_id = r6 and state in ('assigned','accepted') order by assigned_at desc limit 1; if d6 is null then raise exception 'no live dispatch'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  d6 found' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL d6 found: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.reroute_dispatch(d6, 'On another call.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod hands r6 back' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod hands r6 back: ' || left(sqlerrm, 220);
  end;
  begin
        if not (not exists (select 1 from public.dispatches where id = d6 and state in ('assigned','accepted'))) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r6 dispatch no longer live for the tanod' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r6 dispatch no longer live for the tanod: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.file_report('street_obstruction', 'Sweep test r7', 'Automated sweep, rolled back.', 14.5269, 121.0155, false, '[]'::jsonb, gen_random_uuid());
    execute 'reset role';
    select id into r7 from public.reports where resident_id = v_res and subject = 'Sweep test r7';
    if r7 is null then raise exception 'no report row'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident files r7' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident files r7: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.review_report(r7, 'validate');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin validates r7' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin validates r7: ' || left(sqlerrm, 220);
  end;
  begin
        update public.reports set due_at = now() - interval '1 hour' where id = r7;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  r7 made overdue' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL r7 made overdue: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.follow_up_report(r7, 'Still there.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  resident follows up on the overdue case' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL resident follows up on the overdue case: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_res::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    execute 'set local role authenticated';
    perform public.follow_up_report(r7, 'Again.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'BAD second follow-up the same day refused' || ' (should have been refused)' || '';
  exception when others then
    v_log := v_log || E'\n' || 'ok  second follow-up the same day refused (refused: ' || left(sqlerrm, 120) || ')';
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.refer_report(r7, 'PNP', 'Police matter.');
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  admin escalates r7 directly' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL admin escalates r7 directly: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.dashboard_metrics(now() - interval '30 days', now());
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  dashboard figures' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL dashboard figures: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    execute 'set local role authenticated';
    perform public.report_hotspots(now() - interval '30 days', now());
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  hotspots' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL hotspots: ' || left(sqlerrm, 220);
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_tan::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tan::text, true);
    execute 'set local role authenticated';
    perform public.update_my_location(14.5269, 121.0155);
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  tanod reports a location' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL tanod reports a location: ' || left(sqlerrm, 220);
  end;
  begin
        perform public.sweep_overdue_verifications();
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  sweep: overdue verifications' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL sweep: overdue verifications: ' || left(sqlerrm, 220);
  end;
  begin
        perform public.sweep_unaccepted_dispatches();
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  sweep: unaccepted dispatches' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL sweep: unaccepted dispatches: ' || left(sqlerrm, 220);
  end;
  begin
        perform public.sweep_awaiting_units();
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  sweep: awaiting units' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL sweep: awaiting units: ' || left(sqlerrm, 220);
  end;
  begin
        perform public.sweep_overdue_reports();
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  sweep: overdue reports' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL sweep: overdue reports: ' || left(sqlerrm, 220);
  end;
  begin
        if not (exists (select 1 from pg_proc where proname = 'my_status_log_authors')) then raise exception 'condition false'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  timeline bylines function exists (my_status_log_authors)' ||  '';
  exception when others then
    v_log := v_log || E'\n' || 'FAIL timeline bylines function exists (my_status_log_authors): ' || left(sqlerrm, 220);
  end;
  raise exception 'SWEEP-ROLLBACK%', v_log;
end
$sweep$;
