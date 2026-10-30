-- 38_backend_hardening.sql: retention, indexes, closed helpers, locks (0158). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_t1 uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  n integer; j jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999981', 'Hard, Super', 'resident'), (v_kpo, '+639999999982', 'Hard, Peace', 'resident'),
                 (v_t1, '+639999999983', 'Hard, Tanod', 'tanod'), (v_res, '+639999999984', 'Hard, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_t1, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  v_log := 'setup ok';

  -- 1. what is past its retention period goes; what is not stays; the audit trail is never touched
  begin
    insert into public.admin_punches (user_id, kind, at) values (v_kpo, 'in', now() - interval '400 days'), (v_kpo, 'in', now() - interval '10 days');
    insert into public.inbox_messages (sender, recipient, subject, body, created_at)
    values (v_sup, v_kpo, 'Luma', 'Luma na ito', now() - interval '800 days'), (v_sup, v_kpo, 'Bago', 'Bago ito', now() - interval '5 days');
    insert into public.attendance (tanod_id, duty_status, logged_at)
    values (v_t1, 'on_duty', now() - interval '400 days'), (v_t1, 'on_duty', now() - interval '3 days');
    select count(*) into n from public.status_logs;
    j := public.purge_old_records();
    if (select count(*) from public.admin_punches where user_id = v_kpo) <> 1 then raise exception 'punches: %', j; end if;
    if (select count(*) from public.inbox_messages where recipient = v_kpo) <> 1 or not exists (select 1 from public.inbox_messages where recipient = v_kpo and subject = 'Bago') then raise exception 'inbox: %', j; end if;
    if (select count(*) from public.attendance where tanod_id = v_t1) <> 1 then raise exception 'attendance: %', j; end if;
    if (select count(*) from public.status_logs) <> n then raise exception 'the audit trail was touched'; end if;
    update public.operational_settings set keep_punch_days = 7 where id = 1;
    perform public.purge_old_records();
    if exists (select 1 from public.admin_punches where user_id = v_kpo) then raise exception 'a shorter period was not followed'; end if;
    v_log := v_log || E'\n' || 'ok  records past their retention period are deleted and newer ones kept, the period follows the barangay''s setting, and the audit trail is never touched';
  exception when others then v_log := v_log || E'\n' || 'FAIL retention: ' || sqlerrm; end;

  -- 2. every foreign key has an index; the purge and the internal helpers are closed to callers who should not run them
  begin
    select count(*) into n from pg_constraint c
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey);
    if n > 0 then raise exception '% foreign keys without an index', n; end if;
    if has_function_privilege('anon', 'public._colour_clash(text, text)', 'execute') then raise exception 'anonymous callers run _colour_clash'; end if;
    if has_function_privilege('authenticated', 'public.purge_old_records()', 'execute') then raise exception 'anyone signed in can purge'; end if;
    v_log := v_log || E'\n' || 'ok  every foreign key has an index; anonymous callers cannot run the internal helpers, and nobody signed in can run the purge';
  exception when others then v_log := v_log || E'\n' || 'FAIL indexes: ' || sqlerrm; end;

  -- 3. forwarding locks the case it works on
  begin
    if position('for update' in pg_get_functiondef('public.forward_case(uuid, text, text, bigint)'::regprocedure)) = 0
       or position('for update' in pg_get_functiondef('public.flag_case_for_forward(uuid, text, text)'::regprocedure)) = 0 then
      raise exception 'a forwarding function does not lock the case'; end if;
    v_log := v_log || E'\n' || 'ok  forwarding and flagging lock the case they work on, so two at once cannot both pass';
  exception when others then v_log := v_log || E'\n' || 'FAIL lock: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
