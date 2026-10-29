-- 28_barangay_rules.sql: the barangay's rules, deadlines and hotlines from the portal (0147). Rolled back.
-- The writing checks run as the API's own role ("authenticated"), where row level security applies.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_com uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  r uuid; g uuid; n integer; hrs integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999971', 'Rules, Super', 'resident'), (v_com, '+639999999972', 'Rules, Committee', 'resident'),
                 (v_res, '+639999999973', 'Rules, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_com, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_com;
  v_log := 'setup ok';

  -- 1. a category with no deadline or committee of its own gets Others' (what a category made in Settings starts with)
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    perform public.catalogue_fill();   -- a fresh database has a deadline for Others only
    delete from public.sla_policies where category = 'animal_welfare';
    delete from public.committee_for_category where category = 'animal_welfare';
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    begin perform public.catalogue_fill(); raise exception 'a committee admin filled the catalogue';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    n := public.catalogue_fill();
    if n <> 2 then raise exception 'filled %', n; end if;
    if (select resolution_hours from public.sla_policies where category = 'animal_welfare') <> (select resolution_hours from public.sla_policies where category = 'other') then
      raise exception 'the deadline is not Others''';
    end if;
    if (select committee from public.committee_for_category where category = 'animal_welfare') <> (select committee from public.committee_for_category where category = 'other') then
      raise exception 'the committee is not Others''';
    end if;
    if public.catalogue_fill() <> 0 then raise exception 'a second fill added rows'; end if;
    v_log := v_log || E'\n' || 'ok  catalogue_fill gives a category without them Others'' deadline and committee, once; a committee admin cannot run it';
  exception when others then v_log := v_log || E'\n' || 'FAIL fill: ' || sqlerrm; end;

  -- 2. a report in a category with no deadline row still gets a deadline (Others' hours)
  begin
    delete from public.sla_policies where category = 'animal_welfare';
    select resolution_hours into hrs from public.sla_policies where category = 'other';
    insert into public.reports (resident_id, category, subject, description, latitude, longitude)
    values (v_res, 'animal_welfare', 'Asong gala', 'Mga asong gala sa harap ng paaralan.', 14.51944, 121.01219) returning id into r;
    if (select due_at - created_at from public.reports where id = r) <> make_interval(hours => hrs) then
      raise exception 'deadline % for % hours', (select due_at - created_at from public.reports where id = r), hrs;
    end if;
    v_log := v_log || E'\n' || 'ok  a report in a category with no deadline of its own takes Others'' hours';
  exception when others then v_log := v_log || E'\n' || 'FAIL deadline: ' || sqlerrm; end;

  -- 3. the rules, deadlines and hotlines are written by a super admin only
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    update public.operational_settings set max_report_photos = 7 where id = 1;
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'a committee admin changed the rules'; end if;
    update public.sla_policies set resolution_hours = 1 where category = 'other';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'a committee admin changed a deadline'; end if;
    begin insert into public.hotline_groups (name) values ('Mine'); raise exception 'a committee admin added a hotline';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    update public.operational_settings set max_report_photos = 7, filing_paused = true, filing_paused_message = 'Sarado muna' where id = 1;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'the super admin could not change the rules'; end if;
    update public.sla_policies set resolution_hours = 36, accept_minutes = 25 where category = 'other';
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'the super admin could not change a deadline'; end if;
    insert into public.hotline_groups (name, display, sort_order) values ('Health Center', 'inline', 9) returning id into g;
    insert into public.hotline_numbers (group_id, label, number, carrier) values (g, 'Duty nurse', '0917 000 0000', 'Globe');
    update public.hotline_numbers set is_active = false where group_id = g;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'the super admin could not switch a number off'; end if;
    if not exists (select 1 from public.hotline_numbers where group_id = g and not is_active) then raise exception 'the super admin cannot see the number switched off'; end if;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    if exists (select 1 from public.hotline_numbers where group_id = g) then raise exception 'a resident sees a number switched off'; end if;
    reset role;
    v_log := v_log || E'\n' || 'ok  a super admin changes the rules, a deadline and the hotlines and still sees a number switched off; a committee admin cannot change them, a resident sees only what is on';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
