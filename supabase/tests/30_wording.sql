-- 30_wording.sql: the barangay's own wording (0149). Rolled back.
-- Run as the API's own roles ("anon", "authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_com uuid := gen_random_uuid();
  n integer; v text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999951', 'Wording, Super', 'resident'), (v_com, '+639999999952', 'Wording, Committee', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id in (v_sup, v_com);
  update public.users set admin_tier = 'super' where id = v_sup;
  update public.users set admin_tier = 'committee', committee = 'peace_order' where id = v_com;
  v_log := 'setup ok';

  -- 1. a super admin rewords a label, then puts the code's own back; a committee admin cannot
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    begin insert into public.wording (source, fil) values ('Case Reports', 'Mga Kaso'); raise exception 'a committee admin reworded a label';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    insert into public.wording (source, en, fil) values ('Case Reports', 'Complaints', 'Mga Sumbong');
    update public.wording set fil = 'Mga Reklamo' where source = 'Case Reports';
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'the super admin could not change it'; end if;
    begin insert into public.wording (source) values ('Empty'); raise exception 'a row with no wording was taken';
    exception when check_violation then null; end;
    reset role;
    execute 'set local role anon';
    select fil into v from public.wording where source = 'Case Reports';
    reset role;
    if v is distinct from 'Mga Reklamo' then raise exception 'not readable before signing in: %', v; end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    delete from public.wording where source = 'Case Reports';
    get diagnostics n = row_count;
    reset role;
    if n <> 1 then raise exception 'the super admin could not put it back'; end if;
    v_log := v_log || E'\n' || 'ok  a super admin rewords a label (read before signing in) and puts the code''s own back; a committee admin cannot, an empty row is refused';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL wording: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
