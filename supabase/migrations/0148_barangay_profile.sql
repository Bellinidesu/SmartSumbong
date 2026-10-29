-- =============================================================
-- SmartSumbong — 0148 The barangay's name, place and seal, from the portal
--
-- Ready for Barangay 183, step 5 (Ace, 29 Oct 2026: remove the other logos,
-- "only barangay 183 logo stays", the seal swappable in Settings; and the
-- system stays adaptable to other barangays). The name and the seal were
-- written into the portal and the app; they become one row a super admin
-- edits in Settings > Appearance:
--
--   barangay_profile   name ("Barangay 183"), place ("Zone 20, Villamor,
--                      Pasay City"), seal_url (null: the seal shipped with
--                      the portal)
--
-- Read by anyone, signed in or not: the sign-in page shows them, and they
-- are printed on every public notice the barangay posts anyway.
-- =============================================================

set search_path = public, extensions;

create table public.barangay_profile (
  id         smallint primary key default 1 check (id = 1),
  name       text not null default 'Barangay 183' check (char_length(trim(name)) between 3 and 80),
  place      text not null default 'Zone 20, Villamor, Pasay City' check (char_length(trim(place)) between 3 and 120),
  seal_url   text check (seal_url is null or seal_url ~ '^https://res\.cloudinary\.com/'),
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.barangay_profile (id) values (1);
comment on table public.barangay_profile is '0148: the barangay''s name, place and seal (null seal_url: the one shipped with the portal); one row, edited by a super admin.';

alter table public.barangay_profile enable row level security;
create policy barangay_profile_read on public.barangay_profile for select using (true);
create policy barangay_profile_super_update on public.barangay_profile for update
  using ((select public.is_super_admin())) with check ((select public.is_super_admin()));
grant select on public.barangay_profile to anon, authenticated;
grant update (name, place, seal_url, updated_by, updated_at) on public.barangay_profile to authenticated;
