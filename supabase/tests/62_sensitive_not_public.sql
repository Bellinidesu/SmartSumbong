-- 62_sensitive_not_public.sql: a sensitive case is never on the residents' map (0184, backend sweep). Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  v_sup uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); r1 uuid; r2 uuid;
  lat constant double precision := 14.51944; lng constant double precision := 121.01219;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999931', 'Public, Super'), (v_ana, '+639999999932', 'Public, Ana')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_ana);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto, gabi-gabi.', lat, lng) returning id into r1;
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_ana, 'peace_order_nuisance', 'Pananakit', 'May nananakit sa bahay na ito gabi-gabi.', lat + 0.001, lng) returning id into r2;
  update public.reports set is_sensitive = true where id = r2;

  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.set_report_public(r1, true);
    begin perform public.set_report_public(r2, true); raise exception 'a sensitive case was published';
    exception when check_violation then null; end;
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    if not exists (select 1 from public.public_incidents() where id = r1) then raise exception 'an ordinary public case is gone from the map'; end if;
    if exists (select 1 from public.public_incidents() where id = r2) then raise exception 'a sensitive case is on the map'; end if;
    reset role;
    -- marked sensitive after it was published: it drops off
    update public.reports set is_sensitive = true where id = r1;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_ana::text, true);
    if exists (select 1 from public.public_incidents() where id = r1) then raise exception 'a case marked sensitive stays on the map'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a sensitive case cannot be published, and one marked sensitive after publishing drops off the residents'' map; ordinary ones stay';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL map: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
