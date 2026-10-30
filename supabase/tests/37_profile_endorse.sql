-- 37_profile_endorse.sql: the profile banner, Inbox alerts, and the Kagawad's endorsement of a retirement (0157). Rolled back.
-- The reading checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid(); q uuid; n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999971', 'Prof, Super', 'resident'), (v_kpo, '+639999999972', 'Prof, Peace', 'resident'),
                 (v_kenv, '+639999999973', 'Prof, Env', 'resident'), (v_stf, '+639999999974', 'Prof, Staff', 'resident'),
                 (v_t1, '+639999999975', 'Prof, Tanod', 'tanod')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_kpo, v_kenv, v_stf, v_t1);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  insert into public.tanod_committees (tanod_id, committee, status) values (v_t1, 'peace_order', 'approved');
  insert into public.retirement_requests (tanod_id) values (v_t1) returning id into q;
  v_log := 'setup ok';

  -- 1. an administrator sets their own banner; a colour must be a colour, a picture a Cloudinary one
  begin
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.set_my_banner('solid', '#1e9e4a', null, 30);
    if (select banner_preset || banner_colour || banner_y from public.users where id = v_kpo) <> 'solid#1E9E4A30' then raise exception 'banner not kept'; end if;
    begin perform public.set_my_banner('solid', 'green', null, 50); raise exception 'a word taken as a colour';
    exception when check_violation then null; end;
    begin perform public.set_my_banner('photo', null, 'https://example.com/me.jpg', 50); raise exception 'a picture from elsewhere';
    exception when check_violation then null; end;
    perform public.set_my_banner('photo', null, 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/avatars/b.jpg', 120);
    if (select banner_y from public.users where id = v_kpo) <> 100 then raise exception 'the frame was not kept in bounds'; end if;
    v_log := v_log || E'\n' || 'ok  an administrator sets their own banner (a preset, a colour, or a Cloudinary picture framed within bounds); anything else is refused';
  exception when others then v_log := v_log || E'\n' || 'FAIL banner: ' || sqlerrm; end;

  -- 2. a new Inbox message raises an alert the recipient can switch off; a system message does not
  begin
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    perform public.send_mail(array[v_kpo], 'Paalam', 'Magreretiro po si Tanod.', null, null);
    if not exists (select 1 from public.notifications where user_id = v_kpo and kind::text = 'inbox_mail' and message like 'New message from %Paalam') then raise exception 'no alert'; end if;
    perform public._system_mail(v_kpo, 'System', 'A system note', null, null);
    if (select count(*) from public.notifications where user_id = v_kpo and kind::text = 'inbox_mail') <> 1 then raise exception 'a system message raised an alert'; end if;
    v_log := v_log || E'\n' || 'ok  a new Inbox message raises an alert (kind inbox_mail, which can be switched off); a system message does not';
  exception when others then v_log := v_log || E'\n' || 'FAIL inbox alert: ' || sqlerrm; end;

  -- 3. the tanod's Kagawad sees and endorses the request; another Kagawad and staff do not; the super admins are told and still decide
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    if exists (select 1 from public.retirement_requests where id = q) then raise exception 'another committee sees the request'; end if;
    perform set_config('request.jwt.claim.sub', v_stf::text, true);
    if exists (select 1 from public.retirement_requests where id = q) then raise exception 'staff see the request'; end if;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    if not exists (select 1 from public.retirement_requests where id = q) then raise exception 'the Kagawad cannot see it'; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', v_kenv::text, true);
    begin perform public.endorse_retirement(q, null); raise exception 'another committee endorsed';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_kpo::text, true);
    perform public.endorse_retirement(q, 'Tapos na ang termino niya');
    if (select endorsed_by from public.retirement_requests where id = q) <> v_kpo or (select status::text from public.retirement_requests where id = q) <> 'pending' then raise exception 'not endorsed, or decided'; end if;
    if not exists (select 1 from public.notifications where user_id = v_sup and subject_user_id = v_t1 and message like '%endorses%') then raise exception 'super admins not told'; end if;
    begin perform public.endorse_retirement(q, null); raise exception 'endorsed twice';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  the tanod''s Kagawad sees and endorses the request (once); another committee and staff do not see it; the super admins are told and the request stays theirs to decide';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL endorse: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
