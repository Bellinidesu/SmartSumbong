-- 0107: Look around, sent to a tanod (Bellinist phase 5b, 9 Oct 2026).
--
-- On Spatial Distribution an admin can open Look around for a complaint (the
-- street as Mapillary has it, with the resident's photos standing in it) and
-- send it to the tanod who is going: a note, the street image to open, which
-- way the spot lies from where that view was taken, and whether the
-- resident's photos go too. One row per send.
--
-- Additive only: a table, and one new notification kind. The apps read
-- notification kinds as plain text, so an older build shows it as a
-- notification with its message.

alter type notification_kind add value if not exists 'look_around';

create table public.look_shares (
  id                 uuid primary key default gen_random_uuid(),
  report_id          uuid not null references public.reports (id) on delete cascade,
  tanod_id           uuid not null references public.users (id) on delete cascade,
  sent_by            uuid not null references public.users (id),
  message            text not null check (char_length(message) between 1 and 600),
  mapillary_image_id text,
  image_captured_at  timestamptz,
  spot_dir           text check (spot_dir in ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')),
  spot_metres        integer check (spot_metres is null or spot_metres between 0 and 1000),
  include_photos     boolean not null default true,
  created_at         timestamptz not null default now(),
  read_at            timestamptz
);

create index look_shares_tanod_idx  on public.look_shares (tanod_id, created_at desc);
create index look_shares_report_idx on public.look_shares (report_id);

alter table public.look_shares enable row level security;

-- Admins read and send; a tanod reads what was sent to them and marks it
-- seen, and nothing else.
create policy look_shares_admin_all on public.look_shares
  for all using (public.is_admin()) with check (public.is_admin() and sent_by = auth.uid());
create policy look_shares_tanod_read on public.look_shares
  for select using (tanod_id = auth.uid());
create policy look_shares_tanod_seen on public.look_shares
  for update using (tanod_id = auth.uid()) with check (tanod_id = auth.uid());

revoke update on public.look_shares from authenticated;
grant  update (read_at) on public.look_shares to authenticated;
