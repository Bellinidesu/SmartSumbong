-- 0062: the SLA sweep skips rejected and cancelled reports.
--
-- 0002's sweep_overdue_reports() excludes resolved / closed / archived,
-- but 'rejected' (0001) and 'cancelled' (0023) are just as final. A
-- rejected or cancelled report past its due_at was being escalated every
-- 24 hours: its escalation_level climbed, every admin got an "has
-- breached its resolution deadline" notification, and a system
-- status_logs row ("SLA breach: resolution deadline elapsed.") was
-- written with new_status = the report's own status. For a rejected
-- report that row is newer than the real rejection, so the resident's
-- Appeal sheet showed it as the denial reason and date.
--
-- The body is 0002's, with the two terminal statuses added to the
-- exclusion list. status_logs rows already written stay: the table is
-- append-only by design (0015), and the resident app now skips SLA rows
-- when it looks up the denial reason.

create or replace function public.sweep_overdue_reports()
returns void language plpgsql security definer set search_path = public as $$
begin
  with breached as (
    update public.reports
       set escalated_at = now(),
           escalation_level = least(escalation_level + 1, 3)
     where due_at < now()
       and status not in ('resolved', 'closed', 'archived',
                          'rejected', 'cancelled')
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
end $$;
