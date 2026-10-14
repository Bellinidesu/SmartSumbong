-- 13_three_briefings.sql: the afternoon and night briefings (0131). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_admin uuid; t text; n integer;
begin
  v_admin := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_admin, 'authenticated', 'authenticated', public.auth_email_for('+639999999941'),
          jsonb_build_object('full_name', 'Brief, Admin', 'mobile_number', '+639999999941', 'role', 'resident', 'id_type', 'barangay_id',
                             'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                             'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now());
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id = v_admin;
  v_log := 'setup ok';

  begin
    t := public._smart_briefing_text('afternoon');
    if t not like 'SMART afternoon check%' or t not like '%Since 6 AM%' then raise exception 'afternoon text: %', t; end if;
    t := public._smart_briefing_text('night');
    if t not like 'SMART day review%' or t not like '%Staying open overnight%' then raise exception 'night text: %', t; end if;
    t := public._smart_briefing_text('morning');
    if t not like 'SMART morning digest%' then raise exception 'morning text: %', t; end if;
    v_log := v_log || E'\n' || 'ok  the three briefings read as morning, afternoon and night';
  exception when others then v_log := v_log || E'\n' || 'FAIL texts: ' || sqlerrm; end;

  begin
    begin perform public._smart_briefing_text('noon'); raise exception 'accepted noon';
    exception when invalid_parameter_value then null; end;
    v_log := v_log || E'\n' || 'ok  an unknown period is refused';
  exception when others then v_log := v_log || E'\n' || 'FAIL unknown period: ' || sqlerrm; end;

  begin
    update public.smart_rules set digest_enabled = true where id = 1;
    perform public.smart_digest_send('afternoon');
    select count(*) into n from public.notifications where user_id = v_admin and message like 'SMART afternoon check%';
    if n <> 1 then raise exception 'sent % times', n; end if;
    update public.smart_rules set digest_enabled = false where id = 1;
    perform public.smart_digest_send('night');
    select count(*) into n from public.notifications where user_id = v_admin and message like 'SMART day review%';
    if n <> 0 then raise exception 'sent while off: %', n; end if;
    v_log := v_log || E'\n' || 'ok  a briefing reaches every administrator, and not while the digest switch is off';
  exception when others then v_log := v_log || E'\n' || 'FAIL send: ' || sqlerrm; end;

  begin
    select count(*) into n from cron.job where jobname in ('smart-morning-digest', 'smart-afternoon-digest', 'smart-night-digest');
    if n <> 3 then raise exception 'jobs %', n; end if;
    v_log := v_log || E'\n' || 'ok  all three briefings are scheduled';
  exception when others then v_log := v_log || E'\n' || 'FAIL schedule: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
