-- =============================================================
-- SmartSumbong — 0025 Emergency hotlines the barangay can change
--
-- The Emergency screen is a directory: "Below are emergency services.
-- View and select the number you want to copy or dial." That is
-- View list of Emergency Service Hotline in the Submit Complaint use
-- case, and it involves no dispatch — the resident's phone dials, and
-- the barangay is not in the loop.
--
-- WHY A TABLE AND NOT A CONSTANT.
--
-- The numbers could live in the Dart source. It would work, it would be
-- offline by default, and it would cost nothing. It would also mean that
-- the day the barangay changes its duty mobile, someone has to edit
-- Flutter, rebuild an APK and get it onto every resident's phone — and
-- there is nobody to do that. This project assumes no IT plantilla and
-- three-year turnover; a hotline nobody can correct is a hotline that
-- silently rots into a wrong number during an emergency.
--
-- So: the admin portal edits them, the app reads them, and the app keeps
-- the last list it saw so a resident with no signal still has numbers to
-- call. That last part matters more than it sounds — the moment you most
-- need a hotline is not reliably the moment you have data.
--
-- STRUCTURE. Rose's design has two levels: a first screen with the
-- barangay's own numbers and two rows that open deeper lists (Police
-- Villamor Substation S59, Pasay City Hotlines), and inside those,
-- numbers grouped under headings like "Pasay City General Hospital".
-- That is a group with an optional parent, so:
--
--   hotline_groups   — "Barangay 183 Hotline", "Pasay City Hotlines",
--                      "Pasay City General Hospital" (child of the above)
--   hotline_numbers  — a number in a group, with an optional carrier
--                      label because the design shows Globe / Smart and
--                      a resident on Smart will care which they dial
--
-- READABLE WITHOUT SIGNING IN. Every other table in this schema is
-- guarded, and this one deliberately is not: emergency numbers are
-- published on tarpaulins outside the barangay hall. Making a resident
-- authenticate to read a fire hotline would be the wrong trade in the
-- one situation where seconds matter.
-- =============================================================

set search_path = public, extensions;

-- ---------- groups -------------------------------------------

create table if not exists public.hotline_groups (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.hotline_groups(id) on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 120),
  -- What the row looks like on the first screen. 'inline' shows its
  -- numbers directly; 'link' shows a chevron that opens the group.
  display     text not null default 'inline'
                check (display in ('inline', 'link')),
  icon        text,
  sort_order  smallint not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.hotline_groups is
  'Sections of the emergency directory. A group with a parent appears '
  'inside that parent''s screen — "Pasay City General Hospital" under '
  '"Pasay City Hotlines". Maintained by the barangay through the admin '
  'portal, because a hotline that only a developer can correct is one '
  'that will eventually be wrong.';

create index if not exists hotline_groups_parent_idx
  on public.hotline_groups (parent_id, sort_order)
  where is_active;

-- ---------- numbers ------------------------------------------

create table if not exists public.hotline_numbers (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.hotline_groups(id) on delete cascade,
  label       text,
  number      text not null check (length(trim(number)) between 3 and 32),
  -- Globe / Smart / DITO. The design shows this under the number, and a
  -- resident on Smart has a reason to prefer the Smart line.
  carrier     text,
  sort_order  smallint not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on column public.hotline_numbers.number is
  'Stored as the barangay types it, spacing included, because that is '
  'how it appears on their own signage and a resident matching the two '
  'should not have to squint. Dialling strips non-digits client-side.';

create index if not exists hotline_numbers_group_idx
  on public.hotline_numbers (group_id, sort_order)
  where is_active;

-- ---------- who may read, who may change ---------------------

alter table public.hotline_groups  enable row level security;
alter table public.hotline_numbers enable row level security;

-- Deliberately public. These numbers are on tarpaulins outside the
-- barangay hall; requiring a session to read a fire hotline would be the
-- wrong trade in the one case where seconds matter. It also means the
-- directory works for a resident whose account is still pending.
create policy hotline_groups_read on public.hotline_groups
  for select using (is_active);

create policy hotline_numbers_read on public.hotline_numbers
  for select using (
    is_active
    and exists (select 1 from public.hotline_groups g
                 where g.id = hotline_numbers.group_id and g.is_active)
  );

create policy hotline_groups_write on public.hotline_groups
  for all using (public.is_admin()) with check (public.is_admin());

create policy hotline_numbers_write on public.hotline_numbers
  for all using (public.is_admin()) with check (public.is_admin());

grant select on public.hotline_groups, public.hotline_numbers to anon, authenticated;

-- ---------- seed ---------------------------------------------
-- The numbers from Rose's design, which are the barangay's published
-- ones. Seeded so the app has something on first run; the barangay owns
-- them from here and the admin portal is where they change.

do $$
declare
  g_brgy    uuid;
  g_pasay   uuid;
  g_police  uuid;
  g_pnp     uuid;
  g_hosp    uuid;
  g_drrmo   uuid;
  g_health  uuid;
  g_traffic uuid;
  g_national uuid;
begin
  if exists (select 1 from public.hotline_groups) then
    return; -- already seeded; never overwrite what the barangay edited
  end if;

  insert into public.hotline_groups (name, display, sort_order)
       values ('Barangay 183 Hotline', 'inline', 10) returning id into g_brgy;
  insert into public.hotline_numbers (group_id, number, carrier, sort_order) values
    (g_brgy, '0927 126 9625', 'Globe', 10),
    (g_brgy, '0961 857 4122', 'Smart', 20),
    (g_brgy, '8807 6290',     null,    30);

  insert into public.hotline_groups (name, display, sort_order)
       values ('National Emergency', 'inline', 20) returning id into g_national;
  insert into public.hotline_numbers (group_id, label, number, sort_order) values
    (g_national, '911', '911', 10),
    (g_national, 'Fire Protection Pasay City', '(02) 8831 5555', 20);

  insert into public.hotline_groups (name, display, icon, sort_order)
       values ('Police Villamor Substation S59', 'link', 'police', 30)
       returning id into g_police;
  insert into public.hotline_numbers (group_id, number, carrier, sort_order) values
    (g_police, '0947 170 9308', 'Smart', 10),
    (g_police, '8640 0003',     null,    20);

  insert into public.hotline_groups (name, display, icon, sort_order)
       values ('Pasay City Hotlines', 'link', 'phone', 40)
       returning id into g_pasay;

  insert into public.hotline_groups (parent_id, name, sort_order)
       values (g_pasay, 'Philippine National Police Pasay Station', 10)
       returning id into g_pnp;
  insert into public.hotline_numbers (group_id, number, carrier, sort_order) values
    (g_pnp, '0956 800 5277', 'Globe', 10),
    (g_pnp, '0998 598 7922', 'Smart', 20);

  insert into public.hotline_groups (parent_id, name, sort_order)
       values (g_pasay, 'Pasay City General Hospital', 20)
       returning id into g_hosp;
  insert into public.hotline_numbers (group_id, number, sort_order) values
    (g_hosp, '8551 0121', 10);

  insert into public.hotline_groups (parent_id, name, sort_order)
       values (g_pasay, 'Pasay City Disaster Risk Reduction Management Office', 30)
       returning id into g_drrmo;
  insert into public.hotline_numbers (group_id, number, carrier, sort_order) values
    (g_drrmo, '0905 439 9111', 'Globe', 10),
    (g_drrmo, '8551 7777',     null,    20);

  insert into public.hotline_groups (parent_id, name, sort_order)
       values (g_pasay, 'City Health Office', 40)
       returning id into g_health;
  insert into public.hotline_numbers (group_id, number, sort_order) values
    (g_health, '8887272 loc. 1142', 10);

  insert into public.hotline_groups (parent_id, name, sort_order)
       values (g_pasay, 'Traffic and Parking Management Office', 50)
       returning id into g_traffic;
  insert into public.hotline_numbers (group_id, number, sort_order) values
    (g_traffic, '8889 0218', 10);
end $$;

-- Verification. Run separately.
--
--   select g.name, g.display, count(n.id) as numbers
--     from public.hotline_groups g
--     left join public.hotline_numbers n on n.group_id = g.id
--    where g.parent_id is null
--    group by g.name, g.display, g.sort_order
--    order by g.sort_order;
--
--   select p.name as section, g.name as heading, n.number, n.carrier
--     from public.hotline_groups g
--     join public.hotline_groups p on p.id = g.parent_id
--     join public.hotline_numbers n on n.group_id = g.id
--    order by p.sort_order, g.sort_order, n.sort_order;
--
-- CONFIRM WITH THE BARANGAY before deployment: the Fire Protection
-- number above is Pasay's published city line, not one Rose's design
-- specified — her frame showed the label with a slide-to-call and no
-- digits. Check it, and check whether the two mobile numbers are office
-- handsets or someone's personal phone.
