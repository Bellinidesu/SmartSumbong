-- 36_dashboard_committees.sql: the Dashboard's super admin module (0156). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r1 uuid; r2 uuid; j jsonb; k jsonb; m json;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
  v_from timestamptz := date_trunc('month', now()); v_to timestamptz := date_trunc('month', now()) + interval '1 month';
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'Dash, Super'), (v_kpo, '+639999999962', 'Dash, Peace'), (v_res, '+639999999963', 'Dash, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, due_at)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi.', lat, lng, now() - interval '1 hour') returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Away', 'May nag-aaway sa kanto.', lat, lng + 0.001) returning id into r2;
  v_log := 'setup ok';

  -- 1. the committees' counts and "needs me" add up, and a case handed to the super admins counts as waiting to be placed
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.forward_case(r2, null, 'Saan ito?', null);
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.dashboard_committees(v_from);
    if (j -> 'needs_me' ->> 'to_place')::int < 1 then raise exception 'the handed-up case is not waiting to be placed: %', j -> 'needs_me'; end if;
    if (j -> 'needs_me' ->> 'overdue')::int < 1 then raise exception 'the overdue case is not counted'; end if;
    if (select sum((c ->> 'open')::int) from jsonb_array_elements(j -> 'committees') c) + (j -> 'none' ->> 'open')::int
       <> (j -> 'needs_me' ->> 'open')::int then raise exception 'the committees and "no committee" do not add up to the open cases'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  the committees and "no committee yet" add up to the open cases; a case handed up and an overdue one count as needing a super admin';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL committees: ' || sqlerrm; end;

  -- 2. the box beside the donut lists the same cases the donut counts
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    m := public.dashboard_metrics(v_from, v_to, null);
    k := public.dashboard_slice(v_from, v_to, 'status', 'overdue', 100);
    if (k ->> 'total')::int <> (m -> 'resolution_status' ->> 'overdue')::int then raise exception 'overdue: box % against donut %', k ->> 'total', m -> 'resolution_status' ->> 'overdue'; end if;
    if not exists (select 1 from jsonb_array_elements(k -> 'cases') c where (c ->> 'id')::uuid = r1) then raise exception 'the overdue case is not in the box'; end if;
    k := public.dashboard_slice(v_from, v_to, 'category', 'peace_order_nuisance', 100);
    if (k ->> 'total')::int < 2 then raise exception 'the category box missed a case'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  the box beside the donut lists the same cases the donut counts, by status or by category';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL slice: ' || sqlerrm; end;

  -- 3. the brain buttons get the month's facts
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.smart_chart_notes('received', v_from, v_to, null);
    if (j ->> 'total')::int < 2 or j -> 'top_category' ->> 'category' is null or j -> 'busiest_day' is null then raise exception 'received: %', j; end if;
    j := public.smart_chart_notes('efficiency', v_from, v_to, null);
    if j ? 'finished' is not true or (j ->> 'open_overdue')::int < 1 then raise exception 'efficiency: %', j; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  the brain buttons get the month''s facts for "Total reports received" and "Resolution efficiency"';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL notes: ' || sqlerrm; end;

  -- 4. notifications carry their case's committee; system alerts reach the super admins only
  begin
    perform public._notify_admins('System check: a scheduled job failed');
    if exists (select 1 from public.notifications where user_id = v_kpo and message = 'System check: a scheduled job failed') then raise exception 'a Kagawad got a system alert'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and message = 'System check: a scheduled job failed') then raise exception 'the super admin did not'; end if;
    insert into public.notifications (user_id, report_id, kind, message) values (v_sup, r1, 'status_change', 'About r1');
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    if (select public.notification_committee(n) from public.notifications n where n.user_id = v_sup and n.message = 'About r1') is distinct from 'peace_order' then
      raise exception 'the notification does not carry its committee'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a notification carries its case''s committee; system alerts reach the super admins and not a committee''s admins';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL notifications: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
