-- =============================================================
-- SmartSumbong — 0143 The command center (SMART Iteration 4)
--
-- Spatial Distribution can turn into a command center for one situation
-- at a time: Fire Surroundings, Quake Check, Flood Watch or Typhoon Board.
-- An administrator turns a mode on, or accepts SMART's suggestion; SMART
-- turns one on by itself only when the auto switch is on (it is off unless
-- an administrator turns it on). SMART can switch a mode on; only a person
-- switches it off, with a handover note.
--
-- Nothing here predicts. Every mode shows what residents reported, where,
-- and when, with what is near it: "reported knee-deep", "within 100 m",
-- "as of 3:40 PM", "tagged by 3 reports". Depth uses MMDA's flood gauge,
-- the scale barangays already use. Sensitive cases (0130) stay off the
-- board and the hall display.
--
-- The framework every mode shares:
--   command_modes / command_tags / command_words   what each mode reads for
--   _command_read(text)        the mode words in a report (cached per report)
--   _command_cell(geog, m)     a square grid cell, in true metres (UTM 51N)
--   command_board(mode)        one envelope: counts, reports, cells or sites,
--                              places, checklist, session, last handover
--   command_suggest()          SMART's suggestion, with the reason in words
--   command_start / _end / _handover / _check / _place_check / _dismiss
--   command_feed()             what happened, newest first
--   command_hall(token)        counts only, for a display in the hall
-- =============================================================

set search_path = public, extensions;

-- ---------- the modes and their words --------------------------------------

create table public.command_modes (
  mode              text primary key check (mode in ('fire', 'quake', 'flood', 'typhoon')),
  sort              smallint not null,
  name_en           text not null,
  name_fil          text not null,
  labels            text[] not null default '{}',     -- keyword groups (smart_rules) that make a report about this mode
  detail_counts     boolean not null default false,   -- a detail word alone puts a report on the board (damage words do; "tuhod" alone does not)
  window_hours      integer not null check (window_hours between 1 and 168),
  suggest_reports   smallint not null check (suggest_reports >= 1),
  suggest_residents smallint not null check (suggest_residents >= 1),
  suggest_hours     numeric not null check (suggest_hours > 0),
  cell_metres       integer not null default 100 check (cell_metres between 25 and 500),
  enabled           boolean not null default true
);
insert into public.command_modes values
  ('fire',    1, 'Fire Surroundings', 'Paligid ng Sunog', '{fire,"gas leak"}',                false, 6,  2, 2, 1,  100, true),
  ('quake',   2, 'Quake Check',       'Suri sa Lindol',   '{}',                               true,  24, 3, 2, 1,  100, true),
  ('flood',   3, 'Flood Watch',       'Bantay-baha',      '{flooding}',                       false, 24, 3, 2, 3,  100, true),
  ('typhoon', 4, 'Typhoon Board',     'Pisara ng Bagyo',  '{}',                               true,  48, 4, 3, 6,  100, true);

-- What a mode reads in a report, worst last. rank orders the tags within a mode.
create table public.command_tags (
  mode text not null references public.command_modes (mode) on delete cascade,
  tag  text not null,
  rank smallint not null,
  en   text not null,
  fil  text not null,
  primary key (mode, tag)
);
insert into public.command_tags (mode, tag, rank, en, fil) values
  -- MMDA's flood gauge (inches as MMDA gives them); ankle-deep sits with gutter-deep
  ('flood', 'gutter',      1, 'gutter-deep (about 8 in)',        'hanggang gutter (mga 8 pulgada)'),
  ('flood', 'ankle',       1, 'ankle-deep',                      'hanggang bukung-bukong'),
  ('flood', 'half_knee',   2, 'half-knee (about 10 in)',         'kalahating tuhod (mga 10 pulgada)'),
  ('flood', 'half_tire',   3, 'half-tire (about 13 in)',         'kalahating gulong (mga 13 pulgada)'),
  ('flood', 'knee',        4, 'knee-deep (about 19 in)',         'hanggang tuhod (mga 19 pulgada)'),
  ('flood', 'tire',        5, 'tire-deep (about 26 in)',         'hanggang gulong (mga 26 pulgada)'),
  ('flood', 'waist',       6, 'waist-deep (about 37 in)',        'hanggang baywang (mga 37 pulgada)'),
  ('flood', 'chest',       7, 'chest-deep (about 45 in)',        'hanggang dibdib (mga 45 pulgada)'),
  ('flood', 'above_chest', 8, 'above the chest (neck or roof)',  'lampas dibdib (leeg o bubong)'),
  ('fire',  'smoke',       1, 'smoke',                           'usok'),
  ('fire',  'flames',      2, 'flames',                          'apoy'),
  ('fire',  'gas',         3, 'gas or LPG',                      'gas o LPG'),
  ('fire',  'people_inside', 4, 'people inside',                 'may tao sa loob'),
  ('quake', 'glass',       1, 'broken glass',                    'basag na salamin'),
  ('quake', 'crack',       1, 'cracks',                          'bitak'),
  ('quake', 'fallen',      2, 'things fell',                     'may nahulog'),
  ('quake', 'collapsed',   3, 'collapsed',                       'gumuho'),
  ('quake', 'injured',     4, 'injured or trapped',              'may sugatan o naipit'),
  ('typhoon', 'flood',     1, 'flood water',                     'baha'),
  ('typhoon', 'roof',      2, 'roofing blown off',               'nilipad na bubong o yero'),
  ('typhoon', 'fallen_tree', 2, 'fallen tree',                   'natumbang puno'),
  ('typhoon', 'power_line', 3, 'power line down',                'bagsak na kawad ng kuryente'),
  ('typhoon', 'collapsed', 3, 'collapsed',                       'gumuho'),
  ('typhoon', 'injured',   4, 'injured or trapped',              'may sugatan o naipit');

-- The words. tag null: the word says the report is about the mode. Hyphens
-- read as joined ("knee-deep" is "kneedeep"), as _smart_tokens reads them.
create table public.command_words (
  mode text not null references public.command_modes (mode) on delete cascade,
  word text not null check (word = lower(word) and char_length(word) between 2 and 40),
  tag  text,
  primary key (mode, word),
  foreign key (mode, tag) references public.command_tags (mode, tag) on delete cascade
);
insert into public.command_words (mode, word, tag) values
  ('flood', 'flood', null), ('flood', 'flooded', null), ('flood', 'flooding', null), ('flood', 'floodwater', null),
  ('flood', 'baha', null), ('flood', 'lubog', null), ('flood', 'nalubog', null),
  ('flood', 'gutter', 'gutter'), ('flood', 'gutterdeep', 'gutter'), ('flood', 'gutter deep', 'gutter'),
  ('flood', 'ankle', 'ankle'), ('flood', 'ankledeep', 'ankle'), ('flood', 'ankle deep', 'ankle'), ('flood', 'bukungbukong', 'ankle'), ('flood', 'bukongbukong', 'ankle'), ('flood', 'sakong', 'ankle'),
  ('flood', 'half knee', 'half_knee'), ('flood', 'halfknee', 'half_knee'), ('flood', 'kalahating tuhod', 'half_knee'),
  ('flood', 'half tire', 'half_tire'), ('flood', 'halftire', 'half_tire'), ('flood', 'kalahating gulong', 'half_tire'),
  ('flood', 'tuhod', 'knee'), ('flood', 'knee', 'knee'), ('flood', 'kneedeep', 'knee'), ('flood', 'knee deep', 'knee'),
  ('flood', 'hanggang gulong', 'tire'), ('flood', 'tire deep', 'tire'), ('flood', 'tiredeep', 'tire'),
  ('flood', 'baywang', 'waist'), ('flood', 'bewang', 'waist'), ('flood', 'beywang', 'waist'), ('flood', 'waist', 'waist'), ('flood', 'waistdeep', 'waist'), ('flood', 'waist deep', 'waist'),
  ('flood', 'dibdib', 'chest'), ('flood', 'chest', 'chest'), ('flood', 'chestdeep', 'chest'), ('flood', 'chest deep', 'chest'),
  ('flood', 'leeg', 'above_chest'), ('flood', 'neck', 'above_chest'), ('flood', 'hanggang bubong', 'above_chest'), ('flood', 'roof deep', 'above_chest'),
  ('fire', 'fire', null), ('fire', 'sunog', null), ('fire', 'nasusunog', null), ('fire', 'burning', null), ('fire', 'on fire', 'flames'),
  ('fire', 'usok', 'smoke'), ('fire', 'smoke', 'smoke'), ('fire', 'umuusok', 'smoke'),
  ('fire', 'apoy', 'flames'), ('fire', 'flames', 'flames'), ('fire', 'flame', 'flames'), ('fire', 'liyab', 'flames'), ('fire', 'nagliliyab', 'flames'),
  ('fire', 'lpg', 'gas'), ('fire', 'tangke', 'gas'), ('fire', 'gas leak', 'gas'),
  ('fire', 'naipit', 'people_inside'), ('fire', 'trapped', 'people_inside'), ('fire', 'nakulong', 'people_inside'), ('fire', 'may tao sa loob', 'people_inside'), ('fire', 'people inside', 'people_inside'),
  ('quake', 'lindol', null), ('quake', 'lumindol', null), ('quake', 'earthquake', null), ('quake', 'quake', null), ('quake', 'yanig', null), ('quake', 'yumanig', null), ('quake', 'aftershock', null),
  ('quake', 'bitak', 'crack'), ('quake', 'nabitak', 'crack'), ('quake', 'lamat', 'crack'), ('quake', 'crack', 'crack'), ('quake', 'cracks', 'crack'), ('quake', 'cracked', 'crack'),
  ('quake', 'basag', 'glass'), ('quake', 'broken glass', 'glass'),
  ('quake', 'nahulog', 'fallen'), ('quake', 'bumagsak', 'fallen'), ('quake', 'fell', 'fallen'),
  ('quake', 'guho', 'collapsed'), ('quake', 'gumuho', 'collapsed'), ('quake', 'collapsed', 'collapsed'), ('quake', 'giba', 'collapsed'), ('quake', 'nagiba', 'collapsed'),
  ('quake', 'sugatan', 'injured'), ('quake', 'nasugatan', 'injured'), ('quake', 'injured', 'injured'), ('quake', 'naipit', 'injured'), ('quake', 'trapped', 'injured'),
  ('typhoon', 'bagyo', null), ('typhoon', 'typhoon', null), ('typhoon', 'storm', null), ('typhoon', 'habagat', null), ('typhoon', 'malakas na hangin', null), ('typhoon', 'strong wind', null),
  ('typhoon', 'baha', 'flood'), ('typhoon', 'flood', 'flood'), ('typhoon', 'flooded', 'flood'), ('typhoon', 'lubog', 'flood'),
  ('typhoon', 'yero', 'roof'), ('typhoon', 'nilipad', 'roof'), ('typhoon', 'roof blown', 'roof'), ('typhoon', 'roofing', 'roof'),
  ('typhoon', 'fallen tree', 'fallen_tree'), ('typhoon', 'natumbang puno', 'fallen_tree'), ('typhoon', 'nabuwal na puno', 'fallen_tree'), ('typhoon', 'tumbang puno', 'fallen_tree'), ('typhoon', 'buwal', 'fallen_tree'), ('typhoon', 'nabuwal', 'fallen_tree'),
  ('typhoon', 'live wire', 'power_line'), ('typhoon', 'kawad', 'power_line'), ('typhoon', 'power line', 'power_line'), ('typhoon', 'linya ng kuryente', 'power_line'), ('typhoon', 'poste', 'power_line'), ('typhoon', 'transformer', 'power_line'),
  ('typhoon', 'guho', 'collapsed'), ('typhoon', 'gumuho', 'collapsed'), ('typhoon', 'collapsed', 'collapsed'),
  ('typhoon', 'sugatan', 'injured'), ('typhoon', 'injured', 'injured'), ('typhoon', 'naipit', 'injured'), ('typhoon', 'trapped', 'injured');

-- Each mode's checklist (what a barangay does, in order). A session ticks them.
create table public.command_checklist (
  mode text not null references public.command_modes (mode) on delete cascade,
  key  text not null,
  sort smallint not null,
  en   text not null,
  fil  text not null,
  primary key (mode, key)
);
insert into public.command_checklist (mode, key, sort, en, fil) values
  ('fire', 'bfp',      1, 'Called the Bureau of Fire Protection (911, or the Pasay fire station)', 'Natawagan ang BFP (911, o ang istasyon ng bumbero sa Pasay)'),
  ('fire', 'road',     2, 'Road cleared for the fire truck', 'Nalinis ang daan para sa trak ng bumbero'),
  ('fire', 'move',     3, 'Residents near the fire moved to a safe place', 'Nailipat sa ligtas na lugar ang mga residenteng malapit sa sunog'),
  ('fire', 'power',    4, 'Meralco asked to cut the power to the area', 'Hiniling sa Meralco na putulin ang kuryente sa lugar'),
  ('fire', 'count',    5, 'Families nearby counted', 'Nabilang ang mga pamilyang malapit'),
  ('quake', 'phivolcs', 1, 'PHIVOLCS bulletin read (magnitude, aftershocks)', 'Nabasa ang bulletin ng PHIVOLCS (lakas, aftershock)'),
  ('quake', 'outside', 2, 'Residents told to stay out of damaged buildings', 'Sinabihan ang mga residente na lumayo sa mga nasirang gusali'),
  ('quake', 'hall',    3, 'Barangay hall checked', 'Nasuri ang barangay hall'),
  ('quake', 'places',  4, 'Schools, churches and public buildings checked (Places to check)', 'Nasuri ang mga paaralan, simbahan at pampublikong gusali (Mga lugar na susuriin)'),
  ('quake', 'gas',     5, 'Gas leaks and live wires looked for', 'Hinanap ang tagas ng gas at live wire'),
  ('quake', 'count',   6, 'Headcount at the evacuation area', 'Nabilang ang mga tao sa evacuation area'),
  ('flood', 'pagasa',  1, 'PAGASA rainfall advisory read', 'Nabasa ang rainfall advisory ng PAGASA'),
  ('flood', 'warn',    2, 'Residents in low areas told to move up', 'Sinabihan ang mga nasa mabababang lugar na lumikas pataas'),
  ('flood', 'evac',    3, 'Evacuation center opened', 'Nabuksan ang evacuation center'),
  ('flood', 'drains',  4, 'Drains and canals checked for blockage', 'Nasuri ang mga kanal kung barado'),
  ('flood', 'mmda',    5, 'Roads that cannot be passed reported to MMDA', 'Naiulat sa MMDA ang mga daang hindi madaanan'),
  ('typhoon', 'signal', 1, 'PAGASA wind signal announced to residents', 'Naianunsyo sa mga residente ang wind signal ng PAGASA'),
  ('typhoon', 'secure', 2, 'Loose roofing and signs secured or reported', 'Natalian o naiulat ang maluluwag na yero at karatula'),
  ('typhoon', 'evac',   3, 'Evacuation center ready', 'Handa ang evacuation center'),
  ('typhoon', 'lines',  4, 'Fallen trees and wires reported to Meralco and the city', 'Naiulat sa Meralco at sa lungsod ang natumbang puno at kawad'),
  ('typhoon', 'relief', 5, 'Relief goods counted', 'Nabilang ang relief goods');

-- Places a quake check walks through, and what fire surroundings name.
create table public.command_place_kinds (
  kind  text primary key,
  quake boolean not null default false,
  fire  boolean not null default false
);
insert into public.command_place_kinds (kind, quake, fire) values
  ('school', true, true), ('college', true, true), ('educational_institution', true, true), ('place_of_worship', true, true),
  ('chapel', true, true), ('government', true, true), ('townhall', true, true), ('police', true, false), ('fire_station', true, true),
  ('hospital', true, true), ('clinic', true, true), ('mall', true, true), ('terminal', true, false), ('station', true, false),
  ('bus_station', true, false), ('fuel', false, true), ('hotel', false, true), ('residential', false, true), ('supermarket', false, true),
  ('pharmacy', false, true);

alter table public.command_modes enable row level security;
alter table public.command_tags enable row level security;
alter table public.command_words enable row level security;
alter table public.command_checklist enable row level security;
alter table public.command_place_kinds enable row level security;
create policy command_modes_read on public.command_modes for select using ((select public.is_admin()));
create policy command_tags_read on public.command_tags for select using ((select public.is_admin()));
create policy command_words_read on public.command_words for select using ((select public.is_admin()));
create policy command_checklist_read on public.command_checklist for select using ((select public.is_admin()));
create policy command_place_kinds_read on public.command_place_kinds for select using ((select public.is_admin()));

-- ---------- sessions, checks, handovers, the switch --------------------------

create table public.command_sessions (
  id         uuid primary key default gen_random_uuid(),
  mode       text not null references public.command_modes (mode),
  how        text not null check (how in ('admin', 'suggested', 'auto')),
  reason     text not null check (char_length(reason) between 3 and 300),
  started_at timestamptz not null default now(),
  started_by uuid references public.users (id) on delete set null,   -- null: SMART switched it on (auto)
  ended_at   timestamptz,
  ended_by   uuid references public.users (id) on delete set null,
  end_note   text check (char_length(end_note) <= 1000)
);
create unique index command_sessions_one_active on public.command_sessions ((true)) where ended_at is null;
create index command_sessions_started_idx on public.command_sessions (started_at desc);

create table public.command_checks (
  session_id uuid not null references public.command_sessions (id) on delete cascade,
  item       text not null,
  done       boolean not null,
  note       text check (char_length(note) <= 300),
  by_user    uuid references public.users (id) on delete set null,
  at         timestamptz not null default now(),
  primary key (session_id, item)
);

create table public.command_place_checks (
  session_id uuid not null references public.command_sessions (id) on delete cascade,
  place_id   bigint not null references public.places (id) on delete cascade,
  status     text not null check (status in ('ok', 'damage', 'closed')),
  note       text check (char_length(note) <= 300),
  by_user    uuid references public.users (id) on delete set null,
  at         timestamptz not null default now(),
  primary key (session_id, place_id)
);

create table public.command_handovers (
  id         bigint generated always as identity primary key,
  session_id uuid not null references public.command_sessions (id) on delete cascade,
  by_user    uuid references public.users (id) on delete set null,
  at         timestamptz not null default clock_timestamp(),
  note       text not null check (char_length(note) between 5 and 1000),
  final      boolean not null default false,
  snapshot   jsonb not null
);
create index command_handovers_session_idx on public.command_handovers (session_id, at desc);

-- the switch: SMART switches a mode on by itself only when this is on
create table public.command_state (
  id          smallint primary key default 1 check (id = 1),
  auto_switch boolean not null default false,
  dismissed   jsonb not null default '{}',   -- mode -> until: "not now" on a suggestion
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.users (id) on delete set null
);
insert into public.command_state (id) values (1);

-- the reading of each report, kept so the board does not read every report again
create table public.command_reads (
  report_id uuid primary key references public.reports (id) on delete cascade,
  reading   jsonb not null,
  read_at   timestamptz not null default now()
);

-- a display in the hall: a link with a secret, counts only, revocable
create table public.command_display_links (
  id           uuid primary key default gen_random_uuid(),
  label        text not null check (char_length(label) between 2 and 60),
  token_sha256 text not null unique,
  created_by   uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  revoked_at   timestamptz,
  last_seen_at timestamptz
);

alter table public.command_sessions enable row level security;
alter table public.command_checks enable row level security;
alter table public.command_place_checks enable row level security;
alter table public.command_handovers enable row level security;
alter table public.command_state enable row level security;
alter table public.command_reads enable row level security;
alter table public.command_display_links enable row level security;
create policy command_sessions_read on public.command_sessions for select using ((select public.is_admin()));
create policy command_checks_read on public.command_checks for select using ((select public.is_admin()));
create policy command_place_checks_read on public.command_place_checks for select using ((select public.is_admin()));
create policy command_handovers_read on public.command_handovers for select using ((select public.is_admin()));
create policy command_state_read on public.command_state for select using ((select public.is_admin()));
create policy command_display_links_read on public.command_display_links for select using ((select public.is_admin()));
-- command_reads: no policy; only the functions below read it
comment on table public.command_sessions is '0143: one command-center mode at a time. started_by null: SMART switched it on (auto). Written only by command_start/_end and _command_auto.';
comment on table public.command_display_links is '0143: hall display links. Only the SHA-256 of the secret is kept; the secret is shown once.';

-- ---------- reading a report ------------------------------------------------

/** Every word a mode reads: its own words, and the words of the keyword
    groups named in its labels (so a word an administrator adds to "fire"
    also counts here). */
create or replace function public._command_words_all()
returns table (mode text, word text, norm text, tag text, rank smallint, phrase boolean)
language sql stable security definer set search_path = public, extensions as $$
  with w as (
    select cw.mode, cw.word, cw.tag from public.command_words cw
    union
    select m.mode, gw, null from public.command_modes m, public.smart_rules k, jsonb_array_elements(k.keyword_groups) g,
           jsonb_array_elements_text(g -> 'words') gw
     where k.id = 1 and g ->> 'label' = any (m.labels)
  )
  select w.mode, w.word, array_to_string(public._smart_tokens(w.word), ' '), w.tag, t.rank,
         array_length(public._smart_tokens(w.word), 1) > 1
    from w left join public.command_tags t on t.mode = w.mode and t.tag = w.tag
$$;
revoke all on function public._command_words_all() from public, anon, authenticated;

/** What each mode reads in a text: {"flood": {"about": true, "tag": "knee",
    "rank": 4, "word": "tuhod", "tags": ["knee"]}, ...}. Phrases are read
    first, longest first, and taken out so their words are not read again
    ("half knee" is not "knee"). A word after hindi, wala or walang is not
    read ("walang sunog"). Words are matched as written, with stretched
    letters read once, and by the engine's root ("binaha" is "baha"). */
create or replace function public._command_read(p_text text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
declare
  v_toks  text[] := public._smart_tokens(p_text);
  v_vocab text[];
  v_cand  jsonb := '{}';      -- token -> [as written, unstretched, root]
  v_out   jsonb := '{}';
  v_neg   text[] := array['hindi', 'di', 'wala', 'walang', 'wla', 'wlang', 'hnd', 'no', 'not', 'never'];
  v_words jsonb;
  m record; w record; v_root text;
  v_flat text; v_left text[]; v_hits jsonb; v_about boolean; i integer; t text; c text[];
begin
  if coalesce(array_length(v_toks, 1), 0) = 0 then return '{}'; end if;
  v_vocab := public._smart_vocab();
  select jsonb_agg(to_jsonb(x)) into v_words from public._command_words_all() x;
  foreach t in array v_toks loop
    if t = '|' or v_cand ? t then continue; end if;
    c := array[t, public._smart_unstretch(t)];
    v_root := null;
    select st.root into v_root from public._smart_stem(t, v_vocab) st;
    if v_root is not null then c := c || v_root; end if;
    v_cand := v_cand || jsonb_build_object(t, to_jsonb(c));
  end loop;

  for m in select cm.mode from public.command_modes cm where cm.enabled loop
    v_flat := ' ' || array_to_string(v_toks, ' ') || ' ';
    v_hits := '[]'; v_about := false;
    for w in select * from jsonb_to_recordset(v_words) as x(mode text, word text, norm text, tag text, rank smallint, phrase boolean)
              where x.mode = m.mode and x.phrase order by length(x.norm) desc loop
      if v_flat like '% ' || w.norm || ' %' then
        if w.tag is null then v_about := true;
        else v_hits := v_hits || jsonb_build_object('tag', w.tag, 'rank', w.rank, 'word', w.word); end if;
        v_flat := replace(v_flat, ' ' || w.norm || ' ', ' ~ ');
      end if;
    end loop;
    v_left := string_to_array(trim(v_flat), ' ');
    for i in 1 .. coalesce(array_length(v_left, 1), 0) loop
      t := v_left[i];
      if t in ('~', '|') or not (v_cand ? t) then continue; end if;
      -- "walang sunog", "hindi na baha": a negation one word back, or two with na/nang/pa between
      if (i > 1 and v_left[i - 1] = any (v_neg))
         or (i > 2 and v_left[i - 2] = any (v_neg) and v_left[i - 1] in ('na', 'nang', 'ng', 'pa', 'po', 'more', 'any')) then
        continue;
      end if;
      for w in select * from jsonb_to_recordset(v_words) as x(mode text, word text, norm text, tag text, rank smallint, phrase boolean)
                where x.mode = m.mode and not x.phrase
                  and x.norm in (select jsonb_array_elements_text(v_cand -> t)) loop
        if w.tag is null then v_about := true;
        else v_hits := v_hits || jsonb_build_object('tag', w.tag, 'rank', w.rank, 'word', t); end if;
      end loop;
    end loop;
    if v_about or jsonb_array_length(v_hits) > 0 then
      v_out := v_out || jsonb_build_object(m.mode, jsonb_build_object(
        'about', v_about,
        'tag',  (select h ->> 'tag'  from jsonb_array_elements(v_hits) h order by (h ->> 'rank')::int desc limit 1),
        'rank', (select (h ->> 'rank')::int from jsonb_array_elements(v_hits) h order by (h ->> 'rank')::int desc limit 1),
        'word', (select h ->> 'word' from jsonb_array_elements(v_hits) h order by (h ->> 'rank')::int desc limit 1),
        'tags', coalesce((select jsonb_agg(distinct h ->> 'tag') from jsonb_array_elements(v_hits) h), '[]')));
    end if;
  end loop;
  return v_out;
end $$;
revoke all on function public._command_read(text) from public, anon, authenticated;

/** A report's reading, from the cache or read now and kept. */
create or replace function public._command_reading(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v jsonb;
begin
  select reading into v from public.command_reads where report_id = p_report;
  if found then return v; end if;
  select public._command_read(coalesce(subject, '') || ' ' || coalesce(description, '')) into v from public.reports where id = p_report;
  if v is null then return '{}'; end if;
  insert into public.command_reads (report_id, reading) values (p_report, v) on conflict (report_id) do update set reading = excluded.reading, read_at = now();
  return v;
end $$;
revoke all on function public._command_reading(uuid) from public, anon, authenticated;

-- the cache forgets a report whose words change, and everything when the words do
create or replace function public._command_reads_forget()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'reports' then
    delete from public.command_reads where report_id = new.id;
    return new;
  end if;
  delete from public.command_reads;
  return null;
end $$;
revoke all on function public._command_reads_forget() from public, anon, authenticated;
create trigger reports_command_reads_forget after update of subject, description on public.reports
  for each row when (old.subject is distinct from new.subject or old.description is distinct from new.description)
  execute function public._command_reads_forget();
create trigger command_words_forget after insert or update or delete on public.command_words
  for each statement execute function public._command_reads_forget();
create trigger command_modes_forget after update of labels on public.command_modes
  for each statement execute function public._command_reads_forget();
create trigger smart_rules_command_forget after update of keyword_groups on public.smart_rules
  for each statement execute function public._command_reads_forget();

-- ---------- the grid ---------------------------------------------------------

/** The square cell a point falls in, p_metres a side, in true metres
    (UTM zone 51N, which covers Metro Manila): its key and its outline. */
create or replace function public._command_cell(p_geom geography, p_metres integer)
returns table (key text, outline jsonb, lat double precision, lng double precision)
language sql immutable set search_path = public, extensions as $$
  with p as (select st_transform(p_geom::geometry, 32651) as g),
       k as (select floor(st_x(g) / p_metres)::bigint as kx, floor(st_y(g) / p_metres)::bigint as ky from p),
       e as (select kx, ky, st_makeenvelope(kx * p_metres, ky * p_metres, (kx + 1) * p_metres, (ky + 1) * p_metres, 32651) as env from k)
  select p_metres || ':' || kx || ':' || ky,
         st_asgeojson(st_transform(env, 4326), 6)::jsonb,
         st_y(st_transform(st_centroid(env), 4326)), st_x(st_transform(st_centroid(env), 4326))
    from e
$$;
revoke all on function public._command_cell(geography, integer) from public, anon, authenticated;

-- ---------- the session ------------------------------------------------------

create or replace function public._command_active()
returns public.command_sessions
language sql stable security definer set search_path = public as $$
  select * from public.command_sessions where ended_at is null limit 1
$$;
revoke all on function public._command_active() from public, anon, authenticated;

/** The reports on a mode's board since p_since: not sensitive, not
    rejected or cancelled, and about the mode (or, for damage modes, with a
    damage word). */
create or replace function public._command_reports(p_mode text, p_since timestamptz)
returns table (id uuid, tracking_id text, subject text, status text, level text, resident_id uuid, created_at timestamptz,
               lat double precision, lng double precision, geom geography, place text,
               about boolean, tag text, rank integer, word text, tags jsonb)
language plpgsql security definer set search_path = public, extensions as $$
declare m public.command_modes%rowtype;
begin
  select * into m from public.command_modes where mode = p_mode;
  return query
  select r.id, r.tracking_id, r.subject, r.status::text, t.effective_level, r.resident_id, r.created_at,
         st_y(r.geom::geometry), st_x(r.geom::geometry), r.geom, r.location_label,
         coalesce((rd.x ->> 'about')::boolean, false), rd.x ->> 'tag', (rd.x ->> 'rank')::int, rd.x ->> 'word', coalesce(rd.x -> 'tags', '[]')
    from public.reports r
    left join public.report_triage t on t.report_id = r.id
    cross join lateral (select public._command_reading(r.id) -> p_mode as x) rd
   where r.deleted_at is null and not r.is_sensitive and r.created_at >= p_since
     and r.status not in ('rejected', 'cancelled') and r.geom is not null
     and rd.x is not null
     and ((rd.x ->> 'about')::boolean or (m.detail_counts and rd.x ->> 'tag' is not null))
   order by r.created_at desc;
end $$;
revoke all on function public._command_reports(text, timestamptz) from public, anon, authenticated;

/** SMART's suggestion, or null: the first mode (fire, quake, flood,
    typhoon) with enough reports about it from enough residents lately, not
    already on and not put off with "not now". Typhoon Board is also
    suggested when storm mode is on or PAGASA's wind signal is up over Metro
    Manila (the portal reads PAGASA and passes the signal). */
create or replace function public._command_suggestion(p_signal smallint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m record; v_active public.command_sessions; v_dis jsonb; v_storm boolean;
  n integer; who integer; ids text[];
begin
  v_active := public._command_active();
  select dismissed into v_dis from public.command_state where id = 1;
  select storm_mode into v_storm from public.smart_rules where id = 1;
  for m in select * from public.command_modes where enabled order by sort loop
    if v_active.mode = m.mode then continue; end if;
    if (v_dis ->> m.mode) is not null and (v_dis ->> m.mode)::timestamptz > now() then continue; end if;
    select count(*), count(distinct x.resident_id), (array_agg(x.tracking_id order by x.created_at desc))[1:5]
      into n, who, ids
      from public._command_reports(m.mode, now() - make_interval(secs => (m.suggest_hours * 3600)::int)) x
     where x.about;
    if n >= m.suggest_reports and who >= m.suggest_residents then
      return jsonb_build_object('mode', m.mode, 'name_en', m.name_en, 'name_fil', m.name_fil, 'reports', n, 'residents', who, 'hours', m.suggest_hours, 'tracking_ids', to_jsonb(ids),
        'why_en', format('%s reports in the last %s mention %s, from %s residents.', n,
                         case when m.suggest_hours = 1 then 'hour' else m.suggest_hours::text || ' hours' end,
                         case m.mode when 'fire' then 'a fire' when 'quake' then 'an earthquake or damage' when 'flood' then 'flood water' else 'the storm or its damage' end, who),
        'why_fil', format('%s ulat sa nakaraang %s oras ang bumanggit ng %s, mula sa %s residente.', n, m.suggest_hours::text,
                          case m.mode when 'fire' then 'sunog' when 'quake' then 'lindol o pinsala' when 'flood' then 'baha' else 'bagyo o pinsala nito' end, who));
    end if;
    if m.mode = 'typhoon' and (coalesce(v_storm, false) or coalesce(p_signal, 0) >= 1) then
      return jsonb_build_object('mode', m.mode, 'name_en', m.name_en, 'name_fil', m.name_fil, 'reports', n, 'residents', who, 'signal', p_signal,
        'why_en', case when coalesce(p_signal, 0) >= 1 then format('PAGASA Wind Signal No. %s is up over Metro Manila.', p_signal) else 'Storm mode is on.' end,
        'why_fil', case when coalesce(p_signal, 0) >= 1 then format('Nakataas ang Wind Signal No. %s ng PAGASA sa Metro Manila.', p_signal) else 'Naka-on ang storm mode.' end);
    end if;
  end loop;
  return null;
end $$;
revoke all on function public._command_suggestion(smallint) from public, anon, authenticated;

create or replace function public.command_suggest(p_signal smallint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  return public._command_suggestion(p_signal);
end $$;

/** "Not now": the suggestion for this mode stays quiet for p_hours. */
create or replace function public.command_dismiss(p_mode text, p_hours integer default 2)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.command_modes where mode = p_mode) then raise exception 'No such mode' using errcode = 'check_violation'; end if;
  update public.command_state
     set dismissed = dismissed || jsonb_build_object(p_mode, now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 2), 24)))),
         updated_at = now(), updated_by = auth.uid()
   where id = 1;
  perform public._smart_event('command_not_now', null, format('Suggestion put off: %s, for %s hours', p_mode, greatest(1, least(coalesce(p_hours, 2), 24))), jsonb_build_object('mode', p_mode));
end $$;

/** The counts a handover keeps. */
create or replace function public._command_counts(p_session uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.command_sessions;
begin
  select * into s from public.command_sessions where id = p_session;
  return (select jsonb_build_object(
      'reports', count(*), 'open', count(*) filter (where x.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
      'resolved', count(*) filter (where x.status in ('resolved', 'closed')), 'residents', count(distinct x.resident_id),
      'checklist_done', (select count(*) from public.command_checks c where c.session_id = s.id and c.done),
      'checklist_total', (select count(*) from public.command_checklist l where l.mode = s.mode),
      'places_checked', (select count(*) from public.command_place_checks pc where pc.session_id = s.id),
      'places_damage', (select count(*) from public.command_place_checks pc where pc.session_id = s.id and pc.status = 'damage'),
      'worst', (select jsonb_build_object('tag', y.tag, 'en', t.en, 'fil', t.fil) from public._command_reports(s.mode, s.started_at - interval '2 hours') y
                  join public.command_tags t on t.mode = s.mode and t.tag = y.tag order by y.rank desc nulls last limit 1))
    from public._command_reports(s.mode, s.started_at - interval '2 hours') x);
end $$;
revoke all on function public._command_counts(uuid) from public, anon, authenticated;

/** Turn a mode on. An administrator gives the reason; accepting SMART's
    suggestion uses its reason. A mode already on is ended first, noted as
    switched. */
create or replace function public.command_start(p_mode text, p_reason text default null, p_how text default 'admin')
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.command_modes%rowtype; v_active public.command_sessions; v_id uuid; v_who text;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if p_how not in ('admin', 'suggested') then raise exception 'how is admin or suggested' using errcode = 'check_violation'; end if;
  select * into m from public.command_modes where mode = p_mode and enabled;
  if not found then raise exception 'No such mode' using errcode = 'check_violation'; end if;
  if p_how = 'suggested' then
    v_reason := coalesce(v_reason, public._command_suggestion(null) ->> 'why_en', 'Suggested by SMART');
  end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'Say why the mode is turned on' using errcode = 'check_violation'; end if;
  v_active := public._command_active();
  if v_active.id is not null then
    if v_active.mode = p_mode then raise exception '% is already on', m.name_en using errcode = 'check_violation'; end if;
    insert into public.command_handovers (session_id, by_user, note, final, snapshot)
    values (v_active.id, auth.uid(), format('Switched to %s.', m.name_en), true, public._command_counts(v_active.id));
    update public.command_sessions set ended_at = now(), ended_by = auth.uid(), end_note = format('Switched to %s.', m.name_en) where id = v_active.id;
  end if;
  insert into public.command_sessions (mode, how, reason, started_by) values (p_mode, p_how, left(v_reason, 300), auth.uid()) returning id into v_id;
  update public.command_state set dismissed = dismissed - p_mode, updated_at = now(), updated_by = auth.uid() where id = 1;
  select public.display_name(full_name) into v_who from public.users where id = auth.uid();
  perform public._smart_event('command_on', null, format('%s on (%s): %s', m.name_en, coalesce(v_who, 'an administrator'), left(v_reason, 200)),
                              jsonb_build_object('session', v_id, 'mode', p_mode, 'how', p_how));
  perform public._notify_admins(format('%s is on. %s: %s', m.name_en, coalesce(v_who, 'An administrator'), left(v_reason, 200)));
  return v_id;
exception when unique_violation then
  raise exception 'Another mode was turned on a moment ago. Reload the page.' using errcode = 'check_violation';
end $$;

/** Hand over to the next shift: a note, and the counts as they stand. */
create or replace function public.command_handover(p_note text)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare v_active public.command_sessions; v_id bigint; v_note text := nullif(trim(coalesce(p_note, '')), ''); m public.command_modes%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  if v_active.id is null then raise exception 'No mode is on' using errcode = 'check_violation'; end if;
  if v_note is null or char_length(v_note) < 5 then raise exception 'Write what the next shift needs to know' using errcode = 'check_violation'; end if;
  select * into m from public.command_modes where mode = v_active.mode;
  insert into public.command_handovers (session_id, by_user, note, snapshot) values (v_active.id, auth.uid(), left(v_note, 1000), public._command_counts(v_active.id))
  returning id into v_id;
  perform public._smart_event('command_handover', null, format('Handover (%s): %s', m.name_en, left(v_note, 200)), jsonb_build_object('session', v_active.id));
  perform public._notify_admins(format('Handover, %s: %s', m.name_en, left(v_note, 200)));
  return v_id;
end $$;

/** Turn the mode off. Only a person does this, with a closing note. */
create or replace function public.command_end(p_note text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_active public.command_sessions; v_note text := nullif(trim(coalesce(p_note, '')), ''); m public.command_modes%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  if v_active.id is null then raise exception 'No mode is on' using errcode = 'check_violation'; end if;
  if v_note is null or char_length(v_note) < 5 then raise exception 'Write a closing note for the record' using errcode = 'check_violation'; end if;
  select * into m from public.command_modes where mode = v_active.mode;
  insert into public.command_handovers (session_id, by_user, note, final, snapshot) values (v_active.id, auth.uid(), left(v_note, 1000), true, public._command_counts(v_active.id));
  update public.command_sessions set ended_at = now(), ended_by = auth.uid(), end_note = left(v_note, 1000) where id = v_active.id;
  perform public._smart_event('command_off', null, format('%s off: %s', m.name_en, left(v_note, 200)), jsonb_build_object('session', v_active.id));
  perform public._notify_admins(format('%s is off: %s', m.name_en, left(v_note, 200)));
end $$;

/** Tick (or untick) a checklist item of the mode that is on. */
create or replace function public.command_check(p_item text, p_done boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_active public.command_sessions;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  if v_active.id is null then raise exception 'No mode is on' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.command_checklist where mode = v_active.mode and key = p_item) then
    raise exception 'That is not on this mode''s checklist' using errcode = 'check_violation';
  end if;
  insert into public.command_checks (session_id, item, done, note, by_user) values (v_active.id, p_item, coalesce(p_done, true), left(nullif(trim(coalesce(p_note, '')), ''), 300), auth.uid())
  on conflict (session_id, item) do update set done = excluded.done, note = coalesce(excluded.note, command_checks.note), by_user = excluded.by_user, at = now();
end $$;

/** Mark a place checked: ok, damage seen, or closed. Null clears it. */
create or replace function public.command_place_check(p_place bigint, p_status text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_active public.command_sessions;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  if v_active.id is null then raise exception 'No mode is on' using errcode = 'check_violation'; end if;
  if p_status is null then delete from public.command_place_checks where session_id = v_active.id and place_id = p_place; return; end if;
  if p_status not in ('ok', 'damage', 'closed') then raise exception 'Status is ok, damage or closed' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.places where id = p_place) then raise exception 'No such place' using errcode = 'check_violation'; end if;
  insert into public.command_place_checks (session_id, place_id, status, note, by_user) values (v_active.id, p_place, p_status, left(nullif(trim(coalesce(p_note, '')), ''), 300), auth.uid())
  on conflict (session_id, place_id) do update set status = excluded.status, note = coalesce(excluded.note, command_place_checks.note), by_user = excluded.by_user, at = now();
end $$;

/** The auto switch: off unless an administrator turns it on. */
create or replace function public.command_set_auto(p_on boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  update public.command_state set auto_switch = coalesce(p_on, false), updated_at = now(), updated_by = auth.uid() where id = 1;
  perform public._smart_event('command_auto_setting', null, case when p_on then 'SMART may switch a mode on by itself' else 'SMART only suggests a mode' end, '{}');
end $$;

/** Every five minutes: when the auto switch is on and nothing is on, turn
    on what SMART would suggest, and tell the administrators. It never turns
    a mode off. */
create or replace function public._command_auto()
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s jsonb; v_id uuid;
begin
  if not coalesce((select auto_switch from public.command_state where id = 1), false) then return; end if;
  if (public._command_active()).id is not null then return; end if;
  s := public._command_suggestion(null);
  if s is null then return; end if;
  insert into public.command_sessions (mode, how, reason, started_by) values (s ->> 'mode', 'auto', left('SMART switched this on: ' || (s ->> 'why_en'), 300), null)
  returning id into v_id;
  perform public._smart_event('command_on', null, format('%s on (SMART, auto switch): %s', s ->> 'name_en', s ->> 'why_en'), jsonb_build_object('session', v_id, 'mode', s ->> 'mode', 'how', 'auto'));
  perform public._notify_admins(format('SMART turned on %s: %s An administrator ends it with a note.', s ->> 'name_en', s ->> 'why_en'));
exception when unique_violation then null;   -- an administrator turned one on at the same moment
end $$;
revoke all on function public._command_auto() from public, anon, authenticated;
select cron.schedule('command-watch', '*/5 * * * *', $$ select public._command_auto() $$);

-- ---------- the board ---------------------------------------------------------

/** The command board for a mode (default: the mode that is on). One
    envelope for every mode:
      mode, names, session, as_of, since, counts, tags, reports,
      cells (flood, quake, typhoon), sites (fire), places (quake),
      storm (typhoon), checklist, handover, tanods, suggestion.
    With no mode on and none asked for, only the suggestion and the modes. */
create or replace function public.command_board(p_mode text default null, p_signal smallint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions set jit = off as $$
declare
  v_active public.command_sessions; m public.command_modes%rowtype; v_mode text; v_since timestamptz; v_live boolean;
  v_out jsonb;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  v_mode := coalesce(p_mode, v_active.mode);
  v_out := jsonb_build_object(
    'as_of', now(),
    'auto_switch', (select auto_switch from public.command_state where id = 1),
    'modes', (select jsonb_agg(jsonb_build_object('mode', mode, 'en', name_en, 'fil', name_fil) order by sort) from public.command_modes where enabled),
    'active', case when v_active.id is null then null else jsonb_build_object(
        'id', v_active.id, 'mode', v_active.mode, 'how', v_active.how, 'reason', v_active.reason, 'started_at', v_active.started_at,
        'started_by', (select full_name from public.users where id = v_active.started_by),
        'en', (select name_en from public.command_modes where mode = v_active.mode), 'fil', (select name_fil from public.command_modes where mode = v_active.mode)) end,
    'suggestion', public._command_suggestion(p_signal));
  if v_mode is null then return v_out; end if;
  select * into m from public.command_modes where mode = v_mode;
  if not found then raise exception 'No such mode' using errcode = 'check_violation'; end if;
  v_live := coalesce(v_active.mode = v_mode, false);
  v_since := case when v_live then v_active.started_at - interval '2 hours' else now() - make_interval(hours => m.window_hours) end;

  create temp table if not exists _cb (id uuid, tracking_id text, subject text, status text, level text, resident_id uuid, created_at timestamptz,
    lat double precision, lng double precision, geom geography, place text, about boolean, tag text, rank integer, word text, tags jsonb) on commit drop;
  truncate _cb;
  insert into _cb select * from public._command_reports(v_mode, v_since);

  v_out := v_out || jsonb_build_object(
    'mode', v_mode, 'en', m.name_en, 'fil', m.name_fil, 'live', v_live, 'since', v_since, 'window_hours', m.window_hours, 'cell_metres', m.cell_metres,
    'counts', (select jsonb_build_object(
        'reports', count(*), 'residents', count(distinct resident_id),
        'open', count(*) filter (where status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
        'resolved', count(*) filter (where status in ('resolved', 'closed')),
        'dispatched', (select count(*) from public.dispatches d where d.report_id in (select id from _cb) and d.state in ('assigned', 'accepted')),
        'last_at', max(created_at)) from _cb),
    'tags', coalesce((select jsonb_agg(jsonb_build_object('tag', t.tag, 'rank', t.rank, 'en', t.en, 'fil', t.fil, 'reports', z.n, 'last_at', z.last_at) order by t.rank desc, z.n desc)
                        from (select x.tag, count(*) n, max(x.created_at) last_at from _cb x where x.tag is not null group by x.tag) z
                        join public.command_tags t on t.mode = v_mode and t.tag = z.tag), '[]'),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'tracking_id', x.tracking_id, 'subject', x.subject, 'status', x.status, 'level', x.level,
                          'created_at', x.created_at, 'lat', x.lat, 'lng', x.lng, 'place', x.place, 'tag', x.tag, 'word', x.word, 'rank', x.rank,
                          'tag_en', t.en, 'tag_fil', t.fil) order by x.created_at desc)
                        from (select * from _cb order by created_at desc limit 200) x
                        left join public.command_tags t on t.mode = v_mode and t.tag = x.tag), '[]'),
    'checklist', (select jsonb_agg(jsonb_build_object('key', l.key, 'en', l.en, 'fil', l.fil, 'done', coalesce(c.done, false), 'note', c.note, 'at', c.at,
                          'by', (select full_name from public.users where id = c.by_user)) order by l.sort)
                    from public.command_checklist l
                    left join public.command_checks c on v_live and c.session_id = v_active.id and c.item = l.key
                   where l.mode = v_mode),
    'handover', case when v_live then (select jsonb_build_object('at', h.at, 'note', h.note, 'by', (select full_name from public.users where id = h.by_user))
                                         from public.command_handovers h where h.session_id = v_active.id order by h.at desc limit 1) end,
    'tanods', (select jsonb_build_object('on_duty', count(*), 'located', count(*) filter (where public.location_is_fresh(u.last_location_at)))
                 from public.users u where u.role = 'tanod' and u.duty_status = 'on_duty' and not coalesce(u.is_suspended, false)));

  -- the grid: flood, quake, typhoon
  if v_mode in ('flood', 'quake', 'typhoon') then
    v_out := v_out || jsonb_build_object('cells', coalesce((
      select jsonb_agg(jsonb_build_object('key', g.key, 'outline', g.outline, 'lat', g.lat, 'lng', g.lng, 'reports', g.n, 'open', g.open_n,
                       'tag', g.tag, 'rank', g.rank, 'tag_en', t.en, 'tag_fil', t.fil, 'last_at', g.last_at, 'tracking_ids', g.ids,
                       'noah', case when v_mode = 'flood' then (select max(z.level) from public.hazard_zones z where z.hazard = 'flood' and st_intersects(z.geom, st_geomfromgeojson(g.outline::text))) end,
                       'surge', case when v_mode = 'flood' then (select max(z.level) from public.hazard_zones z where z.hazard = 'surge' and st_intersects(z.geom, st_geomfromgeojson(g.outline::text))) end)
                       order by g.rank desc nulls last, g.n desc)
        from (select c.key, min(c.outline::text)::jsonb outline, min(c.lat) lat, min(c.lng) lng, count(*) n,
                     count(*) filter (where x.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')) open_n,
                     (array_agg(x.tag order by x.rank desc nulls last))[1] tag, max(x.rank) rank, max(x.created_at) last_at,
                     (array_agg(x.tracking_id order by x.created_at desc))[1:6] ids
                from _cb x cross join lateral public._command_cell(x.geom, m.cell_metres) c group by c.key) g
        left join public.command_tags t on t.mode = v_mode and t.tag = g.tag), '[]'));
  end if;

  -- fire: each place a fire is reported (reports within 150 m are one site), and what is within 50, 100 and 200 m of it
  if v_mode = 'fire' then
    v_out := v_out || jsonb_build_object('sites', coalesce((
      with cl as (select x.*, st_clusterdbscan(st_transform(x.geom::geometry, 32651), eps := 150, minpoints := 1) over () cid from _cb x),
           st as (select cid, st_centroid(st_collect(geom::geometry))::geography centre, count(*) n, min(created_at) first_at, max(created_at) last_at,
                         (array_agg(tag order by rank desc nulls last))[1] tag, array_agg(tracking_id order by created_at) ids, array_agg(id) rids
                    from cl group by cid)
      select jsonb_agg(jsonb_build_object(
               'lat', st_y(s.centre::geometry), 'lng', st_x(s.centre::geometry), 'reports', s.n, 'first_at', s.first_at, 'last_at', s.last_at,
               'tag', s.tag, 'tag_en', (select en from public.command_tags where mode = 'fire' and tag = s.tag), 'tag_fil', (select fil from public.command_tags where mode = 'fire' and tag = s.tag),
               'tracking_ids', to_jsonb(s.ids),
               'rings', (select jsonb_agg(jsonb_build_object('metres', rg.r_m,
                           'places', (select count(*) from public.places p join public.command_place_kinds k on k.kind = p.kind and k.fire
                                        where p.active and st_dwithin(p.geom, s.centre, rg.r_m) and (rg.r_m = 50 or not st_dwithin(p.geom, s.centre, rg.r_prev))),
                           'named', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'name', q.name, 'kind', q.kind, 'metres', q.d) order by q.d)
                                        from (select p.id, p.name, p.kind, round(st_distance(p.geom, s.centre))::int d
                                                from public.places p join public.command_place_kinds k on k.kind = p.kind and k.fire
                                               where p.active and st_dwithin(p.geom, s.centre, rg.r_m) and (rg.r_m = 50 or not st_dwithin(p.geom, s.centre, rg.r_prev))
                                               order by p.geom <-> s.centre limit 8) q), '[]'),
                           'other_reports', (select count(*) from public.reports r where r.deleted_at is null and not r.is_sensitive and r.created_at >= v_since
                                               and r.id <> all (s.rids) and st_dwithin(r.geom, s.centre, rg.r_m) and (rg.r_m = 50 or not st_dwithin(r.geom, s.centre, rg.r_prev))))
                           order by rg.r_m)
                         from (values (50, 0), (100, 50), (200, 100)) rg(r_m, r_prev)),
               'fire_station', (select jsonb_build_object('name', p.name, 'metres', round(st_distance(p.geom, s.centre))::int)
                                  from public.places p where p.active and p.kind = 'fire_station' order by p.geom <-> s.centre limit 1),
               'tanods', coalesce((select jsonb_agg(jsonb_build_object('name', u.full_name, 'metres', round(st_distance(u.last_geom, s.centre))::int, 'as_of', u.last_location_at) order by st_distance(u.last_geom, s.centre))
                                     from (select * from public.users u where u.role = 'tanod' and u.duty_status = 'on_duty' and not coalesce(u.is_suspended, false)
                                             and u.last_geom is not null and public.location_is_fresh(u.last_location_at) order by u.last_geom <-> s.centre limit 3) u), '[]'))
             order by s.last_at desc)
        from st s), '[]'));
  end if;

  -- quake: the public buildings to check, and what was found
  if v_mode = 'quake' then
    v_out := v_out || jsonb_build_object('places', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'kind', p.kind, 'lat', p.lat, 'lng', p.lng,
               'status', pc.status, 'note', pc.note, 'at', pc.at, 'by', (select full_name from public.users where id = pc.by_user),
               'reports_near', (select count(*) from _cb x where st_dwithin(x.geom, p.geom, 75)))
             order by (pc.status is null) desc, p.kind, p.name)
        from public.places p
        join public.command_place_kinds k on k.kind = p.kind and k.quake
        cross join public.barangay_boundary b
        left join public.command_place_checks pc on v_live and pc.session_id = v_active.id and pc.place_id = p.id
       where p.active and p.name is not null and st_dwithin(b.geom, p.geom, 50)), '[]'));
  end if;

  if v_mode = 'typhoon' then
    v_out := v_out || jsonb_build_object('storm', (select jsonb_build_object('on', storm_mode, 'until', storm_until, 'reason', storm_reason) from public.smart_rules where id = 1),
                                         'signal', p_signal);
  end if;
  return v_out;
end $$;

-- ---------- the feed ----------------------------------------------------------

/** What happened since the mode came on (or the last 6 hours), newest
    first: reports filed, status changes, dispatches, SMART's events,
    checklist ticks and handovers. Fields, not sentences; the portal words
    them in English or Tagalog. */
create or replace function public.command_feed(p_limit integer default 40)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_active public.command_sessions; v_since timestamptz; v_lim integer := greatest(5, least(coalesce(p_limit, 40), 200));
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  v_active := public._command_active();
  v_since := coalesce(v_active.started_at - interval '1 hour', now() - interval '6 hours');
  return coalesce((select jsonb_agg(f order by (f ->> 'at')::timestamptz desc) from (
    select f from (
      (select jsonb_build_object('at', r.created_at, 'kind', 'filed', 'report_id', r.id, 'tracking_id', r.tracking_id, 'subject', r.subject, 'place', r.location_label) f
         from public.reports r where r.deleted_at is null and not r.is_sensitive and r.created_at >= v_since order by r.created_at desc limit v_lim)
      union all
      (select jsonb_build_object('at', l.created_at, 'kind', 'status', 'report_id', r.id, 'tracking_id', r.tracking_id, 'from', l.old_status, 'to', l.new_status,
                                 'by', (select full_name from public.users where id = l.changed_by), 'system', l.is_system)
         from public.status_logs l join public.reports r on r.id = l.report_id
        where l.created_at >= v_since and not r.is_sensitive and l.old_status is not null order by l.created_at desc limit v_lim)
      union all
      (select jsonb_build_object('at', coalesce(d.resolved_at, d.accepted_at, d.assigned_at), 'kind', 'dispatch', 'state', d.state, 'report_id', r.id, 'tracking_id', r.tracking_id,
                                 'tanod', (select full_name from public.users where id = d.tanod_id))
         from public.dispatches d join public.reports r on r.id = d.report_id
        where coalesce(d.resolved_at, d.accepted_at, d.assigned_at) >= v_since and not r.is_sensitive order by coalesce(d.resolved_at, d.accepted_at, d.assigned_at) desc limit v_lim)
      union all
      (select jsonb_build_object('at', e.at, 'kind', 'smart', 'event', e.kind, 'summary', e.summary, 'report_id', e.report_id)
         from public.smart_events e where e.at >= v_since and (e.report_id is null or not exists (select 1 from public.reports r where r.id = e.report_id and r.is_sensitive))
        order by e.at desc limit v_lim)
      union all
      (select jsonb_build_object('at', c.at, 'kind', 'check', 'item', c.item, 'done', c.done, 'en', l.en, 'fil', l.fil,
                                 'by', (select full_name from public.users where id = c.by_user))
         from public.command_checks c join public.command_sessions s on s.id = c.session_id join public.command_checklist l on l.mode = s.mode and l.key = c.item
        where c.at >= v_since order by c.at desc limit v_lim)
      union all
      (select jsonb_build_object('at', pc.at, 'kind', 'place', 'status', pc.status, 'name', p.name,
                                 'by', (select full_name from public.users where id = pc.by_user))
         from public.command_place_checks pc join public.places p on p.id = pc.place_id where pc.at >= v_since order by pc.at desc limit v_lim)
    ) u order by (f ->> 'at')::timestamptz desc limit v_lim) z(f)), '[]');
end $$;

-- ---------- the hall display ----------------------------------------------------

create or replace function public.command_display_link_create(p_label text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_token text := encode(gen_random_bytes(24), 'hex'); v_label text := nullif(trim(coalesce(p_label, '')), '');
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if v_label is null or char_length(v_label) < 2 then raise exception 'Name the display (for example: Hall TV)' using errcode = 'check_violation'; end if;
  insert into public.command_display_links (label, token_sha256, created_by) values (left(v_label, 60), encode(digest(v_token, 'sha256'), 'hex'), auth.uid());
  perform public._smart_event('display_link', null, format('Hall display link made: %s', left(v_label, 60)), '{}');
  return v_token;   -- shown once; only its hash is kept
end $$;

create or replace function public.command_display_link_revoke(p_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  update public.command_display_links set revoked_at = now() where id = p_id and revoked_at is null;
  if not found then raise exception 'No such display link' using errcode = 'check_violation'; end if;
  perform public._smart_event('display_link', null, 'Hall display link turned off', jsonb_build_object('id', p_id));
end $$;

/** The hall display: counts only. No names, no addresses, no tracking
    numbers, no places on a map. Anyone holding a live display link may
    read it (a television has no account); a wrong or revoked link reads
    nothing. */
create or replace function public.command_hall(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions set jit = off as $$
declare
  v_link public.command_display_links; v_active public.command_sessions; m public.command_modes%rowtype; v_day timestamptz;
  v_mode jsonb := null;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then return null; end if;
  select * into v_link from public.command_display_links where token_sha256 = encode(digest(p_token, 'sha256'), 'hex') and revoked_at is null;
  if not found then return null; end if;
  if v_link.last_seen_at is null or v_link.last_seen_at < now() - interval '1 minute' then
    update public.command_display_links set last_seen_at = now() where id = v_link.id;
  end if;
  v_day := date_trunc('day', now() at time zone 'Asia/Manila') at time zone 'Asia/Manila';
  v_active := public._command_active();
  if v_active.id is not null then
    select * into m from public.command_modes where mode = v_active.mode;
    v_mode := (select jsonb_build_object('mode', m.mode, 'en', m.name_en, 'fil', m.name_fil, 'since', v_active.started_at,
                 'reports', count(*), 'open', count(*) filter (where x.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
                 'resolved', count(*) filter (where x.status in ('resolved', 'closed')),
                 'tags', coalesce((select jsonb_agg(jsonb_build_object('en', t.en, 'fil', t.fil, 'reports', z.n) order by t.rank desc)
                                     from (select y.tag, count(*) n from public._command_reports(m.mode, v_active.started_at - interval '2 hours') y where y.tag is not null group by y.tag) z
                                     join public.command_tags t on t.mode = m.mode and t.tag = z.tag), '[]'),
                 'checklist_done', (select count(*) from public.command_checks c where c.session_id = v_active.id and c.done),
                 'checklist_total', (select count(*) from public.command_checklist l where l.mode = m.mode))
                 from public._command_reports(m.mode, v_active.started_at - interval '2 hours') x);
  end if;
  return jsonb_build_object(
    'as_of', now(),
    'barangay', (select name from public.barangay_boundary where id = 1),
    'today', (select jsonb_build_object('filed', count(*) filter (where r.created_at >= v_day),
                                        'resolved', count(*) filter (where r.resolved_at >= v_day),
                                        'open', count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')))
                from public.reports r where r.deleted_at is null and not r.is_sensitive),
    'tanods_on_duty', (select count(*) from public.users u where u.role = 'tanod' and u.duty_status = 'on_duty' and not coalesce(u.is_suspended, false)),
    'mode', v_mode);
end $$;

/** For the app: which mode is on, if any (a banner for tanods and admins). */
create or replace function public.command_now()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.users u where u.id = auth.uid() and u.role in ('admin', 'tanod')) then
    (select jsonb_build_object('mode', s.mode, 'en', m.name_en, 'fil', m.name_fil, 'since', s.started_at)
       from public.command_sessions s join public.command_modes m on m.mode = s.mode where s.ended_at is null limit 1) end
$$;

revoke all on function public.command_suggest(smallint), public.command_dismiss(text, integer), public.command_start(text, text, text),
  public.command_handover(text), public.command_end(text), public.command_check(text, boolean, text), public.command_place_check(bigint, text, text),
  public.command_set_auto(boolean), public.command_board(text, smallint), public.command_feed(integer),
  public.command_display_link_create(text), public.command_display_link_revoke(uuid), public.command_hall(text), public.command_now() from public, anon;
grant execute on function public.command_suggest(smallint), public.command_dismiss(text, integer), public.command_start(text, text, text),
  public.command_handover(text), public.command_end(text), public.command_check(text, boolean, text), public.command_place_check(bigint, text, text),
  public.command_set_auto(boolean), public.command_board(text, smallint), public.command_feed(integer),
  public.command_display_link_create(text), public.command_display_link_revoke(uuid), public.command_now() to authenticated;
grant execute on function public.command_hall(text) to anon, authenticated;
