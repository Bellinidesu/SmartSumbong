-- 31_committee_colours.sql: committee colours and the super admin colour (0150). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_com uuid := gen_random_uuid();
  k text; n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999941', 'Colour, Super', 'resident'), (v_com, '+639999999942', 'Colour, Committee', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now(), role = 'admin' where id in (v_sup, v_com);
  update public.users set admin_tier = 'super' where id = v_sup;
  update public.users set admin_tier = 'committee', committee = 'peace_order' where id = v_com;
  v_log := 'setup ok';

  -- 1. every committee has a colour; the active ones keep apart from each other and from branding blue
  begin
    if exists (select 1 from public.committees where colour is null) then raise exception 'a committee without a colour'; end if;
    if (select super_colour from public.barangay_profile where id = 1) <> '#00308F' then raise exception 'not branding blue'; end if;
    select count(*) into n from public.committees a join public.committees b on a.key < b.key
     where a.active and b.active and public._colour_dist(a.colour, b.colour) < 70;
    if n > 0 then raise exception '% active pairs too close', n; end if;
    if exists (select 1 from public.committees where active and public._colour_dist(colour, '#00308F') < 70) then raise exception 'an active committee near branding blue'; end if;
    v_log := v_log || E'\n' || 'ok  every committee has a colour; the active ones keep apart from each other and from branding blue';
  exception when others then v_log := v_log || E'\n' || 'FAIL start: ' || sqlerrm; end;

  -- 2. a super admin picks colours; the super admin colour and anything near it, or near another active committee, is taken
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    k := public.committee_save(null, 'Committee on Senior Citizens', null, true, 'Senior Citizens', '#F9A825');
    if (select colour from public.committees where key = k) <> '#F9A825' then raise exception 'colour not kept'; end if;
    begin perform public.committee_save(k, 'Committee on Senior Citizens', null, true, 'Senior Citizens', '#0A3A99'); raise exception 'a colour near branding blue was taken';
    exception when check_violation then null; end;
    begin perform public.committee_save(k, 'Committee on Senior Citizens', null, true, 'Senior Citizens', '#D7342F'); raise exception 'a colour near Peace and Order was taken';
    exception when check_violation then null; end;
    begin perform public.committee_save(k, 'Committee on Senior Citizens', null, true, 'Senior Citizens', 'orange'); raise exception 'a word was taken as a colour';
    exception when check_violation then null; end;
    k := public.committee_save(null, 'Committee on Youth', null, true, 'Youth', null);
    if public._colour_clash((select colour from public.committees where key = k), k) is not null then raise exception 'the free colour clashes'; end if;
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    begin perform public.committee_save('peace_order', 'Peace and Order', null, true, 'Peace and Order', '#000000'); raise exception 'a committee admin changed a colour';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  a super admin picks colours or gets a free one; near the super admin colour or another committee, or not a colour, is refused; a committee admin cannot';
  exception when others then v_log := v_log || E'\n' || 'FAIL pick: ' || sqlerrm; end;

  -- 3. the super admins move their colour only where no committee is; then branding blue is free
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    begin update public.barangay_profile set super_colour = '#D32F2F' where id = 1; raise exception 'the super admins took Peace and Order''s colour';
    exception when check_violation then null; end;
    update public.barangay_profile set super_colour = '#111111' where id = 1;
    k := public.committee_save(null, 'Committee on Appropriations', null, true, 'Appropriations', '#00308F');
    if (select colour from public.committees where key = k) <> '#00308F' then raise exception 'branding blue not free'; end if;
    v_log := v_log || E'\n' || 'ok  the super admins cannot take a committee''s colour; once they change theirs, branding blue is free for a committee';
  exception when others then v_log := v_log || E'\n' || 'FAIL super: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
