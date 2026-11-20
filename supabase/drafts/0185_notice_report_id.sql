-- DRAFT: not applied until Ace says apply 0185
-- 0185_notice_report_id: reopen and appeal requests notify only admins who can open the case, with a Review link
--
-- Probe (tools/sweep/probe.py): request_reopen and request_appeal insert one notice per active admin with no report_id, so _notifications_scope (which only
-- filters notices that carry a report_id) lets them all through: 6 administrators told, 4 of whom cannot open the case, and no Review button.
-- Adding the case id fixes both at once; the trigger does the scoping.
--
-- UNDO (plain language): re-run the previous definitions of request_appeal, request_reopen (0037 and 0057); no data changes.
-- Proof: supabase/drafts/tests/0185_notice_report_id.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_notice_report_id.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

create or replace function public.request_appeal(p_report uuid, p_reason text, p_media jsonb DEFAULT '[]'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_status report_status;
  v_owner  uuid;
  v_ticket text;
  v_item   jsonb;
begin
  if nullif(trim(p_reason), '') is null then
    raise exception 'Please explain why this rejection should be reviewed again';
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
    raise exception 'Only the resident who filed a report may appeal it';
  end if;
  if v_status <> 'rejected' then
    raise exception 'Only a rejected complaint can be appealed';
  end if;

  -- The request is a notification, not a status change. An admin acts on
  -- it with appeal_report(), which is where due_at and appealed_at live
  -- — the same split request_reopen()/reopen_report() already use.
  insert into public.notifications (user_id, report_id, kind, message)
  select a.id, p_report, 'status_change',
         'Appeal requested for ' || v_ticket || ': ' || trim(p_reason)
    from public.users a
   where a.role = 'admin'
     and not a.is_suspended;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark)
  values
    (p_report, auth.uid(), v_status, v_status,
     'Resident appealed the rejection: ' || trim(p_reason));

  -- Same insert idiom as request_reopen() (0037) — report_media_insert
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
end $function$;

create or replace function public.request_reopen(p_report uuid, p_reason text, p_media jsonb DEFAULT '[]'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  insert into public.notifications (user_id, report_id, kind, message)
  select a.id, p_report, 'status_change',
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
end $function$;

-- UNDO SQL (not run; for the person applying this):
-- -- restore request_reopen / request_appeal from 0037 / 0057 (create or replace with the old insert)
