-- =============================================================
-- SmartSumbong — 0163 Several categories and sub-categories on one report, kept as they were filed
--
-- The panel (7 Sep 2026, ask 3) and Ace (4 Nov 2026): a resident files one report with more than one concern ("Barangay Service:
-- delayed response + duty negligence"), each a category and, when it has them, one of its options (the sub-category). Each is
-- resolved on its own (0130). And when the Control Room later renames, adds or switches off a category or an option, every case
-- keeps what it was filed with, and whoever handles or views it is told what it was filed as.
--
--   report_concerns.option_id               the option of a concern (two options of one category are two concerns)
--   report_concerns.filed_category_en/fil   what the category was called when the concern was raised (never changed after)
--   report_concerns.filed_option_en/fil     the same for the option
--   file_report(..., p_option, p_concerns)  the main option by its id, and up to three more concerns [{category, option}];
--                                           one that was switched off while the report waited in the phone's outbox is
--                                           left out, and the report still files
--   add_report_concern(..., p_option)       an administrator, or the resident while the report is being reviewed, adds one
--   _catalogue_change_note()                renaming or switching off a category or an option writes a note on the timeline
--                                           of every open case that has it: what it is called now, what the case was filed as
--
-- The concerns raised before this migration are named as they were filed wherever something recorded it (step 2).
-- =============================================================

set search_path = public, extensions;

-- 1. a concern names its option and keeps what both were called
alter table public.report_concerns
  add column if not exists option_id bigint references public.complaint_options (id) on delete set null,
  add column if not exists filed_category_en text,
  add column if not exists filed_category_fil text,
  add column if not exists filed_option_en text,
  add column if not exists filed_option_fil text;
create index if not exists report_concerns_option_idx on public.report_concerns (option_id) where option_id is not null;
comment on column public.report_concerns.option_id is '0163: the option (sub-category) of this concern, if it has one';
comment on column public.report_concerns.filed_category_en is '0163: the category''s name when the concern was raised; never changed after';

alter table public.report_concerns drop constraint if exists report_concerns_report_id_category_key;
create unique index if not exists report_concerns_one_each on public.report_concerns (report_id, category, coalesce(option_id, 0));

-- 2. the concerns already there, named as they were filed wherever something recorded it:
--    - a category untouched since the concern was raised: today's name is the name it was filed under;
--    - otherwise the name the catalogue's own log (smart_events 'Category saved: ...', 0146) had at that moment;
--    - before the catalogue could be edited at all (0146, 29 Oct 2026): the original fixed names, below;
--    - the main concern's option: the report's subject IS the option's English name as filed; its row is found by today's
--      name, by a name the log shows it had, or by its place in the original list.
--    Only a Tagalog name changed between 29 Oct and today, for a concern raised in between, falls back to today's.
do $backfill$
declare
  x record; c_en text; c_fil text; h_en text; s_en text; s_fil text; v_en text; v_fil text; v_opt bigint; o_en text; o_fil text;
begin
  create temporary table _seed_cat (key text primary key, en text, fil text) on commit drop;
  insert into _seed_cat values
    ('street_obstruction', 'Street Obstruction', 'Sagabal sa Kalsada'),
    ('public_safety_infrastructure', 'Public Safety and Infrastructure', 'Kaligtasan at Imprastraktura'),
    ('environmental_waste_hazard', 'Environmental and Waste Hazards', 'Kapaligiran at Basura'),
    ('animal_welfare', 'Animal Welfare', 'Kapakanan ng Hayop'),
    ('traffic_violation', 'Traffic Violation', 'Paglabag sa Trapiko'),
    ('barangay_service', 'Barangay Service', 'Serbisyo ng Barangay'),
    ('peace_order_nuisance', 'Peace, Order, & Nuisance', 'Kapayapaan, Kaayusan at Istorbo'),
    ('other', 'Others', 'Iba pa');
  create temporary table _seed_opt (category text, en text, n bigint) on commit drop;
  insert into _seed_opt select c, o, n from (values
    ('street_obstruction', array['Obstructed Sidewalks', 'Illegal Parking', 'Vendor Blocking Sidewalks']),
    ('public_safety_infrastructure', array['Dangling Electric Wires', 'Poor Street Lighting', 'Unsecured Construction Site', 'Potholes', 'Open Manholes / Damaged Drainage Covers']),
    ('environmental_waste_hazard', array['Illegal Dumping of Garbage', 'Public Urination', 'Clogged Drainage', 'Foul-Smelling Surrounding', 'Industrial / Commercial Smoke Emission', 'Flooded Street / Road', 'Open Burning of Waste', 'Smoking / Vaping in Prohibited Areas']),
    ('animal_welfare', array['Animal Cruelty', 'Stray / Nuisance Animals', 'Animal Defecation', 'Neglected Pets']),
    ('traffic_violation', array['Unregistered / Unlicensed', 'Habal-Habal', 'Excessive Fare', 'Reckless Driving', 'Overloading', 'Abandoning Vehicle']),
    ('barangay_service', array['Delayed Barangay Response', 'Duty & Negligence', 'Rude Barangay Personnel', 'Document Processing']),
    ('peace_order_nuisance', array['Troublemaking Loiterer', 'Street Drinking Nuisance', 'Altercations / Street Brawls', 'Unreasonable Neighborhood Noise'])
  ) as t(c, opts), unnest(opts) with ordinality as u(o, n);

  for x in
    select rc.id, rc.category::text as cat, rc.created_at as t, rc.option_id, r.subject, (rc.category = r.category) as is_main
      from public.report_concerns rc join public.reports r on r.id = rc.report_id
     where rc.filed_category_en is null
  loop
    select label_en, label_fil into c_en, c_fil from public.complaint_categories where key = x.cat;
    select regexp_replace(e.summary, '^Category saved: ', '') into h_en
      from public.smart_events e where e.kind = 'catalogue' and e.detail ->> 'category' = x.cat and e.at <= x.t order by e.at desc limit 1;
    select en, fil into s_en, s_fil from _seed_cat where key = x.cat;
    v_en := coalesce(h_en, s_en, c_en);
    v_fil := case when v_en = c_en then c_fil when v_en = s_en then s_fil else v_en end;
    v_opt := x.option_id; o_en := null; o_fil := null;
    if x.is_main and x.subject is not null
       and x.subject not in (coalesce(c_en, ''), coalesce(c_fil, ''), coalesce(s_en, ''), coalesce(s_fil, ''), coalesce(h_en, ''), v_en) then
      if v_opt is null then
        v_opt := coalesce(
          (select o.id from public.complaint_options o where o.category = x.cat and (o.label_en = x.subject or o.label_fil = x.subject) order by o.active desc, o.id limit 1),
          (select o.id from public.smart_events e join public.complaint_options o on o.id = (e.detail ->> 'option')::bigint
            where e.kind = 'catalogue' and e.summary = 'Option saved: ' || x.subject and o.category = x.cat order by e.at desc limit 1),
          (select o.id from _seed_opt so join public.complaint_options o on o.category = so.category and o.sort = so.n
            where so.category = x.cat and so.en = x.subject limit 1));
      end if;
      o_en := x.subject;
      select case when o.label_en = x.subject then o.label_fil else x.subject end into o_fil from public.complaint_options o where o.id = v_opt;
      o_fil := coalesce(o_fil, x.subject);
    end if;
    update public.report_concerns
       set option_id = v_opt, filed_category_en = v_en, filed_category_fil = v_fil, filed_option_en = o_en, filed_option_fil = o_fil
     where id = x.id;
  end loop;
end $backfill$;

-- 3. from now on: the names are taken when a concern is raised, and never changed after
create or replace function public._concern_snapshot()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    new.category := old.category;
    if new.option_id is not null then new.option_id := old.option_id; end if;   -- only an option deleted outright clears it
    new.filed_category_en := old.filed_category_en; new.filed_category_fil := old.filed_category_fil;
    new.filed_option_en := old.filed_option_en; new.filed_option_fil := old.filed_option_fil;
    return new;
  end if;
  if new.option_id is not null and not exists (select 1 from public.complaint_options o where o.id = new.option_id and o.category = new.category::text) then
    raise exception 'That option is not under this category' using errcode = 'check_violation';
  end if;
  if new.filed_category_en is null then
    select c.label_en, c.label_fil into new.filed_category_en, new.filed_category_fil from public.complaint_categories c where c.key = new.category::text;
  end if;
  if new.option_id is not null and new.filed_option_en is null then
    select o.label_en, o.label_fil into new.filed_option_en, new.filed_option_fil from public.complaint_options o where o.id = new.option_id;
  end if;
  return new;
end $$;
create trigger concern_snapshot before insert or update on public.report_concerns
  for each row execute function public._concern_snapshot();

-- 4. the report's own concern: its option, given by id (0163) or found from its subject
create or replace function public._main_concern()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare v_opt bigint;
begin
  begin v_opt := nullif(current_setting('smartsumbong.main_option', true), '')::bigint; exception when others then v_opt := null; end;
  if v_opt is not null and not exists (select 1 from public.complaint_options o where o.id = v_opt and o.category = new.category::text) then
    v_opt := null;
  end if;
  if v_opt is null then
    select o.id into v_opt from public.complaint_options o
     where o.category = new.category::text and (o.label_en = new.subject or o.label_fil = new.subject)
     order by o.active desc, o.id limit 1;
  end if;
  insert into public.report_concerns (report_id, category, option_id, created_by) values (new.id, new.category, v_opt, new.resident_id)
  on conflict do nothing;
  return new;
end $$;

-- 5. adding a concern: with its option; a resident only while the report is being reviewed, only what residents may pick, four at most
drop function if exists public.add_report_concern(uuid, public.complaint_category, text);
create or replace function public.add_report_concern(p_report uuid, p_category public.complaint_category, p_note text default null, p_option bigint default null)
returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  r public.reports%rowtype;
  v_id uuid;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  perform public._scope_guard(p_report, true);
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then raise exception 'No such report'; end if;
  if public.is_admin() then
    perform public._case_guard(p_report);
  elsif r.resident_id = auth.uid() then
    if r.status not in ('pending_review', 'validated') then
      raise exception 'A concern can be added only while the report is being reviewed';
    end if;
    if not exists (select 1 from public.complaint_categories c where c.key = p_category::text and c.active) then
      raise exception 'That kind of complaint is not offered' using errcode = 'check_violation';
    end if;
    if p_option is not null and not exists (select 1 from public.complaint_options o where o.id = p_option and o.category = p_category::text and o.active) then
      raise exception 'That option is not offered' using errcode = 'check_violation';
    end if;
    if (select count(*) from public.report_concerns where report_id = p_report) >= 4 then
      raise exception 'A report can have at most four concerns' using errcode = 'check_violation';
    end if;
  else
    raise exception 'Not allowed' using errcode = 'insufficient_privilege';
  end if;
  if v_note is not null and char_length(v_note) > 300 then raise exception 'The note can be at most 300 characters'; end if;
  if exists (select 1 from public.report_concerns where report_id = p_report and category = p_category and coalesce(option_id, 0) = coalesce(p_option, 0)) then
    raise exception 'This report already has that concern';
  end if;
  insert into public.report_concerns (report_id, category, option_id, note, created_by) values (p_report, p_category, p_option, v_note, auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.add_report_concern(uuid, public.complaint_category, text, bigint) from public, anon;
grant execute on function public.add_report_concern(uuid, public.complaint_category, text, bigint) to authenticated, service_role;

-- 6. filing: the main option by id, and the other concerns, in the same call
drop function if exists public.file_report(public.complaint_category, text, text, double precision, double precision, boolean, jsonb, uuid);
create or replace function public.file_report(
  p_category public.complaint_category, p_subject text, p_description text, p_latitude double precision, p_longitude double precision,
  p_is_anonymous boolean default false, p_media jsonb default '[]'::jsonb, p_client_ref uuid default null,
  p_option bigint default null, p_concerns jsonb default '[]'::jsonb
) returns public.reports
language plpgsql set search_path = public, extensions
as $$
declare
  v_report public.reports;
  v_item   jsonb;
begin
  if jsonb_typeof(coalesce(p_media, '[]'::jsonb)) <> 'array' then
    raise exception 'p_media must be a JSON array of {media_url, mime_type, bytes}'
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_typeof(coalesce(p_concerns, '[]'::jsonb)) <> 'array' then
    raise exception 'p_concerns must be a JSON array of {category, option}' using errcode = 'invalid_parameter_value';
  end if;

  -- Already filed under this ref: hand back that report, file nothing.
  if p_client_ref is not null then
    select * into v_report from public.reports where resident_id = auth.uid() and client_ref = p_client_ref;
    if found then
      return v_report;
    end if;
  end if;

  begin
    perform set_config('smartsumbong.main_option', coalesce(p_option::text, ''), true);
    insert into public.reports
      (resident_id, is_anonymous, category, subject, description, latitude, longitude, client_ref)
    values
      (auth.uid(), coalesce(p_is_anonymous, false), p_category, p_subject, p_description, p_latitude, p_longitude, p_client_ref)
    returning * into v_report;
    perform set_config('smartsumbong.main_option', '', true);
  exception when unique_violation then
    -- Two sends of the same queued report raced; the other one won.
    select * into v_report from public.reports where resident_id = auth.uid() and client_ref = p_client_ref;
    return v_report;
  end;

  for v_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
  loop
    insert into public.report_media (report_id, media_url, mime_type, bytes)
    values (v_report.id, v_item ->> 'media_url', v_item ->> 'mime_type', (v_item ->> 'bytes')::integer);
  end loop;

  -- the other concerns; one switched off (or the same as another) while the report waited is left out, and the report still files
  for v_item in select value from jsonb_array_elements(coalesce(p_concerns, '[]'::jsonb)) limit 3
  loop
    begin
      perform public.add_report_concern(v_report.id, (v_item ->> 'category')::public.complaint_category, null, nullif(v_item ->> 'option', '')::bigint);
    exception when others then
      null;
    end;
  end loop;

  return v_report;
end $$;
revoke all on function public.file_report(public.complaint_category, text, text, double precision, double precision, boolean, jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.file_report(public.complaint_category, text, text, double precision, double precision, boolean, jsonb, uuid, bigint, jsonb) to authenticated, service_role;

-- 7. the resident is told which concern was resolved by the name it was filed under
create or replace function public.set_concern_status(p_concern uuid, p_resolved boolean, p_remark text default null)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  c public.report_concerns%rowtype;
  r public.reports%rowtype;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
begin
  if not public.admin_can_write() then raise exception 'Only an administrator may do this' using errcode = 'insufficient_privilege'; end if;
  select * into c from public.report_concerns where id = p_concern;
  if not found then raise exception 'No such concern'; end if;
  if v_remark is not null and char_length(v_remark) > 300 then raise exception 'The remark can be at most 300 characters'; end if;
  select * into r from public.reports where id = c.report_id;
  perform public._case_guard(c.report_id);
  update public.report_concerns
     set status = case when p_resolved then 'resolved' else 'open' end,
         resolved_at = case when p_resolved then now() end,
         resolved_by = case when p_resolved then auth.uid() end,
         remark = v_remark
   where id = p_concern;
  if p_resolved then
    insert into public.notifications (user_id, report_id, kind, message)
    values (r.resident_id, r.id, 'status_change',
            'One concern in your complaint ' || r.tracking_id || ' ('
            || coalesce(c.filed_category_en, replace(c.category::text, '_', ' ')) || coalesce(': ' || c.filed_option_en, '')
            || ') was marked resolved.' || coalesce(' ' || v_remark, ''));
  end if;
end $$;

-- 8. renaming or switching off a category or an option: a note on the timeline of every open case that has it
create or replace function public._catalogue_change_note()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_off boolean := old.active and not new.active; v_renamed boolean := new.label_en is distinct from old.label_en;
begin
  if not (v_off or v_renamed) then return new; end if;
  perform set_config('smartsumbong.handler_change', 'on', true);   -- a note, not a hand-over: nobody takes the case by it
  if tg_table_name = 'complaint_categories' then
    insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
    select distinct on (r.id) r.id, r.resident_id, r.status, r.status,
           left(case when v_off then format('The category "%s" was switched off in the Control Room. This case keeps it: it was filed under "%s".',
                                            old.label_en, coalesce(rc.filed_category_en, old.label_en))
                     else format('The category "%s" is now called "%s". This case was filed under "%s".',
                                 old.label_en, new.label_en, coalesce(rc.filed_category_en, old.label_en)) end, 500), true
      from public.report_concerns rc join public.reports r on r.id = rc.report_id
     where rc.category::text = new.key and r.deleted_at is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected')
     order by r.id;
  else
    insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
    select distinct on (r.id) r.id, r.resident_id, r.status, r.status,
           left(case when v_off then format('The option "%s" was switched off in the Control Room. This case keeps it: it was filed as "%s".',
                                            old.label_en, coalesce(rc.filed_option_en, old.label_en))
                     else format('The option "%s" is now called "%s". This case was filed as "%s".',
                                 old.label_en, new.label_en, coalesce(rc.filed_option_en, old.label_en)) end, 500), true
      from public.report_concerns rc join public.reports r on r.id = rc.report_id
     where rc.option_id = new.id and r.deleted_at is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected')
     order by r.id;
  end if;
  perform set_config('smartsumbong.handler_change', 'off', true);
  return new;
end $$;
create trigger catalogue_change_note after update of label_en, active on public.complaint_categories
  for each row execute function public._catalogue_change_note();
create trigger catalogue_change_note after update of label_en, active on public.complaint_options
  for each row execute function public._catalogue_change_note();
