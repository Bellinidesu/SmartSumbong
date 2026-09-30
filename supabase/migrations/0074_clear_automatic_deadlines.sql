-- 0074_clear_automatic_deadlines.sql
--
-- Complaints filed before 0071 were given a deadline automatically at
-- filing (the category's policy hours). Under the barangay's rule a
-- complaint has no deadline until the admin sets one when assigning it,
-- so those left unassigned (Pending Review or Validated, no tanod on it,
-- no admin-set date in their trail) were showing "Overdue" and set off a
-- burst of overdue alerts once 0072's sweep ran (30 Sep 2026).
--
-- This clears those automatic dates, and marks the overdue alerts they
-- caused as read. Complaints an admin already dated, or that a tanod is
-- working, keep theirs.

set search_path = public, extensions;

with cleared as (
  update public.reports r
     set due_at = null, overdue_notified_at = null
   where r.deleted_at is null
     and r.due_at is not null
     and r.status in ('pending_review', 'validated')
     and not exists (select 1 from public.dispatches d
                      where d.report_id = r.id and d.state in ('assigned', 'accepted'))
     and not exists (select 1 from public.status_logs l
                      where l.report_id = r.id
                        and (l.remark like 'Expected to be resolved%'
                          or l.remark like 'Expected resolution moved%'
                          or l.remark like 'Resolution target%'))
  returning r.id
)
update public.notifications n
   set is_read = true
  from cleared c
 where n.report_id = c.id
   and n.kind = 'sla_warning'
   and n.message like '% is overdue: its target date has passed.';
