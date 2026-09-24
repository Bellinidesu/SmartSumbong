-- 0063: escalation stops at level 3, and an idle case then cancels itself.
--
-- 0002's sweep capped escalation_level at 3 but kept firing every 24
-- hours after that — another admin notification and another "SLA
-- breach" status_logs row each day, for as long as the case sat there.
-- One case had been doing it for about a month.
--
-- Now:
--   * A report is escalated at most three times (levels 1, 2, 3).
--   * 24 hours after its third escalation, if no person has touched it
--     since (no non-system status_logs row newer than escalated_at), it
--     is cancelled by the system, with a system status_logs row saying
--     why, and the resident and admins are told. Any human status change
--     in the meantime pushes that back by another 24 hours.
--   * Only reports nobody has started on are auto-cancelled:
--     pending_review and validated — the same statuses a resident may
--     cancel themselves (cancel_report, 0030). A report already with a
--     tanod (assigned / in_progress / offline_investigation, or awaiting
--     a unit) stops escalating at 3 but is left for the barangay to
--     close, since cancelling it would strand the dispatch.
--
-- Carries 0062's exclusion of rejected and cancelled reports.

create or replace function public.sweep_overdue_reports()
returns void language plpgsql security definer set search_path = public as $$
begin
  -- Escalate: at most three times, 24 hours apart.
  with breached as (
    update public.reports
       set escalated_at = now(),
           escalation_level = escalation_level + 1
     where due_at < now()
       and status not in ('resolved', 'closed', 'archived',
                          'rejected', 'cancelled')
       and escalation_level < 3
       and (escalated_at is null or escalated_at < now() - interval '24 hours')
    returning id, tracking_id
  )
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, b.id, 'escalation',
         'Complaint ' || b.tracking_id || ' has breached its resolution deadline.'
    from breached b cross join public.users u
   where u.role = 'admin';

  insert into public.status_logs (report_id, new_status, remark, is_system)
  select id, status, 'SLA breach: resolution deadline elapsed.', true
    from public.reports
   where escalated_at = now();

  -- Cancel: a day after the third escalation, if still untouched.
  with idle as (
    select r.id, r.tracking_id, r.status as old_status, r.resident_id
      from public.reports r
     where r.status in ('pending_review', 'validated')
       and r.escalation_level >= 3
       and r.escalated_at < now() - interval '24 hours'
       and r.deleted_at is null
       and not exists (
             select 1 from public.status_logs l
              where l.report_id = r.id
                and l.is_system = false
                and l.created_at > r.escalated_at)
  ),
  cancelled as (
    update public.reports r
       set status = 'cancelled',
           closed_at = now()
      from idle i
     where r.id = i.id
    returning r.id
  ),
  logged as (
    insert into public.status_logs
      (report_id, old_status, new_status, remark, is_system)
    select i.id, i.old_status, 'cancelled',
           'Automatically cancelled: no action after three escalations.',
           true
      from idle i
      join cancelled c on c.id = i.id
    returning report_id
  )
  insert into public.notifications (user_id, report_id, kind, message)
  select i.resident_id, i.id, 'status_change',
         'Complaint ' || i.tracking_id || ' was cancelled after going '
         'unattended past its deadline. You may file it again if the '
         'issue continues.'
    from idle i
    join logged l on l.report_id = i.id
   where i.resident_id is not null
  union all
  select u.id, i.id, 'escalation',
         'Complaint ' || i.tracking_id || ' was automatically cancelled '
         'after three escalations with no action.'
    from idle i
    join logged l on l.report_id = i.id
    cross join public.users u
   where u.role = 'admin';
end $$;
