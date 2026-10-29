-- =============================================================
-- SmartSumbong — 0146 The complaint catalogue, editable
--
-- Ready for Barangay 183, step 4 (Ace, 29 Oct 2026: "everything in the system
-- is customizable and tunable to the needs of 183", the barangay's Sir Kiko:
-- the super admin adds or edits the complaint options of each category).
--
-- Until now the 8 categories were a fixed enum and the 34 options residents
-- pick from ("Potholes", "Illegal Parking") were written into the app and the
-- portal. They become two tables a super admin edits:
--
--   complaint_categories   each category: its names (English, Tagalog), colour,
--                          icon, order, and whether residents can pick it
--   complaint_options      the options under each category, the same way
--   complaint_catalogue()  what the app and the portal read (the active ones,
--                          or everything for a super admin)
--   category_save()        make (it is added to the complaint_category type,
--                          so every column, rule and function keeps working)
--                          or change a category
--   option_save()          make or change an option
--
-- Nothing is ever deleted: a category or an option is switched off, and the
-- reports filed under it keep it. An option still lands in reports.subject, as
-- before, so the case list's issue filter keeps working.
-- =============================================================

set search_path = public, extensions;

create table public.complaint_categories (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  label_en   text not null check (char_length(label_en) between 2 and 60),
  label_fil  text not null check (char_length(label_fil) between 2 and 60),
  colour     text not null default '#0F9D9A' check (colour ~ '^#[0-9A-Fa-f]{6}$'),
  icon       text not null default 'other' check (icon ~ '^[a-z_]{2,30}$'),
  sort       smallint not null default 100,
  active     boolean not null default true,
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.complaint_categories (key, label_en, label_fil, colour, icon, sort) values
  ('street_obstruction',           'Street Obstruction',               'Sagabal sa Kalsada',                '#F93535', 'street_obstruction',           1),
  ('public_safety_infrastructure', 'Public Safety and Infrastructure', 'Kaligtasan at Imprastraktura',      '#356CF9', 'public_safety_infrastructure', 2),
  ('environmental_waste_hazard',   'Environmental and Waste Hazards',  'Kapaligiran at Basura',             '#F9AB35', 'environmental_waste_hazard',   3),
  ('animal_welfare',               'Animal Welfare',                   'Kapakanan ng Hayop',                '#34C759', 'animal_welfare',               4),
  ('traffic_violation',            'Traffic Violation',                'Paglabag sa Trapiko',               '#8E9ABB', 'traffic_violation',            5),
  ('barangay_service',             'Barangay Service',                 'Serbisyo ng Barangay',              '#422F8A', 'barangay_service',             6),
  ('peace_order_nuisance',         'Peace, Order, & Nuisance',         'Kapayapaan, Kaayusan at Istorbo',   '#E0609A', 'peace_order_nuisance',         7),
  ('other',                        'Others',                           'Iba pa',                            '#0F9D9A', 'other',                        8);

create table public.complaint_options (
  id         bigint generated always as identity primary key,
  category   text not null references public.complaint_categories (key) on update cascade,
  label_en   text not null check (char_length(label_en) between 2 and 60),
  label_fil  text not null check (char_length(label_fil) between 2 and 60),
  sort       smallint not null default 100,
  active     boolean not null default true,
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index complaint_options_one_name on public.complaint_options (category, lower(label_en));
-- the 34 options the app and the portal carried (Rose's list); the Tagalog names start as the English ones
insert into public.complaint_options (category, label_en, label_fil, sort)
select c, o, o, n from (values
  ('street_obstruction', array['Obstructed Sidewalks', 'Illegal Parking', 'Vendor Blocking Sidewalks']),
  ('public_safety_infrastructure', array['Dangling Electric Wires', 'Poor Street Lighting', 'Unsecured Construction Site', 'Potholes', 'Open Manholes / Damaged Drainage Covers']),
  ('environmental_waste_hazard', array['Illegal Dumping of Garbage', 'Public Urination', 'Clogged Drainage', 'Foul-Smelling Surrounding', 'Industrial / Commercial Smoke Emission', 'Flooded Street / Road', 'Open Burning of Waste', 'Smoking / Vaping in Prohibited Areas']),
  ('animal_welfare', array['Animal Cruelty', 'Stray / Nuisance Animals', 'Animal Defecation', 'Neglected Pets']),
  ('traffic_violation', array['Unregistered / Unlicensed', 'Habal-Habal', 'Excessive Fare', 'Reckless Driving', 'Overloading', 'Abandoning Vehicle']),
  ('barangay_service', array['Delayed Barangay Response', 'Duty & Negligence', 'Rude Barangay Personnel', 'Document Processing']),
  ('peace_order_nuisance', array['Troublemaking Loiterer', 'Street Drinking Nuisance', 'Altercations / Street Brawls', 'Unreasonable Neighborhood Noise'])
) as t(c, opts), unnest(opts) with ordinality as u(o, n);

alter table public.complaint_categories enable row level security;
alter table public.complaint_options enable row level security;
-- residents and tanods read what they can pick; administrators read everything
create policy complaint_categories_read on public.complaint_categories for select using (active or (select public.is_admin()));
create policy complaint_options_read on public.complaint_options for select using (active or (select public.is_admin()));
grant select on public.complaint_categories, public.complaint_options to anon, authenticated;
comment on table public.complaint_categories is '0146: the complaint categories, edited by a super admin (category_save). key is a value of the complaint_category type.';
comment on table public.complaint_options is '0146: the options under each category residents pick from (option_save); the one picked is written into reports.subject.';

/** What the app and the portal read: the categories and their options, in order. p_all (super admins) includes the ones switched off. */
create or replace function public.complaint_catalogue(p_all boolean default false)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', c.key, 'en', c.label_en, 'fil', c.label_fil, 'colour', c.colour, 'icon', c.icon, 'active', c.active,
           'options', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'en', o.label_en, 'fil', o.label_fil, 'active', o.active) order by o.sort, o.id)
                                  from public.complaint_options o
                                 where o.category = c.key and (o.active or (coalesce(p_all, false) and public.is_admin()))), '[]'))
           order by c.sort, c.key), '[]')
    from public.complaint_categories c
   where c.active or (coalesce(p_all, false) and public.is_admin())
$$;
revoke all on function public.complaint_catalogue(boolean) from public;
grant execute on function public.complaint_catalogue(boolean) to anon, authenticated;

/** Make a category (p_key null) or change one. A new one is added to the complaint_category type, so every column,
    access rule and function takes it; it can be used from the next request on (Postgres's rule for a new enum value). */
create or replace function public.category_save(p_key text, p_label_en text, p_label_fil text, p_colour text default null,
                                               p_icon text default null, p_active boolean default true, p_sort integer default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_key text := nullif(trim(coalesce(p_key, '')), '');
  v_en text := nullif(trim(coalesce(p_label_en, '')), '');
  v_fil text := nullif(trim(coalesce(p_label_fil, '')), '');
begin
  if not public.is_super_admin() then raise exception 'Only a super admin edits the complaint categories' using errcode = 'insufficient_privilege'; end if;
  if v_en is null or char_length(v_en) < 2 then raise exception 'Name the category' using errcode = 'check_violation'; end if;
  v_fil := coalesce(v_fil, v_en);
  if p_colour is not null and p_colour !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'The colour is a # and six hex digits' using errcode = 'check_violation'; end if;
  if v_key is null then
    v_key := left(trim(both '_' from regexp_replace(lower(translate(v_en, 'ñÑáéíóúÁÉÍÓÚ', 'nNaeiouAEIOU')), '[^a-z0-9]+', '_', 'g')), 40);
    if v_key !~ '^[a-z]' then v_key := 'c_' || v_key; end if;
    if exists (select 1 from public.complaint_categories where key = v_key) then raise exception 'A category with that name already exists' using errcode = 'check_violation'; end if;
    execute format('alter type public.complaint_category add value if not exists %L', v_key);
    insert into public.complaint_categories (key, label_en, label_fil, colour, icon, sort, active, updated_by)
    values (v_key, left(v_en, 60), left(v_fil, 60), coalesce(p_colour, '#0F9D9A'), coalesce(nullif(p_icon, ''), 'other'),
            coalesce(p_sort, (select coalesce(max(sort), 0) + 1 from public.complaint_categories where key <> 'other')), coalesce(p_active, true), auth.uid());
  else
    update public.complaint_categories
       set label_en = left(v_en, 60), label_fil = left(v_fil, 60), colour = coalesce(p_colour, colour), icon = coalesce(nullif(p_icon, ''), icon),
           sort = coalesce(p_sort, sort), active = coalesce(p_active, active), updated_by = auth.uid(), updated_at = now()
     where key = v_key;
    if not found then raise exception 'No such category' using errcode = 'check_violation'; end if;
  end if;
  perform public._smart_event('catalogue', null, format('Category saved: %s', left(v_en, 60)), jsonb_build_object('category', v_key, 'active', coalesce(p_active, true)));
  return v_key;
end $$;

/** Make an option under a category (p_id null) or change one (its names, its order, on or off). */
create or replace function public.option_save(p_id bigint, p_category text, p_label_en text, p_label_fil text default null,
                                             p_active boolean default true, p_sort integer default null)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare v_id bigint; v_en text := nullif(trim(coalesce(p_label_en, '')), ''); v_fil text := nullif(trim(coalesce(p_label_fil, '')), '');
begin
  if not public.is_super_admin() then raise exception 'Only a super admin edits the complaint options' using errcode = 'insufficient_privilege'; end if;
  if v_en is null or char_length(v_en) < 2 then raise exception 'Name the option' using errcode = 'check_violation'; end if;
  v_fil := coalesce(v_fil, v_en);
  if p_id is null then
    if not exists (select 1 from public.complaint_categories where key = p_category) then raise exception 'No such category' using errcode = 'check_violation'; end if;
    insert into public.complaint_options (category, label_en, label_fil, sort, active, updated_by)
    values (p_category, left(v_en, 60), left(v_fil, 60),
            coalesce(p_sort, (select coalesce(max(sort), 0) + 1 from public.complaint_options where category = p_category)), coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update public.complaint_options
       set label_en = left(v_en, 60), label_fil = left(v_fil, 60), sort = coalesce(p_sort, sort), active = coalesce(p_active, active),
           updated_by = auth.uid(), updated_at = now()
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No such option' using errcode = 'check_violation'; end if;
  end if;
  perform public._smart_event('catalogue', null, format('Option saved: %s', left(v_en, 60)), jsonb_build_object('option', v_id));
  return v_id;
exception when unique_violation then
  raise exception 'That category already has an option with that name' using errcode = 'check_violation';
end $$;

revoke all on function public.category_save(text, text, text, text, text, boolean, integer), public.option_save(bigint, text, text, text, boolean, integer) from public, anon;
grant execute on function public.category_save(text, text, text, text, text, boolean, integer), public.option_save(bigint, text, text, text, boolean, integer) to authenticated;
