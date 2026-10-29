-- =============================================================
-- SmartSumbong — 0149 The barangay's own wording, from the portal
--
-- Ready for Barangay 183, step 5 (Ace, 29 Oct 2026: "everything in the
-- system is customizable and tunable to the needs of 183", wording and
-- labels in English and Tagalog included). Every label in the portal and
-- the app is written in the code in both languages; a super admin can now
-- replace any of them (Settings > Wording) without a new build:
--
--   wording   source: the English text as the code carries it (the key);
--             en, fil: what to show instead (null keeps the code's own)
--
-- Read by anyone, signed in or not: the app's welcome screens are worded
-- too. Deleting a row puts the code's own wording back.
-- =============================================================

set search_path = public, extensions;

create table public.wording (
  source     text primary key check (char_length(source) between 1 and 600),
  en         text check (en is null or char_length(trim(en)) between 1 and 600),
  fil        text check (fil is null or char_length(trim(fil)) between 1 and 600),
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  check (en is not null or fil is not null)
);
comment on table public.wording is '0149: the barangay''s own wording for a label of the portal or the app, keyed by the English text the code carries; edited by a super admin.';

alter table public.wording enable row level security;
create policy wording_read on public.wording for select using (true);
create policy wording_super_insert on public.wording for insert with check ((select public.is_super_admin()));
create policy wording_super_update on public.wording for update using ((select public.is_super_admin())) with check ((select public.is_super_admin()));
create policy wording_super_delete on public.wording for delete using ((select public.is_super_admin()));
grant select on public.wording to anon, authenticated;
