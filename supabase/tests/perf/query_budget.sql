-- Query time budget (item 23). Fills the database with a few years of a
-- busy barangay (2,000 residents, 30 tanods, 50,000 complaints with their
-- trails, 100,000 notifications), then times what the app and the portal
-- run most, each as the role that runs it, so row-level security is
-- included. Every query must finish within its budget on a warm cache.
-- Like the checks in supabase/tests it ends by raising, so nothing is kept;
-- run it with supabase/tests/local/run-local.sh (CI database job).
-- Found on its first run: tracking IDs broke at the 10,000th complaint
-- (fixed in 0120).
do $perf$
declare
  v_log   text := '';
  v_res   uuid;
  v_adm   uuid;
  r       record;
  t0      timestamptz;
  best    double precision;
  ms      double precision;
  n       integer;
begin
  -- ---------- volume ----------
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
         public.auth_email_for('+6399' || lpad(g::text, 8, '0')),
         jsonb_build_object('full_name', 'Perf, Resident ' || g, 'mobile_number', '+6399' || lpad(g::text, 8, '0'),
                            'role', case when g <= 30 then 'tanod' else 'resident' end, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'),
         now(), now()
    from generate_series(1, 2032) g;
  update public.users set verification_status = 'verified', verified_at = now() where full_name like 'Perf, %';
  select id into v_adm from public.users where full_name = 'Perf, Resident 2032';
  update public.users set role = 'admin' where id = v_adm;
  select id into v_res from public.users where full_name = 'Perf, Resident 100';

  -- History is loaded with SMART triage (0122) off: it scores new filings,
  -- and its own cost is timed below on top of this volume.
  alter table public.reports disable trigger reports_smart_triage;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude, status, created_at)
  select u.id,
         (array['street_obstruction','public_safety_infrastructure','environmental_waste_hazard','animal_welfare',
                'traffic_violation','barangay_service','peace_order_nuisance'])[1 + (g % 7)]::public.complaint_category,
         'Perf complaint ' || g, 'Generated for the query budget.',
         14.5165 + ((g * 37) % 100 - 50) / 20000.0, 121.0162 + ((g * 53) % 100 - 50) / 20000.0,
         (array['pending_review','validated','in_progress','resolved','closed','rejected'])[1 + (g % 6)]::public.report_status,
         now() - make_interval(hours => g % 26000)
    from generate_series(1, 50000) g
    join lateral (select id from public.users where full_name = 'Perf, Resident ' || (31 + g % 2000)) u on true;

  alter table public.reports enable trigger reports_smart_triage;
  perform public.smart_triage(id) from (select id from public.reports
     where status in ('pending_review', 'validated', 'in_progress') order by created_at desc limit 1000) x;

  insert into public.notifications (user_id, kind, message, is_read, created_at)
  select u.id, 'status_change', 'Perf notification ' || g, g % 3 <> 0, now() - make_interval(hours => g % 9000)
    from generate_series(1, 100000) g
    join lateral (select id from public.users where full_name = 'Perf, Resident ' || (31 + g % 2000)) u on true;

  analyze public.users; analyze public.reports; analyze public.status_logs; analyze public.notifications;
  select count(*) into n from public.reports;
  v_log := format('volume: %s users, %s reports, %s status log rows, %s notifications',
    (select count(*) from public.users), n, (select count(*) from public.status_logs), (select count(*) from public.notifications));

  -- ---------- the queries, timed ----------
  for r in select * from (values
    ('resident', 'resident: my reports, newest 20',
       $q$ select count(*) from (select id, tracking_id, status, created_at from public.reports
             where resident_id = :me order by created_at desc limit 20) x $q$, 50),
    ('resident', 'resident: my unread notifications',
       $q$ select count(*) from public.notifications where user_id = :me and not is_read $q$, 50),
    ('resident', 'resident: published incidents on the map',
       $q$ select count(*) from public.public_incidents() $q$, 100),
    ('admin', 'admin: cases waiting for review, newest 50',
       $q$ select count(*) from (select id from public.reports where status = 'pending_review'
             order by created_at desc limit 50) x $q$, 50),
    ('admin', 'admin: one case and its trail',
       $q$ select count(*) from public.status_logs where report_id =
             (select id from public.reports order by created_at desc limit 1) $q$, 50),
    ('admin', 'admin: dashboard, last 30 days',
       $q$ select public.dashboard_metrics(now() - interval '30 days', now(), null) $q$, 300),
    ('admin', 'admin: hotspots, last 90 days',
       $q$ select count(*) from public.report_hotspots(now() - interval '90 days', now(), null) $q$, 500),
    ('admin', 'admin: resident directory',
       $q$ select count(*) from public.account_directory('resident') $q$, 300),
    ('admin', 'admin: search reports by tracking id',
       $q$ select count(*) from public.reports where tracking_id = 'BRG-2026-0100' $q$, 50),
    ('resident', 'resident: file a report, SMART triage included',
       $q$ insert into public.reports (resident_id, category, subject, description, latitude, longitude)
           values (:me, 'public_safety_infrastructure', 'Sunog', 'May sunog sa kanto, may mga bata.', 14.5165, 121.0162) $q$, 150),
    ('admin', 'admin: SMART urgent and high queue, top 50',
       $q$ select count(*) from (select t.report_id from public.report_triage t
             where t.level in ('urgent', 'high') order by t.score desc, t.computed_at desc limit 50) x $q$, 50),
    ('admin', 'admin: SMART possible duplicates of a report',
       $q$ select count(*) from public.smart_duplicates((select report_id from public.report_triage
             order by computed_at desc limit 1)) $q$, 100),
    ('admin', 'admin: SMART recurring problems, 90 days (the watcher runs this every 5 min)',
       $q$ select count(*) from public.smart_patterns(90) $q$, 300),
    ('admin', 'admin: SMART calibration, 90 days',
       $q$ select count(*) from public.smart_calibration(90) $q$, 300),
    ('admin', 'admin: SMART case card (one call for the case page)',
       $q$ select public.smart_case_card((select report_id from public.report_triage order by computed_at desc limit 1)) $q$, 150),
    ('admin', 'admin: SMART dashboard tiles',
       $q$ select public.smart_summary() $q$, 300)
  ) as t(who, label, sql, budget_ms)
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', case when r.who = 'admin' then v_adm else v_res end, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', (case when r.who = 'admin' then v_adm else v_res end)::text, true);
    execute 'set local role authenticated';
    best := null;
    for i in 1..5 loop
      t0 := clock_timestamp();
      -- :me is the signed-in user's id as a value, the way the app sends
      -- it (.eq('resident_id', uid)), so the planner can use the index.
      execute replace(r.sql, ':me', quote_literal(case when r.who = 'admin' then v_adm else v_res end));
      ms := extract(epoch from clock_timestamp() - t0) * 1000;
      if i > 1 and (best is null or ms < best) then best := ms; end if;  -- first run warms the cache
    end loop;
    execute 'reset role';
    v_log := v_log || E'\n' || case when best <= r.budget_ms then 'ok  ' else 'FAIL ' end
          || format('%s: %s ms (budget %s)', r.label, round(best::numeric, 1), r.budget_ms);
  end loop;

  raise exception 'SWEEP-ROLLBACK%', E'\n' || v_log;
end $perf$;
