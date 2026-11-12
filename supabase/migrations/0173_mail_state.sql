-- 0173: BarangayMail keeps its state the way Gmail does, and the case chats remember where each person was (12 Nov 2026).
--
-- Ace: "BarangayMail imitates Gmail one to one", "case chats fully imitate Messenger". The Inbox so far knew only "read". This adds, all of it
-- one person's own and never seen by anyone else:
--   - on a message: Cc and Bcc (role), and the thread it belongs to (the batch of the first message of its reply chain);
--   - per person and message: starred, archived, in the trash (and gone from it), snoozed until a time;
--   - labels a person makes and puts on messages;
--   - drafts;
--   - for the case chats, per person and conversation: when they last read it, and whether it is muted, pinned or put away.
-- Everything is written through the functions below (which check that the message or case is the caller's to touch), read with row
-- level security limited to the caller's own rows, and nothing here is reachable signed out. Mail between people is still only
-- written by send_mail along the ladder; no rule about who may write to whom changes.

-- ---------- on the message ----------

alter table public.inbox_messages
  add column role text not null default 'to' check (role in ('to', 'cc', 'bcc')),
  add column thread_id uuid;

-- the thread of a message is the batch of the first message of its chain, the same for every recipient of that first message
with recursive chain as (
  select id, batch as root from public.inbox_messages where reply_to is null
  union all
  select m.id, c.root from public.inbox_messages m join chain c on m.reply_to = c.id
)
update public.inbox_messages m set thread_id = c.root from chain c where c.id = m.id;
update public.inbox_messages set thread_id = batch where thread_id is null;   -- a reply whose first message is gone starts its own thread
alter table public.inbox_messages alter column thread_id set not null;
create index inbox_messages_thread_idx on public.inbox_messages (thread_id, created_at);

create or replace function public._inbox_thread()
returns trigger language plpgsql set search_path = public as $$
begin
  new.thread_id := coalesce((select m.thread_id from public.inbox_messages m where m.id = new.reply_to), new.batch);
  return new;
end $$;
create trigger inbox_messages_thread before insert on public.inbox_messages
  for each row execute function public._inbox_thread();
comment on column public.inbox_messages.role is '0173: how this recipient was addressed: to, cc, or bcc (hidden from the other recipients).';
comment on column public.inbox_messages.thread_id is '0173: the batch of the first message of the reply chain; set by the inbox_messages_thread trigger.';

-- ---------- per person and message ----------

create table public.mail_state (
  user_id       uuid not null references public.users (id) on delete cascade,
  batch         uuid not null,
  starred       boolean not null default false,
  archived      boolean not null default false,
  trashed_at    timestamptz,
  purged        boolean not null default false,
  snoozed_until timestamptz,
  updated_at    timestamptz not null default now(),
  primary key (user_id, batch)
);
comment on table public.mail_state is '0173: one person''s own marks on a message (by its batch): star, archive, trash, snooze. Read and written only by that person, through mail_flag.';
alter table public.mail_state enable row level security;
create policy mail_state_read on public.mail_state for select to authenticated using (user_id = (select auth.uid()));

create table public.mail_labels (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  colour     text not null default '#5F6368' check (colour ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now()
);
create unique index mail_labels_user_name_key on public.mail_labels (user_id, lower(name));
comment on table public.mail_labels is '0173: the labels a person makes for their own mail.';
alter table public.mail_labels enable row level security;
create policy mail_labels_read on public.mail_labels for select to authenticated using (user_id = (select auth.uid()));

create table public.mail_label_links (
  user_id  uuid not null references public.users (id) on delete cascade,
  batch    uuid not null,
  label_id bigint not null references public.mail_labels (id) on delete cascade,
  primary key (user_id, batch, label_id)
);
create index mail_label_links_label_idx on public.mail_label_links (user_id, label_id);
comment on table public.mail_label_links is '0173: which of a person''s labels sit on which message.';
alter table public.mail_label_links enable row level security;
create policy mail_label_links_read on public.mail_label_links for select to authenticated using (user_id = (select auth.uid()));

create table public.mail_drafts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.users (id) on delete cascade,
  to_ids     uuid[] not null default '{}',
  cc_ids     uuid[] not null default '{}',
  bcc_ids    uuid[] not null default '{}',
  subject    text not null default '' check (char_length(subject) <= 140),
  body       text not null default '' check (char_length(body) <= 4000),
  report_id  uuid references public.reports (id) on delete set null,
  reply_to   bigint references public.inbox_messages (id) on delete set null,
  updated_at timestamptz not null default now()
);
create index mail_drafts_user_idx on public.mail_drafts (user_id, updated_at desc);
comment on table public.mail_drafts is '0173: a person''s unsent mail. Read and written only by that person; sending it (send_mail with p_draft) removes it.';
alter table public.mail_drafts enable row level security;
create policy mail_drafts_read on public.mail_drafts for select to authenticated using (user_id = (select auth.uid()));

-- ---------- the case chats: where each person was ----------

create table public.chat_state (
  user_id    uuid not null references public.users (id) on delete cascade,
  report_id  uuid not null references public.reports (id) on delete cascade,
  conv       text not null check (conv = 'r' or conv ~ '^d-[0-9a-f-]{36}$'),
  seen_at    timestamptz,
  muted      boolean not null default false,
  pinned     boolean not null default false,
  archived   boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, report_id, conv)
);
comment on table public.chat_state is '0173: per person and conversation of a case (r = the resident, d-<dispatch> = a tanod): when it was last read, and whether it is muted, pinned or put away. Written through chat_state_set.';
alter table public.chat_state enable row level security;
create policy chat_state_read on public.chat_state for select to authenticated using (user_id = (select auth.uid()));

-- ---------- writing them ----------

/** Mark messages (by batch) the signed-in person sent or received: star, archive, trash, delete forever, snooze. Returns how many were touched. */
create or replace function public.mail_flag(
  p_batches uuid[], p_starred boolean default null, p_archived boolean default null, p_trashed boolean default null,
  p_purged boolean default null, p_snooze timestamptz default null, p_unsnooze boolean default false)
returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has an Inbox' using errcode = 'insufficient_privilege'; end if;
  if cardinality(coalesce(p_batches, '{}')) > 200 then raise exception 'Two hundred messages at most' using errcode = 'check_violation'; end if;
  with mine as (
    select distinct m.batch from public.inbox_messages m
     where m.batch = any (coalesce(p_batches, '{}')) and (m.recipient = auth.uid() or m.sender = auth.uid())),
  up as (
    insert into public.mail_state as s (user_id, batch, starred, archived, trashed_at, purged, snoozed_until)
    select auth.uid(), mine.batch, coalesce(p_starred, false), coalesce(p_archived, false),
           case when coalesce(p_trashed, false) then now() end, coalesce(p_purged, false),
           case when p_unsnooze then null else p_snooze end
      from mine
    on conflict (user_id, batch) do update set
      starred = coalesce(p_starred, s.starred),
      archived = coalesce(p_archived, s.archived),
      trashed_at = case when p_trashed is true then coalesce(s.trashed_at, now()) when p_trashed is false then null else s.trashed_at end,
      purged = coalesce(p_purged, s.purged),
      snoozed_until = case when p_unsnooze then null when p_snooze is not null then p_snooze else s.snoozed_until end,
      updated_at = now()
    returning 1)
  select count(*) into v_n from up;
  return v_n;
end $$;

/** Mark the signed-in person's messages read or unread (the recipient's side only). */
create or replace function public.mail_set_read(p_ids bigint[], p_read boolean)
returns integer
language sql security definer set search_path = public as $$
  with u as (
    update public.inbox_messages set read_at = case when p_read then coalesce(read_at, now()) else null end
     where id = any (coalesce(p_ids, '{}')) and recipient = auth.uid() and (read_at is null) = p_read returning 1)
  select count(*)::integer from u
$$;

/** Make a label (p_id null) or rename / recolour one of the caller's. Fifty at most. */
create or replace function public.mail_label_save(p_id bigint, p_name text, p_colour text default '#5F6368')
returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_name text := nullif(trim(coalesce(p_name, '')), '');
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has an Inbox' using errcode = 'insufficient_privilege'; end if;
  if v_name is null then raise exception 'Give the label a name' using errcode = 'check_violation'; end if;
  if p_id is null then
    if (select count(*) from public.mail_labels where user_id = auth.uid()) >= 50 then raise exception 'Fifty labels at most' using errcode = 'check_violation'; end if;
    insert into public.mail_labels (user_id, name, colour) values (auth.uid(), left(v_name, 40), coalesce(p_colour, '#5F6368')) returning id into v_id;
  else
    update public.mail_labels set name = left(v_name, 40), colour = coalesce(p_colour, colour) where id = p_id and user_id = auth.uid() returning id into v_id;
    if v_id is null then raise exception 'No such label' using errcode = 'check_violation'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.mail_label_delete(p_id bigint)
returns void
language sql security definer set search_path = public as $$
  delete from public.mail_labels where id = p_id and user_id = auth.uid()
$$;

/** Put one of the caller's labels on messages (by batch), or take it off. */
create or replace function public.mail_label_apply(p_batches uuid[], p_label bigint, p_on boolean)
returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if not exists (select 1 from public.mail_labels where id = p_label and user_id = auth.uid()) then raise exception 'No such label' using errcode = 'check_violation'; end if;
  if cardinality(coalesce(p_batches, '{}')) > 200 then raise exception 'Two hundred messages at most' using errcode = 'check_violation'; end if;
  if p_on then
    with mine as (select distinct m.batch from public.inbox_messages m where m.batch = any (p_batches) and (m.recipient = auth.uid() or m.sender = auth.uid())),
    ins as (insert into public.mail_label_links (user_id, batch, label_id) select auth.uid(), batch, p_label from mine on conflict do nothing returning 1)
    select count(*) into v_n from ins;
  else
    with del as (delete from public.mail_label_links where user_id = auth.uid() and label_id = p_label and batch = any (coalesce(p_batches, '{}')) returning 1)
    select count(*) into v_n from del;
  end if;
  return v_n;
end $$;

/** Keep a draft (p_id null starts one). The lists are not checked against the ladder here; sending does that. A hundred drafts at most. */
create or replace function public.mail_draft_save(
  p_id bigint, p_to uuid[], p_cc uuid[], p_bcc uuid[], p_subject text, p_body text, p_report uuid default null, p_reply_to bigint default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has an Inbox' using errcode = 'insufficient_privilege'; end if;
  if p_report is not null and not (public.is_full_viewer() or public.admin_sees_report(p_report)) then raise exception 'You can only attach a case you can see' using errcode = 'insufficient_privilege'; end if;
  if p_reply_to is not null and not exists (select 1 from public.inbox_messages m where m.id = p_reply_to and (m.recipient = auth.uid() or m.sender = auth.uid())) then p_reply_to := null; end if;
  if p_id is null then
    if (select count(*) from public.mail_drafts where user_id = auth.uid()) >= 100 then raise exception 'A hundred drafts at most' using errcode = 'check_violation'; end if;
    insert into public.mail_drafts (user_id, to_ids, cc_ids, bcc_ids, subject, body, report_id, reply_to)
    values (auth.uid(), coalesce(p_to, '{}'), coalesce(p_cc, '{}'), coalesce(p_bcc, '{}'), left(coalesce(p_subject, ''), 140), left(coalesce(p_body, ''), 4000), p_report, p_reply_to)
    returning id into v_id;
  else
    update public.mail_drafts set to_ids = coalesce(p_to, '{}'), cc_ids = coalesce(p_cc, '{}'), bcc_ids = coalesce(p_bcc, '{}'),
           subject = left(coalesce(p_subject, ''), 140), body = left(coalesce(p_body, ''), 4000), report_id = p_report, reply_to = p_reply_to, updated_at = now()
     where id = p_id and user_id = auth.uid() returning id into v_id;
    if v_id is null then raise exception 'No such draft' using errcode = 'check_violation'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.mail_draft_delete(p_id bigint)
returns void
language sql security definer set search_path = public as $$
  delete from public.mail_drafts where id = p_id and user_id = auth.uid()
$$;

/** Who a message went to (and who it is from), for a message the caller sent or received. A bcc is shown only to the sender. */
create or replace function public.mail_batch_people(p_batch uuid)
returns table (user_id uuid, full_name text, role text)
language sql stable security definer set search_path = public as $$
  select r.recipient, u.full_name, r.role
    from public.inbox_messages r join public.users u on u.id = r.recipient
   where r.batch = p_batch
     and exists (select 1 from public.inbox_messages x where x.batch = p_batch and (x.recipient = auth.uid() or x.sender = auth.uid()))
     and (r.role <> 'bcc' or r.recipient = auth.uid() or exists (select 1 from public.inbox_messages x where x.batch = p_batch and x.sender = auth.uid()))
   order by case r.role when 'to' then 0 when 'cc' then 1 else 2 end, u.full_name
$$;

/** Remember where the signed-in person was in one conversation of a case: read up to, muted, pinned, put away. Reading never goes backwards. */
create or replace function public.chat_state_set(
  p_report uuid, p_conv text, p_seen timestamptz default null, p_muted boolean default null, p_pinned boolean default null, p_archived boolean default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has case chats' using errcode = 'insufficient_privilege'; end if;
  if not (public.is_full_viewer() or public.admin_sees_report(p_report)) then raise exception 'You can only keep the chats of a case you can see' using errcode = 'insufficient_privilege'; end if;
  insert into public.chat_state as s (user_id, report_id, conv, seen_at, muted, pinned, archived)
  values (auth.uid(), p_report, p_conv, p_seen, coalesce(p_muted, false), coalesce(p_pinned, false), coalesce(p_archived, false))
  on conflict (user_id, report_id, conv) do update set
    seen_at = greatest(s.seen_at, p_seen),
    muted = coalesce(p_muted, s.muted), pinned = coalesce(p_pinned, s.pinned), archived = coalesce(p_archived, s.archived), updated_at = now();
end $$;

-- ---------- sending: Cc, Bcc and a draft that is sent ----------

drop function if exists public.send_mail(uuid[], text, text, uuid, bigint);
create or replace function public.send_mail(
  p_to uuid[], p_subject text, p_body text, p_report uuid default null, p_reply_to bigint default null,
  p_cc uuid[] default '{}', p_bcc uuid[] default '{}', p_draft bigint default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_batch uuid := gen_random_uuid(); v_to uuid;
  v_subject text := nullif(trim(coalesce(p_subject, '')), ''); v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_tos uuid[] := array(select distinct x from unnest(coalesce(p_to, '{}')) x where x is not null);
  v_ccs uuid[] := array(select distinct x from unnest(coalesce(p_cc, '{}')) x where x is not null and x <> all (coalesce(p_to, '{}')));
  v_bccs uuid[] := array(select distinct x from unnest(coalesce(p_bcc, '{}')) x where x is not null and x <> all (coalesce(p_to, '{}')) and x <> all (coalesce(p_cc, '{}')));
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has an Inbox' using errcode = 'insufficient_privilege'; end if;
  if cardinality(v_tos) + cardinality(v_ccs) + cardinality(v_bccs) = 0 then raise exception 'Choose who it is for' using errcode = 'check_violation'; end if;
  if cardinality(v_tos) + cardinality(v_ccs) + cardinality(v_bccs) > 30 then raise exception 'Thirty people at most' using errcode = 'check_violation'; end if;
  if v_subject is null or v_body is null then raise exception 'Write a subject and a message' using errcode = 'check_violation'; end if;
  foreach v_to in array v_tos || v_ccs || v_bccs loop
    if not public._mail_may_send(auth.uid(), v_to) then
      raise exception 'You cannot write to % (mail runs along the ladder)', coalesce((select public.display_name(full_name) from public.users where id = v_to), 'that person')
        using errcode = 'insufficient_privilege';
    end if;
  end loop;
  if p_report is not null and not (public.is_full_viewer() or public.admin_sees_report(p_report)) then
    raise exception 'You can only attach a case you can see' using errcode = 'insufficient_privilege';
  end if;
  if p_reply_to is not null and not exists (select 1 from public.inbox_messages m where m.id = p_reply_to and (m.recipient = auth.uid() or m.sender = auth.uid())) then
    raise exception 'No such message to reply to' using errcode = 'check_violation';
  end if;
  insert into public.inbox_messages (batch, sender, recipient, kind, subject, body, report_id, reply_to, role)
  select v_batch, auth.uid(), x.id, 'mail', left(v_subject, 140), left(v_body, 4000), p_report, p_reply_to, x.role
    from (select unnest(v_tos) as id, 'to' as role union all select unnest(v_ccs), 'cc' union all select unnest(v_bccs), 'bcc') x;
  if p_draft is not null then delete from public.mail_drafts where id = p_draft and user_id = auth.uid(); end if;
  return v_batch;
end $$;

-- ---------- who may call what ----------

revoke all on function public._inbox_thread() from public, anon, authenticated;
revoke all on function public.mail_flag(uuid[], boolean, boolean, boolean, boolean, timestamptz, boolean), public.mail_set_read(bigint[], boolean),
  public.mail_label_save(bigint, text, text), public.mail_label_delete(bigint), public.mail_label_apply(uuid[], bigint, boolean),
  public.mail_draft_save(bigint, uuid[], uuid[], uuid[], text, text, uuid, bigint), public.mail_draft_delete(bigint), public.mail_batch_people(uuid),
  public.chat_state_set(uuid, text, timestamptz, boolean, boolean, boolean),
  public.send_mail(uuid[], text, text, uuid, bigint, uuid[], uuid[], bigint) from public, anon, authenticated;
grant execute on function public.mail_flag(uuid[], boolean, boolean, boolean, boolean, timestamptz, boolean), public.mail_set_read(bigint[], boolean),
  public.mail_label_save(bigint, text, text), public.mail_label_delete(bigint), public.mail_label_apply(uuid[], bigint, boolean),
  public.mail_draft_save(bigint, uuid[], uuid[], uuid[], text, text, uuid, bigint), public.mail_draft_delete(bigint), public.mail_batch_people(uuid),
  public.chat_state_set(uuid, text, timestamptz, boolean, boolean, boolean),
  public.send_mail(uuid[], text, text, uuid, bigint, uuid[], uuid[], bigint) to authenticated;

-- the tables: readable by the signed-in person (their own rows, by the policies above), written only through the functions
revoke all on table public.mail_state, public.mail_labels, public.mail_label_links, public.mail_drafts, public.chat_state from public, anon, authenticated;
grant select on table public.mail_state, public.mail_labels, public.mail_label_links, public.mail_drafts, public.chat_state to authenticated;
