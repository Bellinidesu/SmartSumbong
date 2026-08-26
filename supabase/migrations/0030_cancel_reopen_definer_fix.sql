-- =============================================================
-- SmartSumbong — 0030 cancel_report / request_reopen actually work
--
-- Group 5's QA exchange (26 Aug 2026) found both broken: cancelling
-- report BRG-2026-0050 and reopening BRG-2026-0043 each produced the
-- portal-side generic "That did not work. Please try again." — not one
-- of the specific, expected refusal messages 0023 was written to raise.
--
-- ROOT CAUSE. Both functions were declared SECURITY INVOKER in 0023, so
-- residents_.cancel_report()/request_reopen() run as the calling
-- resident, not as the function owner. Two RLS policies then block them
-- silently or loudly:
--
--   * reports_admin_update (0003) is `using (public.is_admin())` — the
--     only UPDATE policy on public.reports. As invoker, a resident's
--     `update ... set status = 'cancelled' where id = p_report` matches
--     zero rows under RLS. No exception; the report just does not
--     change.
--   * status_logs_insert (0003) is `with check (public.is_admin() and
--     changed_by = auth.uid() and is_system = false)` — deliberately,
--     per that policy's own comment: "The transition functions are
--     SECURITY DEFINER and run as the table owner, so they bypass this
--     policy... the only direct writer left is an admin." 0023's two
--     functions are not SECURITY DEFINER, so this INSERT — which both
--     functions do unconditionally, right after the update — hits a
--     real row-level-security violation. That's the exception whose
--     message reached the portal and matched none of _friendly()'s
--     known substrings in reports_screen.dart.
--
-- The UPDATE fails quietly; the INSERT fails loudly and rolls the whole
-- transaction back, which is why nothing changed in either report
-- despite the loud error.
--
-- FIX. Match the pattern 0003 already documented for every other status
-- transition: SECURITY DEFINER, with the authorisation done explicitly
-- in the function body instead of leaned on RLS. Both functions already
-- have that check — `if v_owner is distinct from auth.uid() then raise
-- exception...` — 0023 just didn't pair it with the right SECURITY
-- mode. Nothing about who may call this, or when, changes: same
-- ownership check, same pending_review/validated-only rule for
-- cancellation, same resolved/closed-only rule for a reopen request.
-- =============================================================

set search_path = public, extensions;

create or replace function public.cancel_report(
  p_report uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old    report_status;
  v_owner  uuid;
begin
  -- No longer protected by reports_resident_read as invoker would be —
  -- SECURITY DEFINER bypasses RLS, so the ownership check right below is
  -- now the only thing standing between a resident and someone else's
  -- report. It was already here; it is now load-bearing rather than
  -- redundant.
  select status, resident_id
    into v_old, v_owner
    from public.reports
   where id = p_report and deleted_at is null;

  if v_old is null then
    raise exception 'Report not found';
  end if;

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
  'DEFINER (0030): the reports UPDATE and status_logs INSERT both need '
  'privileges RLS gives only admins and the DEFINER transition '
  'functions (see status_logs_insert in 0003) — the explicit ownership '
  'check below is what makes that safe, not RLS.';

revoke all on function public.cancel_report(uuid, text) from public, anon;
grant execute on function public.cancel_report(uuid, text) to authenticated;

create or replace function public.request_reopen(
  p_report uuid,
  p_reason text
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
  'the request to status_logs without changing the report. SECURITY '
  'DEFINER (0030) for the same reason as cancel_report — the '
  'status_logs INSERT is admin-only under RLS otherwise. Actually '
  'reopening is reopen_report() in 0002, which is admin-only because it '
  'restarts the SLA clock and increments reopened_count.';

revoke all on function public.request_reopen(uuid, text) from public, anon;
grant execute on function public.request_reopen(uuid, text) to authenticated;

-- Verification. Confirm both are now definer, not invoker:
--
--   select proname, case when prosecdef then 'DEFINER' else 'INVOKER' end
--     from pg_proc
--    where proname in ('cancel_report', 'request_reopen');
--
-- Expect DEFINER for both rows.
