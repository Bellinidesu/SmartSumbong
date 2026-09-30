-- 0070_manual_dispatch_admin_reroute.sql
--
-- The barangay's rule (Rose, branch C): every dispatch is the admin's
-- call. A complaint no longer goes to the nearest tanod on its own when
-- it is filed; the admin reviews it and assigns someone (case.php,
-- admin_dispatch()).
--
-- Rerouting is both. The system keeps doing what it already does when
-- a dispatch falls through — a tanod sends it back to the queue, the
-- acceptance window runs out, a tanod retires — and offers it to the
-- next nearest tanod (redispatch_report(), 0010). What is new is the
-- admin's side: taking a live dispatch off one tanod and giving it to
-- another, or back to the system to find the nearest.

set search_path = public, extensions;

-- ---------- no dispatch at filing -------------------------------------
-- 0010's trigger (a constraint trigger since 0017) sent the categories
-- flagged auto_dispatch_on_file straight to proximity routing. The
-- flag is cleared and the trigger dropped; the column stays so nothing
-- that reads it breaks.

drop trigger if exists reports_dispatch_on_file on public.reports;

update public.sla_policies set auto_dispatch_on_file = false
 where auto_dispatch_on_file;

-- Complaints still waiting from a filing-time attempt that found no one
-- (awaiting_unit_since set, never re-dispatched) would otherwise be
-- picked up by sweep_awaiting_units() every two minutes. They go to the
-- admin instead. A reroute that found no one (dispatch_attempts > 0) is
-- the system's to keep trying.
update public.reports set awaiting_unit_since = null
 where awaiting_unit_since is not null and dispatch_attempts = 0;

comment on column public.sla_policies.auto_dispatch_on_file is
  'Unused since 0070: every dispatch is assigned by an admin. Kept so '
  'older readers do not break.';

-- ---------- admin_reroute_dispatch() ----------------------------------
-- An admin moves a live (assigned or accepted) dispatch. With p_to, to
-- that tanod, through admin_dispatch() and its checks; without, back to
-- the system, which offers it to the nearest available tanod. Either
-- way the tanod it is taken from is told, and the reason is on the
-- trail.

create or replace function public.admin_reroute_dispatch(
  p_dispatch uuid, p_reason text, p_to uuid default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_d      public.dispatches%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_tick   text;
  v_next   uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reroute a dispatch';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to reroute a dispatch';
  end if;

  select * into v_d from public.dispatches
   where id = p_dispatch and state in ('assigned', 'accepted')
   for update;
  if not found then
    raise exception 'That dispatch is no longer active';
  end if;
  if p_to is not null and p_to = v_d.tanod_id then
    raise exception 'That tanod already has this dispatch';
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = 'By the barangay: ' || v_reason, rerouted_to = p_to
   where id = p_dispatch;

  select tracking_id into v_tick from public.reports where id = v_d.report_id;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_d.report_id, auth.uid(), 'assigned', 'assigned',
          'Rerouted by the barangay: ' || v_reason);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_d.tanod_id, v_d.report_id, 'reroute',
          format('The barangay moved %s to another tanod: %s', v_tick, v_reason));

  if p_to is not null then
    -- admin_dispatch checks the new tanod (on duty, not busy), sets the
    -- report to assigned, and notifies them and the resident. Any
    -- refusal there rolls this whole call back.
    v_next := public.admin_dispatch(v_d.report_id, p_to,
                                    'Rerouted by the barangay: ' || v_reason);
  else
    v_next := public.redispatch_report(v_d.report_id,
                                       'rerouted by the barangay: ' || v_reason);
  end if;

  return v_next;
end $$;

revoke execute on function public.admin_reroute_dispatch(uuid, text, uuid) from public, anon;
grant execute on function public.admin_reroute_dispatch(uuid, text, uuid) to authenticated;

comment on function public.admin_reroute_dispatch(uuid, text, uuid) is
  'An admin moves a live dispatch to another tanod (p_to) or back to the '
  'system''s nearest-tanod routing (p_to null). Reason required. 0070.';
