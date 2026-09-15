-- =============================================================
-- SmartSumbong — 0057 Appeal a rejected complaint
--
-- Rose's feedback list, last unaddressed item: the resident app has no
-- way to dispute a denial. Reports Screen (Figma 2869:156) already gives
-- a finished report two Reopen-style moves — Cancel and Request Reopen
-- — through request_reopen() (0002/0037), which only files a request;
-- reopen_report() (0002, admin-only) is what actually restarts the case.
-- A rejected complaint had neither half of that pair. This migration
-- gives it both, following the exact same split so the barangay keeps
-- deciding and the trail keeps recording who asked and who acted:
--
--   request_appeal(report, reason, media)  — resident-callable. Notifies
--     admins and writes a status_logs row that does not move the status,
--     precisely mirroring request_reopen()'s own "the request is a
--     notification, not a status change" comment.
--
--   appeal_report(report, remark)          — admin-only. Moves
--     'rejected' back to 'validated' and notifies the resident, the
--     mirror of reopen_report().
--
-- WHY NOT REUSE reopened_count. That column (0001) is documented as
-- counting how many times a FINISHED (resolved/closed) case was reopened
-- for a second look at work already done — the Report Summary and the
-- resident's own "Reopened Nx" bubble both read it with that meaning.
-- An appeal is a different event: the barangay never did the work in
-- the first place, it refused to. Folding the two into one counter
-- would make "Reopened 1x" appear on a report nobody ever worked on, so
-- this adds its own timestamp column instead — appealed_at, a one-shot
-- marker (was this ever appealed and reinstated) rather than a counter,
-- matching how e.g. verified_at marks a one-time event elsewhere in
-- this schema.
--
-- WHY appeal_report() RECOMPUTES due_at FROM sla_policies RATHER THAN
-- REOPEN_REPORT()'S FLAT "+24 hours". reopen_report() reopens a case the
-- barangay already finished, so a short fixed window to double-check the
-- outcome is the right shape. An appeal sends a rejected complaint back
-- to the START of the normal pipeline — assign, dispatch, resolve — so
-- it gets the real SLA window for its category, the same computation
-- set_report_deadline() (0001) runs at filing time, not a shortcut.
-- =============================================================

set search_path = public, extensions;

alter table public.reports
  add column if not exists appealed_at timestamptz;

comment on column public.reports.appealed_at is
  'Set once, by appeal_report() (0057), the first time a rejected complaint is reinstated on appeal. Never cleared or incremented — a marker, not a counter (see reopened_count for why appeals do not share it).';

-- ---------- resident: file the request ------------------------

create or replace function public.request_appeal(
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
  insert into public.notifications (user_id, kind, message)
  select a.id, 'status_change',
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
end $$;

comment on function public.request_appeal(uuid, text, jsonb) is
  'The resident disputes a denial; the barangay decides. Notifies admins, writes the request to status_logs, and optionally attaches evidence to report_media, without changing the report''s status. SECURITY DEFINER for the same reason as request_reopen.';

revoke all on function public.request_appeal(uuid, text, jsonb) from public, anon;
grant execute on function public.request_appeal(uuid, text, jsonb) to authenticated;

-- ---------- admin: decide the appeal ---------------------------

create or replace function public.appeal_report(
  p_report uuid,
  p_remark text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_hrs    integer;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may act on an appeal';
  end if;

  select * into v_report
    from public.reports
   where id = p_report and deleted_at is null
     for update;

  if not found then
    raise exception 'No such report';
  end if;

  if v_report.status <> 'rejected' then
    raise exception 'Only a rejected complaint can be reinstated on appeal';
  end if;

  select resolution_hours into v_hrs
    from public.sla_policies where category = v_report.category;

  update public.reports
     set status      = 'validated',
         appealed_at = now(),
         due_at      = case when v_hrs is not null
                            then now() + make_interval(hours => v_hrs)
                            else null end
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), 'rejected', 'validated',
          coalesce(v_remark, 'Appeal granted: reinstated for review.'));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          format('Your appeal for %s was granted. It is back with the barangay.',
                 v_report.tracking_id));
end $$;

comment on function public.appeal_report(uuid, text) is
  'Grants a resident appeal: moves rejected back to validated with a fresh SLA window (from sla_policies, same as filing), marks appealed_at, logs the trail and notifies the resident. Admin only. The mirror of reopen_report() for the rejected path.';

revoke execute on function public.appeal_report(uuid, text) from public, anon;
grant  execute on function public.appeal_report(uuid, text) to authenticated;
