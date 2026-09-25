-- 0065: the tanod handling a case can ask the resident for more details.
--
-- Figma REPORTS - REQUIRE ADDTL / TICKET ADDTL SUBMITTED. While a report
-- is being worked on, the tanod with the accepted dispatch (or an admin)
-- asks a question; the resident answers with text and, optionally, a
-- photo or short video; the answer reaches whoever asked.
--
-- One open request per report at a time: a second question waits until
-- the first is answered, so the resident is never looking at two.
--
-- Both steps are RPCs (SECURITY DEFINER, ownership checked inside), in
-- the same shape as request_reopen (0037): each writes a status_logs row
-- — so the resident's timeline and the portal's case page show the
-- exchange with no changes of their own — and a notification, which
-- the existing push path delivers. Attachments go into report_media
-- through the same insert as file_report/request_reopen, so the photo
-- cap, the 10 MB total and the URL pins (0017/0060) all still apply.

set search_path = public, extensions;

create table if not exists public.detail_requests (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.reports (id) on delete cascade,
  requested_by  uuid not null references public.users (id),
  message       text not null check (char_length(message) between 1 and 300),
  requested_at  timestamptz not null default now(),
  response      text check (char_length(response) <= 500),
  responded_at  timestamptz
);

create index if not exists detail_requests_report_idx
  on public.detail_requests (report_id, requested_at desc);

-- At most one unanswered request per report.
create unique index if not exists detail_requests_one_open
  on public.detail_requests (report_id) where responded_at is null;

alter table public.detail_requests enable row level security;

-- Read: the resident who filed the report, any tanod dispatched to it,
-- and admins. No insert/update/delete policies — the RPCs below are the
-- only way in. (select …) wrappers as 0061 requires.
drop policy if exists detail_requests_read on public.detail_requests;
create policy detail_requests_read on public.detail_requests
  for select to authenticated
  using (
    exists (select 1 from public.reports r
             where r.id = detail_requests.report_id
               and r.resident_id = (select auth.uid()))
    or exists (select 1 from public.dispatches d
                where d.report_id = detail_requests.report_id
                  and d.tanod_id = (select auth.uid()))
    or (select public.is_admin())
  );

grant select on public.detail_requests to authenticated;

-- ---------- ask ----------------------------------------------------------

create or replace function public.request_additional_details(
  p_report  uuid,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_status  report_status;
  v_owner   uuid;
  v_ticket  text;
  v_message text := nullif(trim(p_message), '');
  v_id      uuid;
begin
  if v_message is null then
    raise exception 'Please say what details you need';
  end if;
  if char_length(v_message) > 300 then
    raise exception 'Keep the request under 300 characters';
  end if;

  select status, resident_id, tracking_id
    into v_status, v_owner, v_ticket
    from public.reports
   where id = p_report and deleted_at is null;

  if v_status is null then
    raise exception 'Report not found';
  end if;

  if not (public.is_admin()
          or exists (select 1 from public.dispatches d
                      where d.report_id = p_report
                        and d.tanod_id = auth.uid()
                        and d.state = 'accepted')) then
    raise exception 'Only the tanod handling this report can ask for more details';
  end if;

  if v_status not in ('assigned', 'in_progress', 'offline_investigation') then
    raise exception 'More details can only be asked for while the report is being worked on';
  end if;

  if exists (select 1 from public.detail_requests
              where report_id = p_report and responded_at is null) then
    raise exception 'There is already a request for more details waiting on the resident';
  end if;

  insert into public.detail_requests (report_id, requested_by, message)
  values (p_report, auth.uid(), v_message)
  returning id into v_id;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark)
  values
    (p_report, auth.uid(), v_status, v_status,
     'More details requested: ' || v_message);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_owner, p_report, 'status_change'::notification_kind,
          'More details needed for ' || v_ticket || ': ' || v_message);

  return v_id;
end $$;

comment on function public.request_additional_details(uuid, text) is
  'The accepted tanod (or an admin) asks the resident for more details '
  'on a report being worked on. One open request per report. Logs to '
  'status_logs and notifies the resident. 0065.';

revoke all on function public.request_additional_details(uuid, text) from public, anon;
grant execute on function public.request_additional_details(uuid, text) to authenticated;

-- ---------- answer -------------------------------------------------------

create or replace function public.submit_additional_details(
  p_request uuid,
  p_details text,
  p_media   jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_report    uuid;
  v_asker     uuid;
  v_answered  timestamptz;
  v_status    report_status;
  v_owner     uuid;
  v_ticket    text;
  v_details   text := nullif(trim(p_details), '');
  v_media     jsonb := coalesce(p_media, '[]'::jsonb);
  v_item      jsonb;
begin
  if jsonb_typeof(v_media) <> 'array' then
    raise exception 'p_media must be a JSON array of {media_url, mime_type, bytes}'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_details is null and jsonb_array_length(v_media) = 0 then
    raise exception 'Please add the details or a photo';
  end if;
  if char_length(coalesce(v_details, '')) > 500 then
    raise exception 'Keep the details under 500 characters';
  end if;

  select q.report_id, q.requested_by, q.responded_at
    into v_report, v_asker, v_answered
    from public.detail_requests q
   where q.id = p_request;

  if v_report is null then
    raise exception 'Request not found';
  end if;

  select status, resident_id, tracking_id
    into v_status, v_owner, v_ticket
    from public.reports
   where id = v_report and deleted_at is null;

  if v_owner is distinct from auth.uid() then
    raise exception 'Only the resident who filed this report can answer';
  end if;
  if v_answered is not null then
    raise exception 'This request has already been answered';
  end if;
  if v_status not in ('assigned', 'in_progress', 'offline_investigation') then
    raise exception 'This report is no longer being worked on';
  end if;

  update public.detail_requests
     set response = v_details,
         responded_at = now()
   where id = p_request;

  -- Same insert idiom as request_reopen (0037): report_media_cap and
  -- the URL pins still apply.
  for v_item in select value from jsonb_array_elements(v_media)
  loop
    insert into public.report_media (report_id, media_url, mime_type, bytes)
    values (v_report,
            v_item ->> 'media_url',
            v_item ->> 'mime_type',
            (v_item ->> 'bytes')::integer);
  end loop;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark)
  values
    (v_report, auth.uid(), v_status, v_status,
     'Resident sent more details: ' ||
       coalesce(v_details, 'photo/video attached'));

  -- Whoever asked, and the tanod now holding the case if that's someone
  -- else (a reroute in between).
  insert into public.notifications (user_id, report_id, kind, message)
  -- (the union already drops a duplicate recipient)
  select u, v_report, 'status_change'::notification_kind,
         'The resident sent more details for ' || v_ticket || '.'
    from (
      select v_asker as u
      union
      select d.tanod_id from public.dispatches d
       where d.report_id = v_report and d.state = 'accepted'
    ) t
   where u is not null;
end $$;

comment on function public.submit_additional_details(uuid, text, jsonb) is
  'The resident answers an open detail request with text and/or media '
  '(into report_media under the usual caps and URL pins). Logs to '
  'status_logs and notifies the asker and the current tanod. 0065.';

revoke all on function public.submit_additional_details(uuid, text, jsonb) from public, anon;
grant execute on function public.submit_additional_details(uuid, text, jsonb) to authenticated;

-- Live updates to both apps, as notifications (0046).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'detail_requests') then
    alter publication supabase_realtime add table public.detail_requests;
  end if;
end $$;
