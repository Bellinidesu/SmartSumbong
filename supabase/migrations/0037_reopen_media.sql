-- =============================================================
-- SmartSumbong — 0037 optional evidence photo on a reopen request
--
-- Figma parity audit (27 Aug 2026): the Reopen sheet (2780:3594) has an
-- optional "Attach Media" tile that request_reopen() had no parameter
-- for. Widening it rather than adding a second RPC, because the two
-- already differ only by whether the resident had a photo to add —
-- same authorization, same status_logs write, same notification.
--
-- report_media has no notion of "which submission event a row came
-- from" — it is keyed only to report_id (0001) — so a reopen photo
-- lands in the same gallery as the report's original evidence. That is
-- deliberate, not a shortcut: it is the same table file_report() (0017)
-- already writes to, so it reuses is_media_url() (0018) and
-- enforce_media_cap()'s 35 MB combined ceiling (0033) exactly as they
-- already apply to that report, rather than inventing a parallel path
-- with its own limits to keep in step.
--
-- p_media follows file_report()'s own shape and validation
-- (jsonb array of {media_url, mime_type, bytes}) so the two RPCs stay
-- consistent from the client's point of view — same UploadedMedia.toJson()
-- feeds both.
-- =============================================================

set search_path = public, extensions;

drop function if exists public.request_reopen(uuid, text);

create or replace function public.request_reopen(
  p_report uuid,
  p_reason text,
  p_media  jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_status  report_status;
  v_owner   uuid;
  v_ticket  text;
  v_item    jsonb;
begin
  if nullif(trim(p_reason), '') is null then
    raise exception 'Please say why this report should be reopened';
  end if;

  if jsonb_typeof(coalesce(p_media, '[]'::jsonb)) <> 'array' then
    raise exception 'p_media must be a JSON array of {media_url, mime_type, bytes}'
      using errcode = 'invalid_parameter_value';
  end if;

  select status, resident_id, tracking_id
    into v_status, v_owner, v_ticket
    from public.reports
   where id = p_report and deleted_at is null;

  if v_status is null then
    raise exception 'Report not found';
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the resident who filed a report may ask to reopen it';
  end if;
  if v_status not in ('resolved', 'closed') then
    raise exception 'Only a finished report can be reopened';
  end if;

  -- The request is a notification, not a status change. An admin acts on
  -- it with reopen_report(), which is where the SLA clock and the
  -- reopened_count live.
  insert into public.notifications (user_id, kind, message)
  select a.id, 'status_change',
         'Reopen requested for ' || v_ticket || ': ' || trim(p_reason)
    from public.users a
   where a.role = 'admin'
     and not a.is_suspended;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark)
  values
    (p_report, auth.uid(), v_status, v_status,
     'Resident requested reopening: ' || trim(p_reason));

  -- Same insert idiom as file_report() (0017) — report_media_insert
  -- and report_media_url_pinned still apply; SECURITY DEFINER bypasses
  -- RLS the same way the rest of this function already does, so the
  -- ownership check above is what makes this safe, not the policy.
  for v_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
  loop
    insert into public.report_media (report_id, media_url, mime_type, bytes)
    values (p_report,
            v_item ->> 'media_url',
            v_item ->> 'mime_type',
            (v_item ->> 'bytes')::integer);
  end loop;
end $$;

comment on function public.request_reopen(uuid, text, jsonb) is
  'The resident asks; the barangay decides. Notifies admins, writes '
  'the request to status_logs, and optionally attaches one evidence '
  'photo to report_media (0037) without changing the report''s status. '
  'SECURITY DEFINER for the same reason as cancel_report — the '
  'status_logs and report_media inserts are otherwise admin/owner-only '
  'under RLS.';

revoke all on function public.request_reopen(uuid, text, jsonb) from public, anon;
grant execute on function public.request_reopen(uuid, text, jsonb) to authenticated;
