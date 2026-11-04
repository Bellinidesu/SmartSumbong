-- 43_committee_logos.sql: the committee's logo, and staff seeing their own committee's staff (0164). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_k1 uuid := gen_random_uuid(); v_s1 uuid := gen_random_uuid(); v_s2 uuid := gen_random_uuid();
  v_k2 uuid := gen_random_uuid(); v_s3 uuid := gen_random_uuid();
  j jsonb; ids uuid[];
  v_logo constant text := 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/committees/peace.png';
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999961', 'Logo, Super'), (v_k1, '+639999999962', 'Logo, Kagawad'), (v_s1, '+639999999963', 'Logo, Staff One'),
                 (v_s2, '+639999999964', 'Logo, Staff Two'), (v_k2, '+639999999965', 'Logo, Other Kagawad'), (v_s3, '+639999999966', 'Logo, Other Staff')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id in (v_sup, v_k1, v_s1, v_s2, v_k2, v_s3);
  update public.users set admin_tier = 'super' where id = v_sup;
  update public.users set admin_tier = 'committee', committee = 'peace_order' where id = v_k1;
  update public.users set admin_tier = 'moderator', committee = 'peace_order' where id in (v_s1, v_s2);
  update public.users set admin_tier = 'committee', committee = 'health_sanitation' where id = v_k2;
  update public.users set admin_tier = 'moderator', committee = 'health_sanitation' where id = v_s3;

  -- 1. only a super admin sets a committee's logo, only an uploaded picture, and can clear it
  begin
    perform set_config('request.jwt.claim.sub', v_k1::text, true);
    begin perform public.committee_set_logo('peace_order', v_logo); raise exception 'a Kagawad set the logo';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin perform public.committee_set_logo('peace_order', 'https://example.com/logo.png'); raise exception 'a picture from elsewhere was taken';
    exception when check_violation then null; end;
    begin perform public.committee_set_logo('no_such_committee', v_logo); raise exception 'a logo was set on no committee';
    exception when check_violation then null; end;
    perform public.committee_set_logo('peace_order', v_logo);
    if (select logo_url from public.committees where key = 'peace_order') is distinct from v_logo then raise exception 'the logo was not kept'; end if;
    perform public.committee_set_logo('peace_order', null);
    if (select logo_url from public.committees where key = 'peace_order') is not null then raise exception 'the logo was not cleared'; end if;
    v_log := v_log || E'\n' || 'ok  only a super admin sets a committee''s logo, only an uploaded picture, and can clear it';
  exception when others then v_log := v_log || E'\n' || 'FAIL logo: ' || sqlerrm; end;

  -- 2. a staff member sees their committee's other staff, not its Kagawad (0153); a Kagawad their staff; nobody another committee's
  begin
    perform set_config('request.jwt.claim.sub', v_s1::text, true);
    j := public.punch_cards(7, null);
    select array_agg((x->>'id')::uuid) into ids from jsonb_array_elements(j) x;
    if not (ids @> array[v_s1, v_s2]) then raise exception 'a staff member does not see their committee''s staff'; end if;
    if ids && array[v_k1] then raise exception 'a staff member sees their Kagawad''s card'; end if;
    if ids && array[v_s3, v_k2, v_sup] then raise exception 'a staff member sees another committee''s cards'; end if;
    perform set_config('request.jwt.claim.sub', v_k1::text, true);
    j := public.punch_cards(7, null);
    select array_agg((x->>'id')::uuid) into ids from jsonb_array_elements(j) x;
    if not (ids @> array[v_s1, v_s2]) then raise exception 'a Kagawad does not see their staff'; end if;
    if ids && array[v_s3, v_k2] then raise exception 'a Kagawad sees another committee''s cards'; end if;
    perform set_config('request.jwt.claim.sub', v_s3::text, true);
    if public._sees_punch_card(v_k1) or public._sees_punch_card(v_s1) then raise exception 'staff of one committee see the other''s'; end if;
    v_log := v_log || E'\n' || 'ok  staff see their own committee''s other staff, not their Kagawad; a Kagawad their staff; never another committee''s';
  exception when others then v_log := v_log || E'\n' || 'FAIL punch cards: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
