-- 55_reports_direct_writes.sql: reports are written only through the functions (0177, backend sweep). A signed-in resident's direct
-- insert may carry only what file_report writes; nobody signed in updates a report directly. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_res uuid := gen_random_uuid(); v_kag uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid();
  r public.reports; r1 uuid; i integer; s text;
  cols text[] := array['tracking_id', 'status', 'handler_id', 'committee', 'is_sensitive', 'assigned_to', 'created_at', 'resolved_at', 'deleted_at'];
  vals text[];
  sets text[];
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
  long_text constant text := 'This is a long enough description for the check on the length of a description.';
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999991', 'Direct, Ana'), (v_kag, '+639999999992', 'Direct, Kagawad'), (v_sup, '+639999999993', 'Direct, Super')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_kag, v_sup);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kag;
  vals := array[quote_literal('BRG-2026-0020'), quote_literal('validated'), quote_literal(v_kag), quote_literal('environment'), 'true',
                quote_literal(v_res), quote_literal('2020-01-01'), 'now()', 'now()'];

  -- 1. a resident's direct insert cannot choose the fields the system owns, one by one
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    for i in 1 .. array_length(cols, 1) loop
      begin
        execute format('insert into public.reports (resident_id, category, subject, description, latitude, longitude, %s) values (%L, %L, %L, %L, %s, %s, %s)',
                       cols[i], v_res, 'peace_order_nuisance', 'Forged ' || cols[i], long_text, lat, lng, vals[i]);
        raise exception 'a resident set % on a report by a direct insert', cols[i];
      exception when insufficient_privilege then null; end;
    end loop;
    reset role;
    v_log := v_log || E'\n' || 'ok  a resident cannot choose tracking id, status, handler, committee, sensitivity, assignment or dates by a direct insert';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL forged insert: ' || sqlerrm; end;

  -- 2. the columns filing uses still work, directly and through file_report; the system fills in the rest
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    insert into public.reports (resident_id, category, subject, description, latitude, longitude, is_anonymous)
    values (v_res, 'peace_order_nuisance', 'Videoke', long_text, lat, lng, false) returning * into r;
    if r.status <> 'pending_review' or r.handler_id is not null or r.assigned_to is not null or r.tracking_id is null then
      raise exception 'a plain insert did not start the way filing does: %, %', r.status, r.tracking_id;
    end if;
    r := public.file_report('peace_order_nuisance', 'Away sa kanto', long_text, lat + 0.001, lng, false, '[]'::jsonb, gen_random_uuid(), null, '[]'::jsonb);
    if r.status <> 'pending_review' or r.tracking_id is null then raise exception 'file_report no longer files'; end if;
    r1 := r.id;
    reset role;
    v_log := v_log || E'\n' || 'ok  filing still works (the allowed columns, and file_report), starting at pending review with a generated tracking id';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL filing: ' || sqlerrm; end;

  -- 3. the administrator who handles a case cannot patch it: category, resident, tracking id and status are the functions' to change
  begin
    sets := array['category = ' || quote_literal('environmental_waste_hazard'), 'resident_id = ' || quote_literal(v_sup),
                  'tracking_id = ' || quote_literal('BRG-HACK'), 'status = ' || quote_literal('closed'), 'subject = ' || quote_literal('edited')];
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kag::text, true);
    perform public.take_case(r1);
    foreach s in array sets loop
      begin
        execute format('update public.reports set %s where id = %L', s, r1);
        raise exception 'a handler patched a report: %', s;
      exception when insufficient_privilege then null; end;
    end loop;
    -- the functions still change it
    perform public.review_report(r1, 'validate');
    if (select status from public.reports where id = r1) <> 'validated' then raise exception 'review_report no longer validates'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  nobody signed in patches a report; the case functions still work for the handler';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL patching: ' || sqlerrm; end;

  -- 4. a super admin too: the functions are the only way; signed-out callers hold no write right at all
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin update public.reports set status = 'closed' where id = r1; raise exception 'a super admin patched a report';
    exception when insufficient_privilege then null; end;
    reset role;
    if has_table_privilege('anon', 'public.reports', 'insert') or has_table_privilege('anon', 'public.reports', 'update') then raise exception 'anon can write reports'; end if;
    v_log := v_log || E'\n' || 'ok  a super admin patches nothing either, and signed-out callers hold no write right on reports';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL super admin: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
