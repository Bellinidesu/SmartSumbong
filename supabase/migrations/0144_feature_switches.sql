-- =============================================================
-- SmartSumbong — 0144 Feature switches
--
-- Parts of the system can be switched off without removing them. Ace, 29 Oct
-- 2026: the command center (0143) and the Workspace go offline until after the
-- defense, as agreed with the barangay on the Monday before. Anything switched
-- off stays in the code and the database; it simply is not reachable.
--
--   feature_switches        one row per switchable part, on or off
--   feature_on(key)         true when a part is on (false for a key that does not exist)
--   feature_set(key, on)    an administrator turns a part on or off (SMART event kept)
--
-- The command center's functions answer "off" when it is switched off, so it
-- cannot be reached by calling them directly: the board and starting a mode
-- refuse, the suggestion, the hall display and the app's banner answer nothing,
-- and the five-minute auto check does nothing. Who may flip a switch will move to
-- the super admin when that role exists (the next piece of work).
-- =============================================================

set search_path = public, extensions;

create table public.feature_switches (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  label_en   text not null,
  label_fil  text not null,
  enabled    boolean not null default true,
  note       text check (char_length(note) <= 300),
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.feature_switches enable row level security;
create policy feature_switches_read on public.feature_switches for select using ((select public.is_admin()));
comment on table public.feature_switches is '0144: parts of the system that can be switched off without removing them. Written only by feature_set().';

insert into public.feature_switches (key, label_en, label_fil, enabled, note) values
  ('workspace',      'Workspace',      'Tablero ng Gawain',   false, 'Offline until after the defense (agreed 26 Oct 2026).'),
  ('command_center', 'Command center', 'Sentro ng Pamamahala', false, 'Offline until after the defense (agreed 26 Oct 2026). Spatial Distribution, the hall display and the tanod banner follow it.');

create or replace function public.feature_on(p_key text)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select enabled from public.feature_switches where key = p_key), false)
$$;
revoke all on function public.feature_on(text) from public, anon;
grant execute on function public.feature_on(text) to authenticated;

create or replace function public.feature_set(p_key text, p_on boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_label text;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  update public.feature_switches set enabled = coalesce(p_on, false), updated_by = auth.uid(), updated_at = now()
   where key = p_key returning label_en into v_label;
  if not found then raise exception 'No such feature' using errcode = 'check_violation'; end if;
  perform public._smart_event('feature_switch', null, format('%s switched %s', v_label, case when p_on then 'on' else 'off' end), jsonb_build_object('key', p_key, 'on', coalesce(p_on, false)));
end $$;
revoke all on function public.feature_set(text, boolean) from public, anon;
grant execute on function public.feature_set(text, boolean) to authenticated;

-- ---------- the command center answers "off" -----------------------------------

create or replace function public.command_now()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.feature_on('command_center')
               and exists (select 1 from public.users u where u.id = auth.uid() and u.role in ('admin', 'tanod')) then
    (select jsonb_build_object('mode', s.mode, 'en', m.name_en, 'fil', m.name_fil, 'since', s.started_at)
       from public.command_sessions s join public.command_modes m on m.mode = s.mode where s.ended_at is null limit 1) end
$$;

-- a guard at the top of each function that does the command center's work, patched into the live definition
do $$
declare
  g record; v_def text; v_new text;
begin
  for g in select * from (values
    ('command_suggest(smallint)',      E'  if not public.feature_on(''command_center'') then return null; end if;\n'),
    ('command_board(text,smallint)',   E'  if not public.feature_on(''command_center'') then raise exception ''The command center is switched off'' using errcode = ''check_violation''; end if;\n'),
    ('command_start(text,text,text)',  E'  if not public.feature_on(''command_center'') then raise exception ''The command center is switched off'' using errcode = ''check_violation''; end if;\n'),
    ('command_hall(text)',             E'  if not public.feature_on(''command_center'') then return null; end if;\n'),
    ('_command_auto()',                E'  if not public.feature_on(''command_center'') then return; end if;\n')
  ) as t(sig, guard) loop
    v_def := replace(pg_get_functiondef(('public.' || g.sig)::regprocedure), E'\r', '');
    if position(E'\nbegin\n' in v_def) = 0 then raise exception 'no begin in %', g.sig; end if;
    v_new := replace(v_def, E'\nbegin\n', E'\nbegin\n' || g.guard);   -- the first one only is the function's own (none of these has an earlier block)
    if v_new = v_def then raise exception 'not patched %', g.sig; end if;
    execute v_new;
  end loop;
end $$;
