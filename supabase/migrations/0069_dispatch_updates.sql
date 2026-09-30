-- 0069_dispatch_updates.sql
--
-- The dispatch window (branch C): a tanod's accepted dispatch becomes a
-- running thread — updates with photos, admin replies, and the steps
-- On the way / Arrived — instead of one field report that closes it.
--
-- Until now submit_field_report() was the only thing a tanod could send,
-- and sending it resolved the case. It still does; it is now the last
-- message of the thread rather than the only one.
--
-- Who sees what:
--   the tanod on the dispatch and admins   every row
--   the resident who filed the complaint   the steps only, and those
--                                          reach them as status_logs
--                                          remarks and notifications,
--                                          which their app already shows
-- A tanod's working notes ("gate locked, coming back at 3") are for the
-- barangay, not the complainant, so notes and their photos are not
-- resident-readable. The final field report and its proof are, as
-- before (0024).
--
-- Every write goes through an RPC, like the rest of dispatches (0003).

set search_path = public, extensions;

-- ---------- dispatch_updates -----------------------------------------

create table if not exists public.dispatch_updates (
  id           uuid primary key default gen_random_uuid(),
  dispatch_id  uuid not null references public.dispatches (id) on delete cascade,
  author_id    uuid not null references public.users (id),
  kind         text not null check (kind in ('note', 'step')),
  step         text check (step in ('on_the_way', 'arrived')),
  body         text check (body is null or char_length(body) <= 2000),
  created_at   timestamptz not null default now(),
  constraint dispatch_updates_shape check (
    (kind = 'step' and step is not null)
    or (kind = 'note' and step is null)
  )
);

create index if not exists dispatch_updates_idx
  on public.dispatch_updates (dispatch_id, created_at);

alter table public.dispatch_updates enable row level security;

drop policy if exists dispatch_updates_read on public.dispatch_updates;
create policy dispatch_updates_read on public.dispatch_updates
  for select using (
    public.is_admin()
    or exists (select 1 from public.dispatches d
                where d.id = dispatch_updates.dispatch_id
                  and d.tanod_id = auth.uid())
  );

comment on table public.dispatch_updates is
  'The dispatch window thread (0069): tanod notes, admin replies and the '
  'On the way / Arrived steps. Readable by the dispatched tanod and '
  'admins; written only through post_dispatch_update() and '
  'set_dispatch_step().';

-- The dispatch's current step, so a list or the window can show it
-- without reading the thread.
alter table public.dispatches
  add column if not exists step text
  check (step in ('on_the_way', 'arrived'));

-- ---------- media on an update ---------------------------------------
-- An update's photos are dispatch_media rows tagged with the update.
-- Untagged rows are the final field report's proof, as before.

alter table public.dispatch_media
  add column if not exists update_id uuid
  references public.dispatch_updates (id) on delete cascade;

-- 0024's policy, with the resident limited to the final proof.
drop policy if exists dispatch_media_read on public.dispatch_media;
create policy dispatch_media_read on public.dispatch_media
  for select using (
    exists (
      select 1
        from public.dispatches d
        join public.reports r on r.id = d.report_id
       where d.id = dispatch_media.dispatch_id
         and (
           d.tanod_id = auth.uid()
           or public.is_admin()
           or (r.resident_id = auth.uid() and r.deleted_at is null
               and dispatch_media.update_id is null)
         )
    )
  );

-- ---------- post_dispatch_update() -----------------------------------
-- A note from the dispatched tanod (accepted dispatch) or an admin
-- (assigned or accepted dispatch), with optional media rows
-- [{media_url, mime_type, bytes}] — the same shape the tanod app already
-- inserts, checked by dispatch_media's own constraints. An admin's reply
-- notifies the tanod.

create or replace function public.post_dispatch_update(
  p_dispatch uuid, p_body text, p_media jsonb default '[]'::jsonb)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_d     public.dispatches%rowtype;
  v_admin boolean := public.is_admin();
  v_body  text := nullif(trim(coalesce(p_body, '')), '');
  v_id    uuid;
  v_tick  text;
  m       jsonb;
begin
  select * into v_d from public.dispatches where id = p_dispatch;
  if not found then
    raise exception 'Dispatch not found';
  end if;

  if v_admin then
    if v_d.state not in ('assigned', 'accepted') then
      raise exception 'This dispatch is closed';
    end if;
  elsif v_d.tanod_id is distinct from auth.uid() or v_d.state <> 'accepted' then
    raise exception 'Dispatch not found, not yours, or not accepted';
  end if;

  if v_body is null and jsonb_array_length(coalesce(p_media, '[]'::jsonb)) = 0 then
    raise exception 'An update needs a message or a photo';
  end if;
  if jsonb_array_length(coalesce(p_media, '[]'::jsonb)) > 6 then
    raise exception 'Up to 6 attachments per update';
  end if;

  insert into public.dispatch_updates (dispatch_id, author_id, kind, body)
  values (p_dispatch, auth.uid(), 'note', v_body)
  returning id into v_id;

  for m in select * from jsonb_array_elements(coalesce(p_media, '[]'::jsonb)) loop
    insert into public.dispatch_media (dispatch_id, update_id, media_url, mime_type, bytes)
    values (p_dispatch, v_id, m->>'media_url', m->>'mime_type', (m->>'bytes')::integer);
  end loop;

  if v_admin and v_d.tanod_id is not null then
    select tracking_id into v_tick from public.reports where id = v_d.report_id;
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_d.tanod_id, v_d.report_id, 'status_change'::notification_kind,
            'Barangay on ' || coalesce(v_tick, 'your dispatch') || ': '
            || coalesce(left(v_body, 140), 'sent a photo'));
  end if;

  return v_id;
end $$;

-- ---------- set_dispatch_step() --------------------------------------
-- On the way, then Arrived; forward only. Each step is a thread row, a
-- status_logs remark (the resident's timeline) and a notification to
-- the resident.

create or replace function public.set_dispatch_step(p_dispatch uuid, p_step text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_d      public.dispatches%rowtype;
  v_status report_status;
  v_owner  uuid;
  v_tick   text;
  v_line   text;
begin
  if p_step not in ('on_the_way', 'arrived') then
    raise exception 'Unknown step';
  end if;

  select * into v_d from public.dispatches
   where id = p_dispatch and tanod_id = auth.uid() and state = 'accepted'
   for update;
  if not found then
    raise exception 'Dispatch not found, not yours, or not accepted';
  end if;

  if v_d.step = p_step or (v_d.step = 'arrived' and p_step = 'on_the_way') then
    return; -- already there; a double tap is not an error
  end if;

  update public.dispatches set step = p_step where id = p_dispatch;

  insert into public.dispatch_updates (dispatch_id, author_id, kind, step)
  values (p_dispatch, auth.uid(), 'step', p_step);

  select status, resident_id, tracking_id into v_status, v_owner, v_tick
    from public.reports where id = v_d.report_id;

  v_line := case p_step
              when 'on_the_way' then 'Tanod is on the way.'
              else 'Tanod has arrived.'
            end;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_d.report_id, auth.uid(), v_status, v_status, v_line);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_owner, v_d.report_id, 'status_change'::notification_kind,
          case p_step
            when 'on_the_way' then 'A tanod is on the way to ' || v_tick || '.'
            else 'The tanod has arrived for ' || v_tick || '.'
          end);
end $$;

revoke execute on function public.post_dispatch_update(uuid, text, jsonb) from public, anon;
revoke execute on function public.set_dispatch_step(uuid, text) from public, anon;
grant execute on function public.post_dispatch_update(uuid, text, jsonb) to authenticated;
grant execute on function public.set_dispatch_step(uuid, text) to authenticated;

-- Live thread in the window and on the case page.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'dispatch_updates') then
    alter publication supabase_realtime add table public.dispatch_updates;
  end if;
end $$;
