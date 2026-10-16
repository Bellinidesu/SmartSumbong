-- 0132: the Workspace widgets (Ace, 17 Oct 2026: all 120 approved on the aesthetics page, section 33 and 34).
--
-- The Workspace becomes each staff member's own screen: a slim rail of widgets they choose. Most widgets read what the
-- database already holds (cases, tanods, attendance, the SMART engine) or a public feed the portal reads on its server
-- (weather, sea, quakes, holidays, RSS). This migration adds only what had nowhere to live yet:
--
--   workspace_prefs      each person's widgets, open tab, own RSS feeds and watch words, and the "just for me" notes
--   workspace_settings   the barangay's choices: which alarm rules ring, whether minigames exist, shift start hours, fares
--   team_posts / reads   the Chairman's notice, shift handover, team board and announcements, with who has seen them
--   polls / poll_votes   a one-question team poll
--   staff_dates          staff birthdays
--   staff_leave          who is off and until when
--   staff_credentials    first-aid cards, tanod IDs and trainings with their expiry
--   duty_roster          who is on which shift on which day
--   patrol_checkpoints   the rounds' checkpoints, and checkpoint_scans for each time a tanod reaches one
--   shift_checkins       a one-tap "how is the shift" (calm, busy, tired); only totals are ever shown, to the lead
--   relief_tally         relief packs given out during a calamity, by street
--   safe_point_notes     capacity and open/closed for an OpenStreetMap safe point (OSM holds neither)
--   game_scores          each person's best score per minigame, for the team high scores
--
-- and the read functions the widgets use (workspace_numbers, workspace_team, workspace_alarm_db, workspace_activity,
-- workspace_photos, workspace_find, shift_mood_totals) plus record_game_score. Everything is administrators only, except
-- that a tanod may record their own checkpoint scan (for the app later). Additive: no existing table or function changes.

-- ---------------------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------------------

-- A widget id: lower-case letters and digits, up to 16 (the catalogue lives in admin/includes/widgets.php).
create or replace function public._ws_ids_ok(p_ids text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(x ~ '^[a-z0-9]{1,16}$'), true) from unnest(p_ids) as x
$$;

create or replace function public._ws_feeds_ok(p_urls text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(x ~ '^https://[^\s<>"]{4,500}$'), true) from unnest(p_urls) as x
$$;

create or replace function public._ws_words_ok(p_words text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(char_length(btrim(x)) between 1 and 40), true) from unnest(p_words) as x
$$;

create or replace function public._ws_options_ok(p_opts text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(char_length(btrim(x)) between 1 and 60), false) from unnest(p_opts) as x
$$;

-- The person who decides barangay-wide things on the Workspace: the Chairman or the Secretary. While no Chairman account
-- exists (a new install, the demo), any administrator, so the switches are never out of reach.
create or replace function public._ws_is_lead()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select u.role = 'admin' and not u.is_suspended and u.removed_at is null
           and (u.official_role in ('chairman', 'secretary')
                or not exists (select 1 from public.users c
                                where c.role = 'admin' and c.official_role = 'chairman'
                                  and not c.is_suspended and c.removed_at is null))
      from public.users u where u.id = auth.uid()), false)
$$;

revoke all on function public._ws_is_lead() from public, anon;
grant execute on function public._ws_is_lead() to authenticated;

-- Rows about a staff member may only name an administrator or a tanod who has not been removed.
create or replace function public._ws_staff_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.users u
                  where u.id = new.user_id and u.role in ('admin', 'tanod') and u.removed_at is null) then
    raise exception 'Only barangay staff can be listed here.' using errcode = 'check_violation';
  end if;
  return new;
end $$;

revoke all on function public._ws_staff_guard() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- each person's Workspace
-- ---------------------------------------------------------------------------------------------------------------------

create table public.workspace_prefs (
  user_id    uuid primary key references public.users (id) on delete cascade,
  tabs       text[] not null default '{brief,flood,ty,risk,queue,duty,due,wx}',
  tab        text,
  feeds      text[] not null default '{}',
  keywords   text[] not null default '{}',
  mine       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint workspace_prefs_tabs_check     check (cardinality(tabs) between 1 and 120 and public._ws_ids_ok(tabs)),
  constraint workspace_prefs_tab_check      check (tab is null or tab ~ '^[a-z0-9]{1,16}$'),
  constraint workspace_prefs_feeds_check    check (cardinality(feeds) <= 12 and public._ws_feeds_ok(feeds)),
  constraint workspace_prefs_keywords_check check (cardinality(keywords) <= 20 and public._ws_words_ok(keywords)),
  constraint workspace_prefs_mine_check     check (jsonb_typeof(mine) = 'object' and pg_column_size(mine) <= 32768)
);

comment on table public.workspace_prefs is '0132: one row per staff member: the Workspace widgets they chose (in order), the tab left open, their own RSS feeds and watch words, and the "just for me" widgets (checklist, sticky note, countdown, habits, notes, water, goal, personal bests) as one small JSON object.';

alter table public.workspace_prefs enable row level security;

create policy workspace_prefs_read on public.workspace_prefs
  for select using (user_id = (select auth.uid()) and (select public.is_admin()));
create policy workspace_prefs_insert on public.workspace_prefs
  for insert with check (user_id = (select auth.uid()) and (select public.is_admin()));
create policy workspace_prefs_update on public.workspace_prefs
  for update using (user_id = (select auth.uid()) and (select public.is_admin()))
  with check (user_id = (select auth.uid()) and (select public.is_admin()));
create policy workspace_prefs_delete on public.workspace_prefs
  for delete using (user_id = (select auth.uid()) and (select public.is_admin()));

-- ---------------------------------------------------------------------------------------------------------------------
-- the barangay's Workspace settings (one row)
-- ---------------------------------------------------------------------------------------------------------------------

create table public.workspace_settings (
  id            smallint primary key default 1,
  alarm_rules   text[] not null default '{red,sig3}',
  games_enabled boolean not null default false,
  shift_starts  smallint[] not null default '{6,14,22}',
  fares         jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.users (id) on delete set null,
  constraint workspace_settings_one check (id = 1),
  constraint workspace_settings_rules_check check (alarm_rules <@ array['red', 'sig3', 'urgent2h', 'deadline']::text[]),
  constraint workspace_settings_shifts_check check (cardinality(shift_starts) = 3
    and shift_starts[1] between 0 and 23 and shift_starts[2] between 0 and 23 and shift_starts[3] between 0 and 23),
  constraint workspace_settings_fares_check check (jsonb_typeof(fares) = 'object' and pg_column_size(fares) <= 2048)
);

comment on table public.workspace_settings is '0132: the barangay''s Workspace choices: which alarm rules ring on their own (red = Red rainfall warning, sig3 = wind Signal 3 or higher, urgent2h = an urgent case waits 2 hours without a tanod, deadline = a case is likely to miss its deadline), whether the minigames exist at all (off until the lead turns them on), the three shift start hours, and the fares the fare calculator uses (set by the barangay; empty until then). Changed by the Chairman or the Secretary.';

insert into public.workspace_settings (id) values (1);

create index workspace_settings_updated_by_idx on public.workspace_settings (updated_by);

alter table public.workspace_settings enable row level security;

create policy workspace_settings_read on public.workspace_settings
  for select using ((select public.is_admin()));
create policy workspace_settings_update on public.workspace_settings
  for update using ((select public._ws_is_lead())) with check ((select public._ws_is_lead()));

revoke insert, delete on public.workspace_settings from authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- notices, handovers, the team board and announcements
-- ---------------------------------------------------------------------------------------------------------------------

create table public.team_posts (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null,
  body         text not null,
  author_id    uuid not null default auth.uid() references public.users (id) on delete cascade,
  pinned_until timestamptz,
  created_at   timestamptz not null default now(),
  removed_at   timestamptz,
  constraint team_posts_kind_check check (kind in ('notice', 'handover', 'board', 'announcement')),
  constraint team_posts_body_check check (char_length(btrim(body)) between 1 and 1000
                                          and (kind <> 'board' or char_length(btrim(body)) <= 280))
);

comment on table public.team_posts is '0132: short messages between staff. notice = the Chairman''s pinned notice, announcement = a message to everyone with read receipts (both by the Chairman or the Secretary); handover = what a shift leaves for the next; board = a short line on the team board (280 characters). Removed, never deleted.';

create index team_posts_kind_idx   on public.team_posts (kind, created_at desc) where removed_at is null;
create index team_posts_author_idx on public.team_posts (author_id);

alter table public.team_posts enable row level security;

create policy team_posts_read on public.team_posts
  for select using ((select public.is_admin()));
create policy team_posts_insert on public.team_posts
  for insert with check ((select public.is_admin()) and author_id = (select auth.uid())
                         and (kind in ('handover', 'board') or (select public._ws_is_lead())));
create policy team_posts_update on public.team_posts
  for update using ((select public.is_admin()) and (author_id = (select auth.uid()) or (select public._ws_is_lead())))
  with check ((select public.is_admin()));

revoke update, delete on public.team_posts from authenticated;
grant update (pinned_until, removed_at) on public.team_posts to authenticated;

create table public.team_post_reads (
  post_id uuid not null references public.team_posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

comment on table public.team_post_reads is '0132: who has seen a team post ("seen by 7 of 9").';

create index team_post_reads_user_idx on public.team_post_reads (user_id);

alter table public.team_post_reads enable row level security;

create policy team_post_reads_read on public.team_post_reads
  for select using ((select public.is_admin()));
create policy team_post_reads_insert on public.team_post_reads
  for insert with check ((select public.is_admin()) and user_id = (select auth.uid()));

revoke update, delete on public.team_post_reads from authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- a one-question team poll
-- ---------------------------------------------------------------------------------------------------------------------

create table public.polls (
  id         uuid primary key default gen_random_uuid(),
  question   text not null,
  options    text[] not null,
  created_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  closes_at  timestamptz,
  closed_at  timestamptz,
  created_at timestamptz not null default now(),
  constraint polls_question_check check (char_length(btrim(question)) between 3 and 200),
  constraint polls_options_check  check (cardinality(options) between 2 and 6 and public._ws_options_ok(options))
);

comment on table public.polls is '0132: a one-question poll to the whole team ("Who can cover Saturday night?"), two to six answers, closed by its author or the lead, or on its own at closes_at.';

create index polls_open_idx    on public.polls (created_at desc) where closed_at is null;
create index polls_created_idx on public.polls (created_by);

alter table public.polls enable row level security;

create policy polls_read on public.polls
  for select using ((select public.is_admin()));
create policy polls_insert on public.polls
  for insert with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy polls_update on public.polls
  for update using ((select public.is_admin()) and (created_by = (select auth.uid()) or (select public._ws_is_lead())))
  with check ((select public.is_admin()));

revoke update, delete on public.polls from authenticated;
grant update (closed_at) on public.polls to authenticated;

create table public.poll_votes (
  poll_id  uuid not null references public.polls (id) on delete cascade,
  user_id  uuid not null default auth.uid() references public.users (id) on delete cascade,
  choice   smallint not null check (choice between 0 and 5),
  voted_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

comment on table public.poll_votes is '0132: one vote per person per poll; it can be changed while the poll is open.';

create index poll_votes_user_idx on public.poll_votes (user_id);

-- a vote must name one of the poll's answers, and the poll must still be open
create or replace function public._poll_vote_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.polls%rowtype;
begin
  select * into p from public.polls where id = new.poll_id;
  if p.closed_at is not null or (p.closes_at is not null and p.closes_at <= now()) then
    raise exception 'This poll is closed.' using errcode = 'check_violation';
  end if;
  if new.choice >= cardinality(p.options) then
    raise exception 'That is not one of the answers.' using errcode = 'check_violation';
  end if;
  new.voted_at := now();
  return new;
end $$;

revoke all on function public._poll_vote_guard() from public, anon, authenticated;

create trigger poll_votes_guard before insert or update on public.poll_votes
  for each row execute function public._poll_vote_guard();

alter table public.poll_votes enable row level security;

create policy poll_votes_read on public.poll_votes
  for select using ((select public.is_admin()));
create policy poll_votes_insert on public.poll_votes
  for insert with check ((select public.is_admin()) and user_id = (select auth.uid()));
create policy poll_votes_update on public.poll_votes
  for update using ((select public.is_admin()) and user_id = (select auth.uid()))
  with check ((select public.is_admin()) and user_id = (select auth.uid()));

revoke delete on public.poll_votes from authenticated;
revoke update on public.poll_votes from authenticated;
grant update (choice) on public.poll_votes to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- staff: birthdays, leave, credentials, the roster
-- ---------------------------------------------------------------------------------------------------------------------

create table public.staff_dates (
  user_id    uuid primary key references public.users (id) on delete cascade,
  birthday   date not null,
  updated_by uuid default auth.uid() references public.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint staff_dates_birthday_check check (birthday between date '1920-01-01' and current_date)
);

comment on table public.staff_dates is '0132: a staff member''s birthday, for the Birthdays widget. Administrators and tanods only.';

create index staff_dates_updated_by_idx on public.staff_dates (updated_by);

create trigger staff_dates_staff before insert or update on public.staff_dates
  for each row execute function public._ws_staff_guard();

alter table public.staff_dates enable row level security;

create policy staff_dates_read on public.staff_dates
  for select using ((select public.is_admin()));
create policy staff_dates_insert on public.staff_dates
  for insert with check ((select public.is_admin()));
create policy staff_dates_update on public.staff_dates
  for update using ((select public.is_admin())) with check ((select public.is_admin()));
create policy staff_dates_delete on public.staff_dates
  for delete using ((select public.is_admin()));

create table public.staff_leave (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  starts_on  date not null,
  ends_on    date not null,
  reason     text,
  created_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint staff_leave_dates_check  check (ends_on >= starts_on and ends_on - starts_on <= 366),
  constraint staff_leave_reason_check check (reason is null or char_length(reason) <= 200)
);

comment on table public.staff_leave is '0132: leave and days off ("Who is off").';

create index staff_leave_user_idx    on public.staff_leave (user_id, ends_on);
create index staff_leave_created_idx on public.staff_leave (created_by);

create trigger staff_leave_staff before insert or update on public.staff_leave
  for each row execute function public._ws_staff_guard();

alter table public.staff_leave enable row level security;

create policy staff_leave_read on public.staff_leave
  for select using ((select public.is_admin()));
create policy staff_leave_insert on public.staff_leave
  for insert with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy staff_leave_delete on public.staff_leave
  for delete using ((select public.is_admin()));

revoke update on public.staff_leave from authenticated;

create table public.staff_credentials (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  kind       text not null,
  label      text not null,
  expires_on date,
  created_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint staff_credentials_kind_check  check (kind in ('first_aid', 'tanod_id', 'training', 'other')),
  constraint staff_credentials_label_check check (char_length(btrim(label)) between 1 and 120)
);

comment on table public.staff_credentials is '0132: first-aid cards, tanod IDs and trainings, with the date each expires ("Trainings and IDs" warns 30 days before).';

create index staff_credentials_user_idx    on public.staff_credentials (user_id);
create index staff_credentials_expiry_idx  on public.staff_credentials (expires_on) where expires_on is not null;
create index staff_credentials_created_idx on public.staff_credentials (created_by);

create trigger staff_credentials_staff before insert or update on public.staff_credentials
  for each row execute function public._ws_staff_guard();

alter table public.staff_credentials enable row level security;

create policy staff_credentials_read on public.staff_credentials
  for select using ((select public.is_admin()));
create policy staff_credentials_insert on public.staff_credentials
  for insert with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy staff_credentials_update on public.staff_credentials
  for update using ((select public.is_admin())) with check ((select public.is_admin()));
create policy staff_credentials_delete on public.staff_credentials
  for delete using ((select public.is_admin()));

create table public.duty_roster (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  shift_date date not null,
  shift      text not null,
  created_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint duty_roster_shift_check check (shift in ('morning', 'afternoon', 'night')),
  constraint duty_roster_once unique (user_id, shift_date, shift)
);

comment on table public.duty_roster is '0132: who is on which shift on which day ("Roster this week"); also what "late" in Attendance is measured against. Shift start hours are in workspace_settings.';

create index duty_roster_day_idx     on public.duty_roster (shift_date);
create index duty_roster_created_idx on public.duty_roster (created_by);

create trigger duty_roster_staff before insert or update on public.duty_roster
  for each row execute function public._ws_staff_guard();

alter table public.duty_roster enable row level security;

create policy duty_roster_read on public.duty_roster
  for select using ((select public.is_admin()));
create policy duty_roster_insert on public.duty_roster
  for insert with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy duty_roster_delete on public.duty_roster
  for delete using ((select public.is_admin()));

revoke update on public.duty_roster from authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- patrol checkpoints
-- ---------------------------------------------------------------------------------------------------------------------

create table public.patrol_checkpoints (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  lat        double precision not null,
  lng        double precision not null,
  sort_order smallint not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  constraint patrol_checkpoints_name_check check (char_length(btrim(name)) between 1 and 120),
  constraint patrol_checkpoints_where      check (lat between 4 and 22 and lng between 116 and 127)
);

comment on table public.patrol_checkpoints is '0132: the places a patrol round must pass, in order.';

alter table public.patrol_checkpoints enable row level security;

create policy patrol_checkpoints_read on public.patrol_checkpoints
  for select using ((select public.is_admin()) or (select public.my_role()) = 'tanod');
create policy patrol_checkpoints_insert on public.patrol_checkpoints
  for insert with check ((select public.is_admin()));
create policy patrol_checkpoints_update on public.patrol_checkpoints
  for update using ((select public.is_admin())) with check ((select public.is_admin()));
create policy patrol_checkpoints_delete on public.patrol_checkpoints
  for delete using ((select public.is_admin()));

create table public.checkpoint_scans (
  id            uuid primary key default gen_random_uuid(),
  checkpoint_id uuid not null references public.patrol_checkpoints (id) on delete cascade,
  tanod_id      uuid not null references public.users (id) on delete cascade,
  scanned_at    timestamptz not null default now(),
  recorded_by   uuid not null default auth.uid() references public.users (id) on delete cascade
);

comment on table public.checkpoint_scans is '0132: a tanod reached a checkpoint. Recorded by an administrator from the portal, or by the tanod for themself (the app, later).';

create index checkpoint_scans_cp_idx       on public.checkpoint_scans (checkpoint_id, scanned_at desc);
create index checkpoint_scans_tanod_idx    on public.checkpoint_scans (tanod_id, scanned_at desc);
create index checkpoint_scans_recorded_idx on public.checkpoint_scans (recorded_by);

create or replace function public._scan_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.users u where u.id = new.tanod_id and u.role = 'tanod' and u.removed_at is null) then
    raise exception 'Only a tanod can reach a checkpoint.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.patrol_checkpoints c where c.id = new.checkpoint_id and c.is_active) then
    raise exception 'That checkpoint is not in use.' using errcode = 'check_violation';
  end if;
  new.scanned_at := now();
  return new;
end $$;

revoke all on function public._scan_guard() from public, anon, authenticated;

create trigger checkpoint_scans_guard before insert on public.checkpoint_scans
  for each row execute function public._scan_guard();

alter table public.checkpoint_scans enable row level security;

create policy checkpoint_scans_read on public.checkpoint_scans
  for select using ((select public.is_admin()) or tanod_id = (select auth.uid()));
create policy checkpoint_scans_insert on public.checkpoint_scans
  for insert with check (recorded_by = (select auth.uid())
                         and ((select public.is_admin()) or tanod_id = (select auth.uid())));
create policy checkpoint_scans_delete on public.checkpoint_scans
  for delete using ((select public.is_admin()));

revoke update on public.checkpoint_scans from authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- how is the shift (only totals are ever shown)
-- ---------------------------------------------------------------------------------------------------------------------

create table public.shift_checkins (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.users (id) on delete cascade,
  shift_date date not null default ((now() at time zone 'Asia/Manila')::date),
  mood       text not null,
  created_at timestamptz not null default now(),
  constraint shift_checkins_mood_check check (mood in ('calm', 'busy', 'tired')),
  constraint shift_checkins_once unique (user_id, shift_date)
);

comment on table public.shift_checkins is '0132: a one-tap check-in per person per day. Each person sees only their own; the lead sees only the day''s totals (shift_mood_totals), never who.';

alter table public.shift_checkins enable row level security;

create policy shift_checkins_read on public.shift_checkins
  for select using (user_id = (select auth.uid()) and (select public.is_admin()));
create policy shift_checkins_insert on public.shift_checkins
  for insert with check (user_id = (select auth.uid()) and (select public.is_admin())
                         and shift_date = (now() at time zone 'Asia/Manila')::date);
create policy shift_checkins_update on public.shift_checkins
  for update using (user_id = (select auth.uid()) and (select public.is_admin())
                    and shift_date = (now() at time zone 'Asia/Manila')::date)
  with check (user_id = (select auth.uid()));

revoke delete on public.shift_checkins from authenticated;
revoke update on public.shift_checkins from authenticated;
grant update (mood) on public.shift_checkins to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- relief packs and safe-point notes
-- ---------------------------------------------------------------------------------------------------------------------

create table public.relief_tally (
  id          uuid primary key default gen_random_uuid(),
  event       text not null,
  street      text not null,
  packs       integer not null,
  given_on    date not null default ((now() at time zone 'Asia/Manila')::date),
  recorded_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint relief_tally_event_check  check (char_length(btrim(event)) between 1 and 120),
  constraint relief_tally_street_check check (char_length(btrim(street)) between 1 and 120),
  constraint relief_tally_packs_check  check (packs between 1 and 100000)
);

comment on table public.relief_tally is '0132: relief packs given out during a calamity, one line per street and handing-out.';

create index relief_tally_event_idx    on public.relief_tally (event, given_on desc);
create index relief_tally_recorded_idx on public.relief_tally (recorded_by);

alter table public.relief_tally enable row level security;

create policy relief_tally_read on public.relief_tally
  for select using ((select public.is_admin()));
create policy relief_tally_insert on public.relief_tally
  for insert with check ((select public.is_admin()) and recorded_by = (select auth.uid()));
create policy relief_tally_delete on public.relief_tally
  for delete using ((select public.is_admin()) and (recorded_by = (select auth.uid()) or (select public._ws_is_lead())));

revoke update on public.relief_tally from authenticated;

create table public.safe_point_notes (
  osm_id     text primary key,
  name       text,
  capacity   integer,
  status     text not null default 'unknown',
  note       text,
  updated_by uuid default auth.uid() references public.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint safe_point_notes_id_check       check (osm_id ~ '^(node|way|relation)/[0-9]{1,15}$'),
  constraint safe_point_notes_name_check     check (name is null or char_length(name) <= 160),
  constraint safe_point_notes_capacity_check check (capacity is null or capacity between 0 and 100000),
  constraint safe_point_notes_status_check   check (status in ('open', 'closed', 'full', 'unknown')),
  constraint safe_point_notes_note_check     check (note is null or char_length(note) <= 300)
);

comment on table public.safe_point_notes is '0132: what OpenStreetMap does not hold about an evacuation centre or other safe point: how many people it takes and whether it is open. Keyed by the OSM element (node/123). Set by the Chairman or the Secretary.';

create index safe_point_notes_updated_by_idx on public.safe_point_notes (updated_by);

alter table public.safe_point_notes enable row level security;

create policy safe_point_notes_read on public.safe_point_notes
  for select using ((select public.is_admin()));
create policy safe_point_notes_insert on public.safe_point_notes
  for insert with check ((select public._ws_is_lead()));
create policy safe_point_notes_update on public.safe_point_notes
  for update using ((select public._ws_is_lead())) with check ((select public._ws_is_lead()));
create policy safe_point_notes_delete on public.safe_point_notes
  for delete using ((select public._ws_is_lead()));

-- ---------------------------------------------------------------------------------------------------------------------
-- minigame bests
-- ---------------------------------------------------------------------------------------------------------------------

create table public.game_scores (
  user_id    uuid not null default auth.uid() references public.users (id) on delete cascade,
  game       text not null,
  best       numeric not null,
  plays      integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, game)
);

comment on table public.game_scores is '0132: each person''s best per minigame, written only by record_game_score() (which knows whether lower or higher is better), read by everyone for the team high scores.';

alter table public.game_scores enable row level security;

create policy game_scores_read on public.game_scores
  for select using ((select public.is_admin()));

revoke insert, update, delete on public.game_scores from authenticated;

-- higher is better unless listed in v_low; the ranges keep a typo or a tampered request from topping the board
create or replace function public.record_game_score(p_game text, p_score numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_low  text[] := array['mem', 'react', 'whack', 'wordl', 'sudoku', 'mines'];
  v_max  numeric;
  v_old  numeric;
  v_best numeric;
  v_new  boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Only staff can record a score.' using errcode = 'insufficient_privilege';
  end if;
  if not coalesce((select games_enabled from public.workspace_settings where id = 1), false) then
    raise exception 'Minigames are switched off.' using errcode = 'check_violation';
  end if;
  v_max := case p_game
             when 'ttt' then 10000 when 'mem' then 500 when 'react' then 5000 when 'whack' then 600000
             when 'hl' then 1000 when 'rps' then 10000 when 'snake' then 10000 when 'g2048' then 1000000
             when 'wordl' then 6 when 'sudoku' then 86400 when 'mines' then 86400 when 'quiz' then 10
             when 'simon' then 1000 when 'type' then 300 end;
  if v_max is null then
    raise exception 'Unknown game.' using errcode = 'invalid_parameter_value';
  end if;
  if p_score is null or p_score < 0 or p_score > v_max then
    raise exception 'That score is out of range.' using errcode = 'invalid_parameter_value';
  end if;

  select best into v_old from public.game_scores where user_id = auth.uid() and game = p_game for update;
  if v_old is null then
    insert into public.game_scores (user_id, game, best) values (auth.uid(), p_game, p_score);
    v_best := p_score; v_new := true;
  else
    v_new := case when p_game = any (v_low) then p_score < v_old else p_score > v_old end;
    v_best := case when v_new then p_score else v_old end;
    update public.game_scores set best = v_best, plays = plays + 1, updated_at = now()
     where user_id = auth.uid() and game = p_game;
  end if;
  return jsonb_build_object('best', v_best, 'new_best', v_new, 'lower_is_better', p_game = any (v_low));
end $$;

revoke all on function public.record_game_score(text, numeric) from public, anon;
grant execute on function public.record_game_score(text, numeric) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- reads for the widgets
-- ---------------------------------------------------------------------------------------------------------------------

-- Cases and numbers: the stacked status bar, cases by category, cases per day and per hour, first-response pace,
-- this month against last, today's resolved cases, the busiest streets and the escalations. One call for all of them.
create or replace function public.workspace_numbers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_today  date := (now() at time zone 'Asia/Manila')::date;
  v_day0   timestamptz := v_today::timestamp at time zone 'Asia/Manila';
  v_month0 timestamptz := date_trunc('month', v_today)::timestamp at time zone 'Asia/Manila';
  v_prev0  timestamptz := (date_trunc('month', v_today) - interval '1 month')::timestamp at time zone 'Asia/Manila';
  v_open   public.report_status[] := array['pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation']::public.report_status[];
  v_done   public.report_status[] := array['resolved', 'closed', 'archived']::public.report_status[];
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only staff can see the Workspace numbers.' using errcode = 'insufficient_privilege';
  end if;

  with live as (select * from public.reports where deleted_at is null),
  month_rows as (select * from live where created_at >= v_month0),
  first_touch as (
    select r.id, r.created_at,
           least((select min(sl.created_at) from public.status_logs sl
                   where sl.report_id = r.id and not sl.is_system and sl.new_status <> 'pending_review'),
                 (select min(d.assigned_at) from public.dispatches d where d.report_id = r.id)) as touched_at
      from live r where r.created_at >= v_day0 - interval '6 days'
  )
  select jsonb_build_object(
    'status', (select jsonb_build_object(
                 'waiting',     count(*) filter (where status in ('pending_review', 'validated')),
                 'in_progress', count(*) filter (where status in ('assigned', 'in_progress', 'offline_investigation')),
                 'resolved',    count(*) filter (where status = any (v_done)),
                 'rejected',    count(*) filter (where status in ('rejected', 'cancelled')))
                 from month_rows),
    'by_category', (select coalesce(jsonb_agg(jsonb_build_object('category', category, 'n', n) order by n desc, category), '[]'::jsonb)
                      from (select category, count(*) as n from month_rows group by category) c),
    'per_day', (select jsonb_agg(jsonb_build_object('d', g.d, 'n', coalesce(c.n, 0)) order by g.d)
                  from (select (v_today - k) as d from generate_series(0, 29) k) g
                  left join (select (created_at at time zone 'Asia/Manila')::date as d, count(*) as n
                               from live where created_at >= v_day0 - interval '29 days' group by 1) c on c.d = g.d),
    'per_hour', (select jsonb_agg(coalesce(h.n, 0) order by s.hr)
                   from generate_series(0, 23) s(hr)
                   left join (select extract(hour from created_at at time zone 'Asia/Manila')::int as hr, count(*) as n
                                from live where created_at >= now() - interval '90 days' group by 1) h on h.hr = s.hr),
    'pace', (select jsonb_build_object(
               'days', (select jsonb_agg(jsonb_build_object('d', g.d, 'hours', p.h) order by g.d)
                          from (select (v_today - k) as d from generate_series(0, 6) k) g
                          left join (select (f.created_at at time zone 'Asia/Manila')::date as d,
                                            round(avg(extract(epoch from (f.touched_at - f.created_at)) / 3600)::numeric, 1) as h
                                       from first_touch f where f.touched_at is not null group by 1) p on p.d = g.d),
               'avg_hours', (select round(avg(extract(epoch from (touched_at - created_at)) / 3600)::numeric, 1) from first_touch where touched_at is not null),
               'fastest_minutes', (select round(min(extract(epoch from (touched_at - created_at)) / 60)) from first_touch where touched_at is not null),
               'slowest_hours', (select round((max(extract(epoch from (touched_at - created_at)) / 3600))::numeric, 1) from first_touch where touched_at is not null),
               'still_waiting', (select count(*) from first_touch f join live r on r.id = f.id
                                  where f.touched_at is null and r.status = any (v_open)))),
    'month', (select jsonb_build_object(
                'received', (select count(*) from month_rows),
                'resolved', (select count(*) from live where resolved_at >= v_month0),
                'resolved_pct', (select case when count(*) = 0 then null
                                             else round(100.0 * count(*) filter (where status = any (v_done)) / count(*)) end from month_rows),
                'avg_hours', (select round(avg(extract(epoch from (resolved_at - created_at)) / 3600)::numeric, 1)
                                from live where resolved_at >= v_month0),
                'overdue', (select count(*) from live where status = any (v_open) and due_at < now()),
                'escalated', (select count(*) from live where coalesce(handed_up_at, escalated_at) >= v_month0),
                'last_received', (select count(*) from live where created_at >= v_prev0 and created_at < v_month0),
                'last_resolved_pct', (select case when count(*) = 0 then null
                                                  else round(100.0 * count(*) filter (where status = any (v_done)) / count(*)) end
                                        from live where created_at >= v_prev0 and created_at < v_month0))),
    'resolved_today', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
                         select jsonb_build_object('report_id', r.id, 'tracking_id', r.tracking_id, 'subject', r.subject,
                                                   'sensitive', r.is_sensitive, 'at', r.resolved_at,
                                                   'by', (select public.display_name(u.full_name) from public.status_logs sl
                                                            join public.users u on u.id = sl.changed_by
                                                           where sl.report_id = r.id and sl.new_status = 'resolved'
                                                           order by sl.created_at desc limit 1)) as x
                           from live r where r.resolved_at >= v_day0 order by r.resolved_at desc limit 8) t),
    'streets', (select coalesce(jsonb_agg(jsonb_build_object('place', place, 'open', n, 'category', top) order by n desc, place), '[]'::jsonb)
                  from (select btrim(location_label) as place, count(*) as n, mode() within group (order by category) as top
                          from live where status = any (v_open) and nullif(btrim(location_label), '') is not null
                         group by 1 order by 2 desc, 1 limit 5) s),
    'escalations', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
                      select jsonb_build_object('report_id', r.id, 'tracking_id', r.tracking_id, 'subject', r.subject,
                                                'sensitive', r.is_sensitive, 'tier', r.tier, 'to', r.higher_official,
                                                'at', coalesce(r.handed_up_at, r.escalated_at, r.updated_at)) as x
                        from live r
                       where r.status = any (v_open) and (r.tier > 0 or r.higher_official is not null)
                       order by coalesce(r.handed_up_at, r.escalated_at, r.updated_at) desc limit 6) e),
    'escalation_requests', (select count(*) from public.escalation_requests where status = 'pending')
  ) into v;
  return v;
end $$;

revoke all on function public.workspace_numbers() from public, anon;
grant execute on function public.workspace_numbers() to authenticated;

-- Team: the tanods and their state, attendance today and hours this week (late against the roster), the roster for the
-- coming week, who is off, credentials running out, birthdays in the next two weeks, the directory and what waits for
-- approval.
create or replace function public.workspace_team()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_today  date := (now() at time zone 'Asia/Manila')::date;
  v_day0   timestamptz := v_today::timestamp at time zone 'Asia/Manila';
  v_week0  timestamptz := date_trunc('week', v_today::timestamp) at time zone 'Asia/Manila';
  v_starts smallint[];
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only staff can see the team.' using errcode = 'insufficient_privilege';
  end if;
  select shift_starts into v_starts from public.workspace_settings where id = 1;
  v_starts := coalesce(v_starts, array[6, 14, 22]::smallint[]);

  with staff as (
    select u.* from public.users u
     where u.role in ('admin', 'tanod') and u.removed_at is null and not u.is_suspended and not u.is_retired
  ),
  logs as (
    select a.tanod_id, a.duty_status, a.logged_at,
           lead(a.logged_at) over (partition by a.tanod_id order by a.logged_at) as next_at
      from public.attendance a where a.logged_at >= v_week0 - interval '7 days'
  ),
  hours as (
    select tanod_id, round((sum(extract(epoch from (least(coalesce(next_at, now()), now()) - greatest(logged_at, v_week0)))) / 3600)::numeric, 1) as h
      from logs
     where duty_status = 'on_duty' and least(coalesce(next_at, now()), now()) > greatest(logged_at, v_week0)
     group by tanod_id
  ),
  first_on as (
    select tanod_id, min(logged_at) as at from public.attendance
     where logged_at >= v_day0 and duty_status = 'on_duty' group by tanod_id
  ),
  rostered as (
    select dr.user_id, min(case dr.shift when 'morning' then v_starts[1] when 'afternoon' then v_starts[2] else v_starts[3] end) as start_hr
      from public.duty_roster dr where dr.shift_date = v_today group by dr.user_id
  )
  select jsonb_build_object(
    'tanods', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', s.id, 'name', s.full_name, 'duty', coalesce(s.duty_status::text, 'offline'),
                  'since', (select max(a.logged_at) from public.attendance a where a.tanod_id = s.id),
                  'jobs', (select count(*) from public.dispatches d where d.tanod_id = s.id and d.state in ('assigned', 'accepted')),
                  'first_on', f.at,
                  'rostered_hour', ro.start_hr,
                  'late_minutes', case when f.at is not null and ro.start_hr is not null
                                       then greatest(0, round(extract(epoch from (f.at - (v_day0 + make_interval(hours => ro.start_hr)))) / 60))::int end,
                  'hours_week', coalesce(h.h, 0)) order by s.full_name), '[]'::jsonb)
                 from staff s
                 left join first_on f on f.tanod_id = s.id
                 left join rostered ro on ro.user_id = s.id
                 left join hours h on h.tanod_id = s.id
                where s.role = 'tanod'),
    'roster', (select coalesce(jsonb_agg(jsonb_build_object('id', dr.id, 'date', dr.shift_date, 'shift', dr.shift,
                                                            'user_id', dr.user_id, 'name', u.full_name, 'role', u.role)
                                         order by dr.shift_date, array_position(array['morning', 'afternoon', 'night'], dr.shift), u.full_name), '[]'::jsonb)
                 from public.duty_roster dr join staff u on u.id = dr.user_id
                where dr.shift_date between v_today and v_today + 6),
    'shift_starts', to_jsonb(v_starts),
    'leave', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'user_id', l.user_id, 'name', u.full_name,
                                                           'from', l.starts_on, 'to', l.ends_on, 'reason', l.reason,
                                                           'now', v_today between l.starts_on and l.ends_on)
                                        order by l.starts_on), '[]'::jsonb)
                from public.staff_leave l join staff u on u.id = l.user_id
               where l.ends_on >= v_today and l.starts_on <= v_today + 30),
    'credentials', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'user_id', c.user_id, 'name', u.full_name,
                                                                 'kind', c.kind, 'label', c.label, 'expires_on', c.expires_on,
                                                                 'days_left', c.expires_on - v_today)
                                              order by c.expires_on nulls last), '[]'::jsonb)
                      from public.staff_credentials c join staff u on u.id = c.user_id),
    'birthdays', (select coalesce(jsonb_agg(jsonb_build_object('user_id', sd.user_id, 'name', u.full_name, 'on', g.d,
                                                               'in_days', g.d - v_today) order by g.d, u.full_name), '[]'::jsonb)
                    from public.staff_dates sd join staff u on u.id = sd.user_id
                    join (select x::date as d from generate_series(v_today, v_today + 13, interval '1 day') x) g
                      on to_char(g.d, 'MMDD') = to_char(sd.birthday, 'MMDD')),
    'directory', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.full_name, 'role', s.role,
                                                               'position', s.official_role, 'committee', s.committee,
                                                               'mobile', s.mobile_number, 'duty', s.duty_status)
                                            order by case s.official_role when 'chairman' then 0 when 'kagawad' then 1 when 'secretary' then 2 else 3 end,
                                                     s.role desc, s.full_name), '[]'::jsonb)
                    from staff s),
    'waiting', jsonb_build_object(
                 'residents', (select count(*) from public.users where role = 'resident' and verification_status = 'pending' and removed_at is null),
                 'residents_oldest', (select min(verification_submitted_at) from public.users where role = 'resident' and verification_status = 'pending' and removed_at is null),
                 'profile_requests', (select count(*) from public.profile_requests where status = 'pending'),
                 'retirements', (select count(*) from public.retirement_requests where status = 'pending'),
                 'escalations', (select count(*) from public.escalation_requests where status = 'pending'))
  ) into v;
  return v;
end $$;

revoke all on function public.workspace_team() from public, anon;
grant execute on function public.workspace_team() to authenticated;

-- The two alarm rules the database can judge: an urgent case waiting over two hours with no tanod, and a case likely to
-- miss its deadline. The weather rules (Red warning, Signal 3) are judged by the portal from PAGASA (hazards).
create or replace function public.workspace_alarm_db()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
begin
  if not public.is_admin() then
    raise exception 'Only staff can see the alarm.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'urgent2h', (select coalesce(jsonb_agg(jsonb_build_object('report_id', r.id, 'tracking_id', r.tracking_id,
                                                              'hours', round((extract(epoch from (now() - coalesce(r.awaiting_unit_since, r.created_at))) / 3600)::numeric, 1))
                                           order by coalesce(r.awaiting_unit_since, r.created_at)), '[]'::jsonb)
                   from public.reports r join public.report_triage t on t.report_id = r.id
                  where r.deleted_at is null and r.status in ('pending_review', 'validated') and t.effective_level = 'urgent'
                    and coalesce(r.awaiting_unit_since, r.created_at) < now() - interval '2 hours'
                    and not exists (select 1 from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'))),
    'deadline', (select coalesce(jsonb_agg(jsonb_build_object('report_id', d.report_id, 'tracking_id', d.tracking_id,
                                                              'hours_left', d.hours_left) order by d.hours_left), '[]'::jsonb)
                   from public._smart_deadline_risk() d where d.risk = 'high'),
    'rules', (select to_jsonb(alarm_rules) from public.workspace_settings where id = 1));
end $$;

revoke all on function public.workspace_alarm_db() from public, anon;
grant execute on function public.workspace_alarm_db() to authenticated;

-- Latest activity: new cases, status changes, tanods sent, cases taken and passed up, newest first.
create or replace function public.workspace_activity(p_limit integer default 12)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_n integer := greatest(1, least(coalesce(p_limit, 12), 50));
begin
  if not public.is_admin() then
    raise exception 'Only staff can see the activity.' using errcode = 'insufficient_privilege';
  end if;
  return (select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]'::jsonb) from (
    select x from (
      (select jsonb_build_object('kind', 'new', 'at', r.created_at, 'report_id', r.id, 'tracking_id', r.tracking_id,
                                 'subject', r.subject, 'sensitive', r.is_sensitive, 'category', r.category, 'place', r.location_label) as x
         from public.reports r where r.deleted_at is null order by r.created_at desc limit v_n)
      union all
      (select jsonb_build_object('kind', 'status', 'at', sl.created_at, 'report_id', r.id, 'tracking_id', r.tracking_id,
                                 'subject', r.subject, 'sensitive', r.is_sensitive, 'status', sl.new_status,
                                 'by', public.display_name(u.full_name))
         from public.status_logs sl join public.reports r on r.id = sl.report_id and r.deleted_at is null
         left join public.users u on u.id = sl.changed_by
        where not sl.is_system and sl.new_status <> 'pending_review'
        order by sl.created_at desc limit v_n)
      union all
      (select jsonb_build_object('kind', 'dispatch', 'at', d.assigned_at, 'report_id', r.id, 'tracking_id', r.tracking_id,
                                 'subject', r.subject, 'sensitive', r.is_sensitive,
                                 'tanod', public.display_name(t.full_name), 'by', public.display_name(a.full_name))
         from public.dispatches d join public.reports r on r.id = d.report_id and r.deleted_at is null
         join public.users t on t.id = d.tanod_id left join public.users a on a.id = d.assigned_by
        order by d.assigned_at desc limit v_n)
      union all
      (select jsonb_build_object('kind', 'handler_' || h.action, 'at', h.created_at, 'report_id', r.id, 'tracking_id', r.tracking_id,
                                 'subject', r.subject, 'sensitive', r.is_sensitive, 'by', public.display_name(u.full_name))
         from public.case_handler_log h join public.reports r on r.id = h.report_id and r.deleted_at is null
         join public.users u on u.id = h.admin_id
        order by h.created_at desc limit v_n)
    ) all_rows order by (x->>'at')::timestamptz desc limit v_n
  ) t);
end $$;

revoke all on function public.workspace_activity(integer) from public, anon;
grant execute on function public.workspace_activity(integer) to authenticated;

-- Latest photos: what residents filed and what tanods and staff attached, images only, never from a sensitive case.
create or replace function public.workspace_photos(p_limit integer default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_n integer := greatest(1, least(coalesce(p_limit, 8), 24));
begin
  if not public.is_admin() then
    raise exception 'Only staff can see the photos.' using errcode = 'insufficient_privilege';
  end if;
  return (select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]'::jsonb) from (
    select x from (
      (select jsonb_build_object('url', m.media_url, 'at', m.uploaded_at, 'from', 'resident', 'report_id', r.id, 'tracking_id', r.tracking_id) as x
         from public.report_media m join public.reports r on r.id = m.report_id
        where r.deleted_at is null and not r.is_sensitive and m.mime_type like 'image/%'
        order by m.uploaded_at desc limit v_n)
      union all
      (select jsonb_build_object('url', e.media_url, 'at', e.created_at, 'from', 'staff', 'report_id', r.id, 'tracking_id', r.tracking_id)
         from public.report_evidence e join public.reports r on r.id = e.report_id
        where r.deleted_at is null and not r.is_sensitive
        order by e.created_at desc limit v_n)
      union all
      (select jsonb_build_object('url', dm.media_url, 'at', dm.uploaded_at, 'from', 'tanod', 'report_id', r.id, 'tracking_id', r.tracking_id)
         from public.dispatch_media dm join public.dispatches d on d.id = dm.dispatch_id
         join public.reports r on r.id = d.report_id
        where r.deleted_at is null and not r.is_sensitive and dm.mime_type like 'image/%'
        order by dm.uploaded_at desc limit v_n)
    ) all_rows order by (x->>'at')::timestamptz desc limit v_n
  ) t);
end $$;

revoke all on function public.workspace_photos(integer) from public, anon;
grant execute on function public.workspace_photos(integer) to authenticated;

-- Find a case: by tracking number, subject or place. The text is matched literally (no wildcards from the person).
create or replace function public.workspace_find(p_q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_q text := btrim(coalesce(p_q, ''));
  v_like text;
begin
  if not public.is_admin() then
    raise exception 'Only staff can search cases.' using errcode = 'insufficient_privilege';
  end if;
  if char_length(v_q) < 2 then
    return '[]'::jsonb;
  end if;
  v_q := left(v_q, 60);
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return (select coalesce(jsonb_agg(jsonb_build_object('report_id', r.id, 'tracking_id', r.tracking_id, 'subject', r.subject,
                                                        'status', r.status, 'category', r.category, 'place', r.location_label,
                                                        'sensitive', r.is_sensitive, 'created_at', r.created_at)
                                     order by (r.tracking_id ilike v_like) desc, r.created_at desc), '[]'::jsonb)
            from (select * from public.reports r
                   where r.deleted_at is null
                     and (r.tracking_id ilike v_like or r.subject ilike v_like or r.location_label ilike v_like)
                   order by r.created_at desc limit 8) r);
end $$;

revoke all on function public.workspace_find(text) from public, anon;
grant execute on function public.workspace_find(text) to authenticated;

-- How is the shift: the day's totals, for the lead only, and only once at least three people have answered, so a total
-- can never point at one person.
create or replace function public.shift_mood_totals(p_date date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day date := coalesce(p_date, (now() at time zone 'Asia/Manila')::date);
  v_total integer;
begin
  if not public._ws_is_lead() then
    raise exception 'Only the Chairman or the Secretary can see the totals.' using errcode = 'insufficient_privilege';
  end if;
  select count(*) into v_total from public.shift_checkins where shift_date = v_day;
  if v_total < 3 then
    return jsonb_build_object('date', v_day, 'answered', v_total, 'hidden', true);
  end if;
  return (select jsonb_build_object('date', v_day, 'answered', v_total, 'hidden', false,
                                    'calm', count(*) filter (where mood = 'calm'),
                                    'busy', count(*) filter (where mood = 'busy'),
                                    'tired', count(*) filter (where mood = 'tired'))
            from public.shift_checkins where shift_date = v_day);
end $$;

revoke all on function public.shift_mood_totals(date) from public, anon;
grant execute on function public.shift_mood_totals(date) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- writes that are one row per person: saved with the caller's own rights, so the policies above still decide
-- ---------------------------------------------------------------------------------------------------------------------

-- Save the caller's Workspace. A null argument keeps what is there.
create or replace function public.workspace_save(p_tabs text[] default null, p_tab text default null, p_feeds text[] default null,
                                                 p_keywords text[] default null, p_mine jsonb default null)
returns void
language sql
security invoker
set search_path = public
as $$
  insert into public.workspace_prefs as w (user_id, tabs, tab, feeds, keywords, mine)
  values (auth.uid(), coalesce(p_tabs, '{brief,flood,ty,risk,queue,duty,due,wx}'), p_tab, coalesce(p_feeds, '{}'),
          coalesce(p_keywords, '{}'), coalesce(p_mine, '{}'::jsonb))
  on conflict (user_id) do update
     set tabs = coalesce(p_tabs, w.tabs), tab = coalesce(p_tab, w.tab), feeds = coalesce(p_feeds, w.feeds),
         keywords = coalesce(p_keywords, w.keywords), mine = coalesce(p_mine, w.mine), updated_at = now()
$$;

revoke all on function public.workspace_save(text[], text, text[], text[], jsonb) from public, anon;
grant execute on function public.workspace_save(text[], text, text[], text[], jsonb) to authenticated;

-- Vote, or change a vote while the poll is open.
create or replace function public.poll_vote(p_poll uuid, p_choice smallint)
returns void
language sql
security invoker
set search_path = public
as $$
  insert into public.poll_votes as v (poll_id, user_id, choice) values (p_poll, auth.uid(), p_choice)
  on conflict (poll_id, user_id) do update set choice = excluded.choice
$$;

revoke all on function public.poll_vote(uuid, smallint) from public, anon;
grant execute on function public.poll_vote(uuid, smallint) to authenticated;

-- Today's check-in, or change it.
create or replace function public.shift_checkin(p_mood text)
returns void
language sql
security invoker
set search_path = public
as $$
  insert into public.shift_checkins as s (user_id, mood) values (auth.uid(), p_mood)
  on conflict (user_id, shift_date) do update set mood = excluded.mood
$$;

revoke all on function public.shift_checkin(text) from public, anon;
grant execute on function public.shift_checkin(text) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- table privileges: nothing for anonymous visitors
-- ---------------------------------------------------------------------------------------------------------------------

revoke all on public.workspace_prefs, public.workspace_settings, public.team_posts, public.team_post_reads, public.polls,
              public.poll_votes, public.staff_dates, public.staff_leave, public.staff_credentials, public.duty_roster,
              public.patrol_checkpoints, public.checkpoint_scans, public.shift_checkins, public.relief_tally,
              public.safe_point_notes, public.game_scores
  from anon;
