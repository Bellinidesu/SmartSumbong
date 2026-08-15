-- =============================================================
-- SmartSumbong — 0023 A resident may withdraw; only the barangay reopens
--
-- Rose's Reports screen puts two actions in the resident's three-dot
-- menu — Cancel and Reopen — and the schema supports neither. This adds
-- the first properly and gives the second an honest shape.
--
-- CANCEL. Withdrawing your own complaint is the resident's to make. You
-- reported a stray dog and it wandered off; you reported illegal parking
-- and the car moved. Forcing that through a barangay official wastes
-- their time and teaches residents that the app cannot be trusted with
-- small things.
--
-- But only while nobody is working on it. Once a tanod has been
-- dispatched, someone is walking to a location, and a complaint that
-- evaporates underneath them is worse than one that stays open. So
-- cancellation is allowed from pending_review and validated only.
--
-- REOPEN IS NOT ADDED. reopen_report() in 0002 raises for anyone who is
-- not an admin, and that is correct: reopening restarts the SLA clock,
-- re-notifies staff, and increments a counter the Report Summary reads.
-- Handing that lever to the person with the most reason to pull it
-- repeatedly would make the resolution figures meaningless.
--
-- Instead the resident's Reopen button raises a *request*: it notifies
-- every admin with the resident's stated reason, and an admin decides.
-- The screen is Rose's, the reason field is Rose's, and the only visible
-- difference is that the success copy says the request was sent rather
-- than that the case was reopened. That difference is worth stating
-- plainly in the manuscript — it is the same reasoning as tanod approval
-- being a roster check: authority stays with the barangay.
--
-- WHY 'cancelled' RATHER THAN A SOFT DELETE. reports.deleted_at exists,
-- but a withdrawn complaint is not a mistake to be hidden. It is part of
-- the barangay's record — how often residents withdraw, and at what
-- stage, is a real signal about whether the queue is moving. The Report
-- Summary counts it; the resident sees it in their own list.
-- =============================================================

set search_path = public, extensions;

alter type report_status add value if not exists 'cancelled';

-- ---------- who may withdraw, and when -----------------------

create or replace function public.cancel_report(
  p_report uuid,
  p_reason text default null
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_old    report_status;
  v_owner  uuid;
begin
  -- SECURITY INVOKER, so reports_resident_read decides whether this
  -- caller can even see the row. A resident querying someone else's
  -- report gets no row and the not-found branch below.
  select status, resident_id
    into v_old, v_owner
    from public.reports
   where id = p_report and deleted_at is null;

  if v_old is null then
    raise exception 'Report not found';
  end if;

  -- Reading is not owning: reports_resident_read also admits admins and
  -- the dispatched tanod. Only the person who filed it may withdraw it.
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the resident who filed a report may cancel it';
  end if;

  if v_old not in ('pending_review', 'validated') then
    raise exception
      'This report can no longer be cancelled because the barangay has '
      'already started working on it';
  end if;

  update public.reports
     set status = 'cancelled',
         closed_at = now()
   where id = p_report;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark)
  values
    (p_report, auth.uid(), v_old, 'cancelled',
     coalesce(nullif(trim(p_reason), ''), 'Withdrawn by the resident'));
end $$;

comment on function public.cancel_report(uuid, text) is
  'Lets the resident who filed a complaint withdraw it, but only before '
  'anyone is working on it — pending_review or validated. SECURITY '
  'INVOKER so RLS applies, with an explicit ownership check because '
  'reports_resident_read also admits admins and the dispatched tanod.';

revoke all on function public.cancel_report(uuid, text) from public, anon;
grant execute on function public.cancel_report(uuid, text) to authenticated;

-- ---------- asking the barangay to reopen ---------------------

create or replace function public.request_reopen(
  p_report uuid,
  p_reason text
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_status  report_status;
  v_owner   uuid;
  v_ticket  text;
begin
  if nullif(trim(p_reason), '') is null then
    raise exception 'Please say why this report should be reopened';
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
end $$;

comment on function public.request_reopen(uuid, text) is
  'The resident asks; the barangay decides. Notifies admins and writes '
  'the request to status_logs without changing the report. Actually '
  'reopening is reopen_report() in 0002, which is admin-only because it '
  'restarts the SLA clock and increments reopened_count.';

revoke all on function public.request_reopen(uuid, text) from public, anon;
grant execute on function public.request_reopen(uuid, text) to authenticated;

-- Verification. Run separately — note that a new enum value cannot be
-- used in the same transaction that adds it, so run this after.
--
--   select 'cancelled in enum' as part,
--          case when 'cancelled' = any (
--            select unnest(enum_range(null::report_status))::text)
--          then 'OK' else 'MISSING' end as state
--   union all
--   select 'cancel_report',
--          case when exists (select 1 from pg_proc where proname='cancel_report')
--          then 'OK' else 'MISSING' end
--   union all
--   select 'request_reopen',
--          case when exists (select 1 from pg_proc where proname='request_reopen')
--          then 'OK' else 'MISSING' end;
