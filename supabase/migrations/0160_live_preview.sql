-- =============================================================
-- SmartSumbong — 0160 Live preview on a phone (developer mode)
--
-- Ace, 1 Nov 2026: the Control Room edits what the resident app shows, and a real phone running the real app should be able to show those edits as
-- they are made, before anything is saved. Residents and tanods must never be able to reach it.
--
--   feature_switches 'live_preview'   off by default; while off, nothing can be started or paired
--   preview_sessions                  one row per pairing: a code (kept hashed), a secret channel name, an expiry
--   preview_attempts                  wrong codes per person; five wrong ones lock them out for 15 minutes
--   preview_start()                   a super admin gets a one-time code and the channel (the code is shown once)
--   preview_pair(code, device)        the phone trades the code for the channel; a wrong code answers {ok:false}, it does not raise,
--                                     so the failed try is kept
--   preview_end(id)                   the super admin ends it
--
-- The channel only carries what the screens display, from the portal to the phone. The phone writes nothing back.
-- =============================================================

set search_path = public, extensions;

insert into public.feature_switches (key, label_en, label_fil, enabled, note) values
  ('live_preview', 'Live preview on a phone', 'Live na preview sa telepono', false,
   'Developer mode: a super admin can show unsaved Control Room edits on a paired phone. While off, nothing can be paired.')
on conflict (key) do nothing;

create table public.preview_sessions (
  id            uuid primary key default gen_random_uuid(),
  created_by    uuid not null references public.users (id) on delete cascade,
  code_hash     text not null,
  channel       text not null unique default encode(extensions.gen_random_bytes(18), 'hex'),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  paired_at     timestamptz,
  paired_by     uuid references public.users (id) on delete set null,
  paired_device text check (char_length(paired_device) <= 60),
  ended_at      timestamptz
);
create index preview_sessions_code_idx on public.preview_sessions (code_hash) where ended_at is null and paired_at is null;
alter table public.preview_sessions enable row level security;
create policy preview_sessions_own on public.preview_sessions for select using (created_by = (select auth.uid()) and (select public.is_super_admin()));
comment on table public.preview_sessions is '0160: pairings of a phone with a super admin''s Control Room. Written only by preview_start / preview_pair / preview_end.';

create table public.preview_attempts (
  user_id      uuid primary key references public.users (id) on delete cascade,
  failed       integer not null default 0,
  locked_until timestamptz,
  updated_at   timestamptz not null default now()
);
alter table public.preview_attempts enable row level security;   -- no policy: only the functions below read or write it

create or replace function public.preview_start()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';   -- no I, L, O, 0 or 1: it is read out and typed on a phone
  v_code text := ''; v_id uuid; v_channel text; v_exp timestamptz := now() + interval '30 minutes'; i integer;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only a super admin can show the app on a phone' using errcode = '42501';
  end if;
  if not public.feature_on('live_preview') then
    raise exception 'Live preview is switched off' using errcode = 'P0001';
  end if;
  update public.preview_sessions set ended_at = now() where created_by = auth.uid() and ended_at is null;   -- one at a time
  for i in 1..8 loop v_code := v_code || substr(v_alpha, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % 31), 1); end loop;
  insert into public.preview_sessions (created_by, code_hash, expires_at)
  values (auth.uid(), encode(extensions.digest(v_code, 'sha256'), 'hex'), v_exp) returning id, channel into v_id, v_channel;
  return jsonb_build_object('id', v_id, 'code', v_code, 'channel', v_channel, 'expires_at', v_exp);
end $$;

create or replace function public.preview_pair(p_code text, p_device text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_hash text := encode(extensions.digest(upper(btrim(coalesce(p_code, ''))), 'sha256'), 'hex'); s public.preview_sessions; a public.preview_attempts;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not public.feature_on('live_preview') then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  select * into a from public.preview_attempts where user_id = auth.uid();
  if found and a.locked_until is not null and a.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'until', a.locked_until);
  end if;
  select * into s from public.preview_sessions
   where code_hash = v_hash and ended_at is null and paired_at is null and expires_at > now() for update;
  if not found then
    insert into public.preview_attempts (user_id, failed, updated_at) values (auth.uid(), 1, now())
    on conflict (user_id) do update set failed = case when preview_attempts.failed + 1 >= 5 then 0 else preview_attempts.failed + 1 end,
      locked_until = case when preview_attempts.failed + 1 >= 5 then now() + interval '15 minutes' else preview_attempts.locked_until end, updated_at = now();
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  update public.preview_sessions set paired_at = now(), paired_by = auth.uid(), paired_device = left(coalesce(p_device, ''), 60) where id = s.id;
  delete from public.preview_attempts where user_id = auth.uid();
  return jsonb_build_object('ok', true, 'channel', s.channel, 'expires_at', s.expires_at);
end $$;

create or replace function public.preview_end(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'Only a super admin can end a preview' using errcode = '42501'; end if;
  update public.preview_sessions set ended_at = now() where id = p_id and created_by = auth.uid() and ended_at is null;
end $$;

revoke all on function public.preview_start() from public, anon;
revoke all on function public.preview_pair(text, text) from public, anon;
revoke all on function public.preview_end(uuid) from public, anon;
grant execute on function public.preview_start() to authenticated;
grant execute on function public.preview_pair(text, text) to authenticated;
grant execute on function public.preview_end(uuid) to authenticated;
