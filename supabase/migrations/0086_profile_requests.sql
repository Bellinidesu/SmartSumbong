-- 0086 — Name-change and ID re-upload requests (Martin, 6 Oct 2026).
--
-- Until now "Request a change" on the app's Edit Profile only sent admins a
-- notification (request_profile_change, 0026); nothing tracked it and the
-- admin changed the name by hand. Now a resident's (or tanod's) request
-- waits in profile_requests until an admin approves or declines it on the
-- portal, and the person is told either way:
--
--   * full_name      — the new name; approving changes it.
--   * id_document    — a fresh photo of a valid ID; approving replaces the
--                      one on file (and its type).
--
-- Mobile-number requests keep 0026's notify-only path: a number is the
-- sign-in identity, so changing it stays a counter job.

set search_path = public, extensions;

create table if not exists public.profile_requests (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.users (id) on delete cascade,
  kind           text not null check (kind in ('full_name', 'id_document')),
  new_full_name  text check (char_length(new_full_name) between 3 and 120),
  id_type        id_document_type,
  id_image_url   text check (id_image_url is null or public.is_media_url(id_image_url)),
  reason         text check (char_length(reason) <= 300),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  decided_by     uuid references public.users (id),
  decided_at     timestamptz,
  decision_note  text check (char_length(decision_note) <= 300),
  created_at     timestamptz not null default now(),
  constraint profile_request_has_value check (
    (kind = 'full_name' and new_full_name is not null)
    or (kind = 'id_document' and id_image_url is not null and id_type is not null))
);

create index if not exists profile_requests_pending_idx on public.profile_requests (status, created_at);
create unique index if not exists profile_requests_one_pending
  on public.profile_requests (user_id, kind) where status = 'pending';

alter table public.profile_requests enable row level security;

drop policy if exists profile_requests_read on public.profile_requests;
create policy profile_requests_read on public.profile_requests
  for select using ((select public.is_admin()) or user_id = (select auth.uid()));
-- No write policies: rows change only through the functions below.

create or replace function public._notify_admins(p_message text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, message)
  select a.id, 'status_change', p_message from public.users a
   where a.role = 'admin' and not coalesce(a.is_suspended, false);
$$;
revoke all on function public._notify_admins(text) from public, anon, authenticated;

-- 0026's entry point, now queueing a name change instead of only notifying.
create or replace function public.request_profile_change(
  p_field text, p_value text, p_reason text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name   text;
  v_value  text := trim(coalesce(p_value, ''));
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_comma  int;
begin
  select full_name into v_name from public.users where id = auth.uid();
  if v_name is null then
    raise exception 'Not signed in';
  end if;
  if p_field not in ('mobile_number', 'full_name') then
    raise exception 'Only a name or mobile number change can be requested';
  end if;

  if p_field = 'mobile_number' then
    if v_value !~ '^\+639[0-9]{9}$' then
      raise exception 'Enter the mobile number as 09XXXXXXXXX';
    end if;
    perform public._notify_admins(v_name || ' asked to change their mobile number to ' || v_value
                                  || coalesce(' — ' || v_reason, '') || '. Changing a number is done at the counter.');
    return;
  end if;

  v_comma := position(',' in v_value);
  if v_comma <= 1 or length(trim(substring(v_value from v_comma + 1))) = 0 then
    raise exception 'Write the name as Last Name, First Name';
  end if;
  if exists (select 1 from public.profile_requests where user_id = auth.uid() and kind = 'full_name' and status = 'pending') then
    raise exception 'You already have a name change waiting for the barangay';
  end if;

  insert into public.profile_requests (user_id, kind, new_full_name, reason)
  values (auth.uid(), 'full_name', v_value, v_reason);
  perform public._notify_admins(v_name || ' asked to change their name to ' || v_value
                                || coalesce(' — ' || v_reason, '') || '. Review it under Residents.');
end $$;

revoke all on function public.request_profile_change(text, text, text) from public, anon;
grant execute on function public.request_profile_change(text, text, text) to authenticated;

create or replace function public.request_id_reupload(
  p_id_type text, p_id_image_url text, p_reason text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text;
begin
  select full_name into v_name from public.users where id = auth.uid() and role in ('resident', 'tanod');
  if v_name is null then
    raise exception 'Only a resident or tanod account can send an ID';
  end if;
  if not exists (select 1 from unnest(enum_range(null::id_document_type)) e where e::text = p_id_type) then
    raise exception 'Choose the type of ID';
  end if;
  if p_id_image_url is null or not public.is_media_url(p_id_image_url) or p_id_image_url !~ '/ids/' then
    raise exception 'The ID photo did not upload correctly. Try again.';
  end if;
  if exists (select 1 from public.profile_requests where user_id = auth.uid() and kind = 'id_document' and status = 'pending') then
    raise exception 'You already have an ID waiting for the barangay';
  end if;

  insert into public.profile_requests (user_id, kind, id_type, id_image_url, reason)
  values (auth.uid(), 'id_document', p_id_type::id_document_type, p_id_image_url, nullif(trim(coalesce(p_reason, '')), ''));
  perform public._notify_admins(v_name || ' sent a new photo of their ID. Review it under Residents.');
end $$;

revoke all on function public.request_id_reupload(text, text, text) from public, anon;
grant execute on function public.request_id_reupload(text, text, text) to authenticated;

create or replace function public.decide_profile_request(
  p_request uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  r      public.profile_requests%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may decide a profile request';
  end if;
  select * into r from public.profile_requests where id = p_request for update;
  if not found then
    raise exception 'No such request';
  end if;
  if r.status <> 'pending' then
    raise exception 'This request has already been decided';
  end if;
  if not p_approve and v_note is null then
    raise exception 'Give a reason for declining; the person sees it';
  end if;

  if p_approve then
    if r.kind = 'full_name' then
      update public.users set full_name = r.new_full_name where id = r.user_id;
    else
      update public.users set id_image_url = r.id_image_url, id_type = r.id_type where id = r.user_id;
    end if;
  end if;

  update public.profile_requests
     set status = case when p_approve then 'approved' else 'declined' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = v_note
   where id = p_request;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (r.user_id, auth.uid(),
          case r.kind when 'full_name' then 'name_change_' else 'id_reupload_' end || case when p_approve then 'approved' else 'declined' end,
          case r.kind when 'full_name' then 'Name change to ' || r.new_full_name else 'New ID photo' end
          || case when p_approve then ' approved' else ' declined' end || coalesce(': ' || v_note, ''));

  insert into public.notifications (user_id, kind, message)
  values (r.user_id, 'status_change',
          case r.kind when 'full_name' then 'Your name change' else 'Your new ID photo' end
          || case when p_approve then ' was approved by the barangay.' else ' was not approved' || coalesce(': ' || v_note, '.') end);
end $$;

revoke all on function public.decide_profile_request(uuid, boolean, text) from public, anon;
grant execute on function public.decide_profile_request(uuid, boolean, text) to authenticated;
