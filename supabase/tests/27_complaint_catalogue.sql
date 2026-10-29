-- 27_complaint_catalogue.sql: the complaint categories and options, editable (0146). Rolled back.
do $sweep$
declare
  v_log text := '';
  v_sup uuid := gen_random_uuid(); v_com uuid := gen_random_uuid(); v_res uuid := gen_random_uuid();
  j jsonb; k text; o bigint; n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', x.rl, 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_sup, '+639999999991', 'Catalogue, Super', 'resident'), (v_com, '+639999999992', 'Catalogue, Committee', 'resident'),
                 (v_res, '+639999999993', 'Catalogue, Ana', 'resident')) as x(id, mob, nm, rl);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_sup, v_com, v_res);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_com;
  v_log := 'setup ok';

  -- 1. the catalogue starts as the app's list: 8 categories, 34 options
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.complaint_catalogue(false);
    if jsonb_array_length(j) <> 8 then raise exception 'categories %', jsonb_array_length(j); end if;
    select sum(jsonb_array_length(c -> 'options')) into n from jsonb_array_elements(j) c;
    if n <> 34 then raise exception 'options %', n; end if;
    if j -> 0 ->> 'key' <> 'street_obstruction' or j -> 0 -> 'options' -> 1 ->> 'en' <> 'Illegal Parking' then raise exception 'order %', j -> 0; end if;
    if (select count(*) from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'complaint_category')
       <> (select count(*) from public.complaint_categories) then raise exception 'the table and the type disagree'; end if;
    v_log := v_log || E'\n' || 'ok  the catalogue starts as the app''s list (8 categories, 34 options, in order), one row for each value of the type';
  exception when others then v_log := v_log || E'\n' || 'FAIL start: ' || sqlerrm; end;

  -- 2. a super admin edits: an option renamed, switched off, added; a category made (and added to the type)
  begin
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    select id into o from public.complaint_options where category = 'animal_welfare' and label_en = 'Neglected Pets';
    perform public.option_save(o, 'animal_welfare', 'Neglected or Abandoned Pets', 'Pinabayaang alaga', true, null);
    perform public.option_save(null, 'animal_welfare', 'Overgrown Trees Near Animals', null, true, null);
    perform public.option_save(o, 'animal_welfare', 'Neglected or Abandoned Pets', 'Pinabayaang alaga', false, null);
    begin perform public.option_save(null, 'animal_welfare', 'animal cruelty', null, true, null); raise exception 'a duplicate option was made';
    exception when check_violation then null; end;
    k := public.category_save(null, 'Overgrown Trees', 'Mga Punong Lumago', '#2E7D32', 'environmental_waste_hazard', true, null);
    if k <> 'overgrown_trees' then raise exception 'key %', k; end if;
    if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'complaint_category' and e.enumlabel = 'overgrown_trees') then
      raise exception 'not added to the type';
    end if;
    perform public.option_save(null, k, 'Branches Over Power Lines', 'Sanga sa kawad ng kuryente', true, null);
    begin perform public.category_save(null, 'Overgrown Trees', null, null, null, true, null); raise exception 'a duplicate category was made';
    exception when check_violation then null; end;
    begin perform public.category_save(k, 'Overgrown Trees', null, 'green', null, true, null); raise exception 'a bad colour was taken';
    exception when check_violation then null; end;
    v_log := v_log || E'\n' || 'ok  a super admin renames, adds and switches off options, and makes a category (added to the type); duplicates and a bad colour are refused';
  exception when others then v_log := v_log || E'\n' || 'FAIL edit: ' || sqlerrm; end;

  -- 3. residents see only what is on; a super admin can see everything; others cannot edit
  begin
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    j := public.complaint_catalogue(true);   -- a resident asking for everything still gets only what is on
    if not exists (select 1 from jsonb_array_elements(j) c where c ->> 'key' = 'overgrown_trees') then raise exception 'the new category is not offered'; end if;
    if exists (select 1 from jsonb_array_elements(j) c, jsonb_array_elements(c -> 'options') x where x ->> 'en' = 'Neglected or Abandoned Pets') then
      raise exception 'a switched-off option is offered';
    end if;
    perform set_config('request.jwt.claim.sub', v_sup::text, true);
    j := public.complaint_catalogue(true);
    if not exists (select 1 from jsonb_array_elements(j) c, jsonb_array_elements(c -> 'options') x where x ->> 'en' = 'Neglected or Abandoned Pets' and not (x ->> 'active')::boolean) then
      raise exception 'the super admin does not see the switched-off option';
    end if;
    perform set_config('request.jwt.claim.sub', v_com::text, true);
    begin perform public.option_save(null, 'peace_order_nuisance', 'Karaoke', null, true, null); raise exception 'a committee admin edited the catalogue';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claim.sub', v_res::text, true);
    begin perform public.category_save(null, 'Mine', null, null, null, true, null); raise exception 'a resident made a category';
    exception when insufficient_privilege then null; end;
    v_log := v_log || E'\n' || 'ok  residents are offered only what is on; a super admin sees everything; a committee admin and a resident cannot edit';
  exception when others then v_log := v_log || E'\n' || 'FAIL who: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
