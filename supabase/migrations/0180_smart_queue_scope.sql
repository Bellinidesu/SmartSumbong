-- 0180: the queue (Next up) lists the cases a person may open, for every rung (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0180".
--
-- 0175 made the staff branch of smart_queue follow admin_sees_report but left a Kagawad on admin_sees_category: the category's
-- committee, whatever happened to the case since. Proved on a copy built from the migrations: the Environment Kagawad forwards
-- an Environment case to Peace and Order; Case Reports no longer shows it to them (0 rows), but their queue still lists it with
-- its subject, and the receiving Peace and Order Kagawad's queue does not list it at all (their category is not its category).
-- The queue is one rule with the case pages: admin_sees_report (a full viewer sees everything, so super admins and the captain
-- are unchanged).

set search_path = public, extensions;

create or replace function public.smart_queue(p_stage text default null, p_limit integer default 50)
returns table (report_id uuid, tracking_id text, subject text, category public.complaint_category, stage text, next_action text,
               waiting_since timestamptz, level text, priority integer, reasons jsonb)
language plpgsql stable security definer set search_path = public, extensions set jit = off as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the queue.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_queue() q
                where (p_stage is null or q.stage = p_stage)
                  and public.admin_sees_report(q.report_id)
                limit greatest(1, least(coalesce(p_limit, 50), 500));
end $$;
