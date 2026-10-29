-- 29_barangay_profile.sql: the barangay's name, place and seal (0148). Rolled back.
-- Run as the API's own roles ("anon", "authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_com uuid := gen_random_uuid();
  n integer; v_name text;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'Profile, Super', 'resident'), (v_com, '+639999999962', 'Profile, Committee', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id in (v_sup, v_com);
  update public.users set admin_tier = 'super' where id = v_sup;
  update public.users set admin_tier = 'committee', committee = 'peace_order' where id = v_com;
  v_log := 'setup ok';

  -- 1. it starts as Barangay 183, with the shipped seal, and anyone can read it
  begin
    execute 'set local role anon';
    select name into v_name from public.barangay_profile where id = 1;
    reset role;
    if v_name is distinct from 'Barangay 183' then raise exception 'anon read %', v_name; end if;
    if (select place from public.barangay_profile) <> 'Zone 20, Villamor, Pasay City' or (select seal_url from public.barangay_profile) is not null then
      raise exception 'not the starting profile';
    end if;
    v_log := v_log || E'\n' || 'ok  the profile starts as Barangay 183, Zone 20, Villamor, Pasay City with the shipped seal, readable before signing in';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL start: ' || sqlerrm; end;

  -- 2. a super admin changes it; a committee admin cannot; a seal from anywhere but the barangay's image host is refused
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    update public.barangay_profile set name = 'Barangay 999' where id = 1;
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'a committee admin renamed the barangay'; end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    update public.barangay_profile set name = 'Barangay 184', seal_url = 'https://res.cloudinary.com/x/image/upload/v1/barangay/seal.png' where id = 1;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'the super admin could not change it'; end if;
    begin update public.barangay_profile set seal_url = 'https://example.com/seal.png' where id = 1; raise exception 'a seal from another host was taken';
    exception when check_violation then null; end;
    begin insert into public.barangay_profile (id, name) values (2, 'Another'); raise exception 'a second profile was made';
    exception when insufficient_privilege or check_violation then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  a super admin renames it and swaps the seal; a committee admin cannot; a seal from another host and a second row are refused';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
