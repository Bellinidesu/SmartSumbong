-- 0088 — Profile-request notifications that lead somewhere (Rose, 6 Oct 2026).
--
-- A name-change or new-ID notification now names the person it is about
-- (notifications.subject_user_id), so the portal's Review button opens that
-- resident's (or tanod's) profile directly. Names in these notifications
-- read First Last, as Rose asked; they are still stored as
-- "Last Name, First Name" (0032), which the ID check compares against.

set search_path = public, extensions;

alter table public.notifications
  add column if not exists subject_user_id uuid references public.users (id) on delete set null;

comment on column public.notifications.subject_user_id is
  'The account a notification is about (0088): a profile request''s '
  'resident or tanod, so the portal can open their profile.';

-- "Besarra, Rose" -> "Rose Besarra"; anything without a comma unchanged.
create or replace function public.display_name(p_name text)
returns text language sql immutable as $$
  select case when position(',' in coalesce(p_name, '')) > 1
              then trim(substring(p_name from position(',' in p_name) + 1)) || ' ' || trim(split_part(p_name, ',', 1))
              else p_name end
$$;

drop function if exists public._notify_admins(text);
create or replace function public._notify_admins(p_message text, p_subject uuid default null)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, message, subject_user_id)
  select a.id, 'status_change', p_message, p_subject from public.users a
   where a.role = 'admin' and not coalesce(a.is_suspended, false);
$$;
revoke all on function public._notify_admins(text, uuid) from public, anon, authenticated;

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
    perform public._notify_admins(public.display_name(v_name) || ' asked to change their mobile number to ' || v_value
                                  || coalesce(' — ' || v_reason, '') || '. Changing a number is done at the counter.', auth.uid());
    return;
  end if;

  v_comma := position(',' in v_value);
  if v_comma <= 1 or length(trim(substring(v_value from v_comma + 1))) = 0 then
    raise exception 'Enter both a first name and a last name';
  end if;
  if exists (select 1 from public.profile_requests where user_id = auth.uid() and kind = 'full_name' and status = 'pending') then
    raise exception 'You already have a name change waiting for the barangay';
  end if;

  insert into public.profile_requests (user_id, kind, new_full_name, reason)
  values (auth.uid(), 'full_name', v_value, v_reason);
  perform public._notify_admins(public.display_name(v_name) || ' asked to change their name to ' || public.display_name(v_value)
                                || coalesce(' — ' || v_reason, '') || '.', auth.uid());
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
  perform public._notify_admins(public.display_name(v_name) || ' sent a new photo of their ID.', auth.uid());
end $$;

revoke all on function public.request_id_reupload(text, text, text) from public, anon;
grant execute on function public.request_id_reupload(text, text, text) to authenticated;
