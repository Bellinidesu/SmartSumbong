-- DRAFT — admin ↔ tanod chat (proposed 30 Sep 2026). NOT a migration.
--
-- Kept out of supabase/migrations on purpose so `supabase db push` never
-- picks it up. When the design is agreed, copy it in as the next numbered
-- migration and review it again against whatever has changed by then.
-- The design notes are in the "Tanod Chat Plan" page.
--
-- Shape: one conversation per tanod with "the barangay". Admins answer as
-- one desk, the same way a resident's question thread (0072) works; a
-- tanod never has to know which admin is on shift. The per-job dispatch
-- thread (0069) stays where it is — this is for everything that is not
-- one job: shift changes, "call the hall", general instructions.

set search_path = public, extensions;

-- ---------- tables -----------------------------------------------------

create table public.chat_threads (
  id               uuid primary key default gen_random_uuid(),
  tanod_id         uuid not null unique references public.users (id) on delete cascade,
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz
);

create table public.chat_messages (
  id          uuid primary key default gen_random_uuid(),
  thread_id   uuid not null references public.chat_threads (id) on delete cascade,
  author_id   uuid not null references public.users (id),
  from_admin  boolean not null,
  body        text check (body is null or char_length(body) <= 2000),
  -- Optional: a message about one complaint links to it.
  report_id   uuid references public.reports (id) on delete set null,
  -- Optional photo, same pinned-URL rule as the other media tables.
  media_url   text check (media_url is null or public.is_media_url(media_url)),
  created_at  timestamptz not null default now(),
  constraint chat_messages_not_empty check (body is not null or media_url is not null)
);

create index chat_messages_thread_idx on public.chat_messages (thread_id, created_at);

-- Unread counts: one row per reader per thread.
create table public.chat_reads (
  thread_id     uuid not null references public.chat_threads (id) on delete cascade,
  user_id       uuid not null references public.users (id) on delete cascade,
  last_read_at  timestamptz not null default now(),
  primary key (thread_id, user_id)
);

-- ---------- who can read ------------------------------------------------

alter table public.chat_threads  enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_reads    enable row level security;

create policy chat_threads_read on public.chat_threads
  for select using (public.is_admin() or tanod_id = auth.uid());

create policy chat_messages_read on public.chat_messages
  for select using (
    public.is_admin()
    or exists (select 1 from public.chat_threads t
                where t.id = chat_messages.thread_id and t.tanod_id = auth.uid()));

create policy chat_reads_own on public.chat_reads
  for select using (user_id = auth.uid());

-- No insert/update/delete policies: every write goes through the RPCs.

-- ---------- writes -----------------------------------------------------

-- An admin writes to a tanod (p_tanod), or a tanod writes to the
-- barangay (p_tanod null). The thread is created on first use.
create or replace function public.send_chat_message(
  p_body text, p_tanod uuid default null, p_report uuid default null,
  p_media_url text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_admin  boolean := public.is_admin();
  v_tanod  uuid;
  v_thread uuid;
  v_id     uuid;
  v_body   text := nullif(trim(coalesce(p_body, '')), '');
begin
  if v_admin then
    if p_tanod is null then raise exception 'Choose a tanod'; end if;
    v_tanod := p_tanod;
  else
    if public.my_role() <> 'tanod' then raise exception 'Only tanods and admins use chat'; end if;
    v_tanod := auth.uid();
  end if;
  if v_body is null and p_media_url is null then
    raise exception 'Write a message first';
  end if;

  insert into public.chat_threads (tanod_id) values (v_tanod)
  on conflict (tanod_id) do nothing;
  select id into v_thread from public.chat_threads where tanod_id = v_tanod;

  insert into public.chat_messages (thread_id, author_id, from_admin, body, report_id, media_url)
  values (v_thread, auth.uid(), v_admin, v_body, p_report, p_media_url)
  returning id into v_id;

  update public.chat_threads set last_message_at = now() where id = v_thread;

  -- The sender has read their own message.
  insert into public.chat_reads (thread_id, user_id, last_read_at)
  values (v_thread, auth.uid(), now())
  on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;

  -- Notify the other side; the existing push pipeline sends it on.
  if v_admin then
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_tanod, p_report, 'status_change',
            'Barangay: ' || coalesce(left(v_body, 140), 'sent a photo'));
  else
    insert into public.notifications (user_id, report_id, kind, message)
    select u.id, p_report, 'status_change',
           (select full_name from public.users where id = v_tanod) || ': '
           || coalesce(left(v_body, 140), 'sent a photo')
      from public.users u where u.role = 'admin';
  end if;

  return v_id;
end $$;

create or replace function public.mark_chat_read(p_thread uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.chat_threads t
                  where t.id = p_thread and (public.is_admin() or t.tanod_id = auth.uid())) then
    raise exception 'Conversation not found';
  end if;
  insert into public.chat_reads (thread_id, user_id, last_read_at)
  values (p_thread, auth.uid(), now())
  on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;
end $$;

-- The portal inbox: every tanod's conversation, newest first, with the
-- calling admin's unread count.
create or replace function public.chat_inbox()
returns table (thread_id uuid, tanod_id uuid, full_name text,
               last_message_at timestamptz, last_body text, unread integer)
language sql stable security definer set search_path = public, extensions as $$
  select t.id, t.tanod_id, u.full_name, t.last_message_at,
         (select m.body from public.chat_messages m
           where m.thread_id = t.id order by m.created_at desc limit 1),
         (select count(*)::integer from public.chat_messages m
           where m.thread_id = t.id and m.from_admin = false
             and m.created_at > coalesce(
                   (select r.last_read_at from public.chat_reads r
                     where r.thread_id = t.id and r.user_id = auth.uid()),
                   '-infinity'))
    from public.chat_threads t
    join public.users u on u.id = t.tanod_id
   where public.is_admin()
   order by t.last_message_at desc nulls last
$$;

revoke execute on function public.send_chat_message(text, uuid, uuid, text) from public, anon;
revoke execute on function public.mark_chat_read(uuid) from public, anon;
revoke execute on function public.chat_inbox() from public, anon;
grant execute on function public.send_chat_message(text, uuid, uuid, text) to authenticated;
grant execute on function public.mark_chat_read(uuid) to authenticated;
grant execute on function public.chat_inbox() to authenticated;

-- ---------- live -------------------------------------------------------

alter publication supabase_realtime add table public.chat_messages;
