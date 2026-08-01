-- =============================================================
-- SmartSumbong — 0008 A tanod cannot be handed a second live job
--
-- reroute_dispatch inserted a dispatch for the named target without
-- checking what that tanod was already holding. So a tanod midway
-- through an accepted incident could have another ticket pushed onto
-- them by a colleague who simply wanted rid of it.
--
-- Automatic dispatch never did this — nearest_available_tanod excludes
-- anyone holding a live dispatch. Only the manual hand-off could.
--
-- The remedy is to refuse the hand-off, not to give the receiving
-- tanod a way to appeal it afterwards. A tanod on scene should not
-- have to argue with their phone.
-- =============================================================

set search_path = public, extensions;

-- One live dispatch per tanod, full stop. The 0002 index only stopped
-- the same tanod holding the same REPORT twice; this stops them
-- holding two different ones.
create unique index dispatches_one_live_job_per_tanod
  on public.dispatches (tanod_id)
  where state in ('assigned', 'accepted');

create or replace function public.reroute_dispatch(
  p_dispatch uuid, p_reason text, p_to uuid default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report uuid;
  v_busy   text;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A justification is required to reroute a dispatch';
  end if;

  -- Check the target before touching anything, so a refused hand-off
  -- leaves the original dispatch untouched rather than half-moved.
  if p_to is not null then
    select r.subject into v_busy
      from public.dispatches d
      join public.reports r on r.id = d.report_id
     where d.tanod_id = p_to and d.state in ('assigned', 'accepted')
     limit 1;

    if v_busy is not null then
      raise exception
        'That tanod is already handling an active incident. Reroute to the queue instead.';
    end if;

    if not exists (select 1 from public.users
                    where id = p_to and is_dispatchable) then
      raise exception 'That tanod is not on duty and available';
    end if;
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = p_reason, rerouted_to = p_to
   where id = p_dispatch
     and tanod_id = auth.uid()
     and state in ('assigned', 'accepted')
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or already actioned';
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_report, auth.uid(), 'assigned', 'assigned', 'Rerouted: ' || p_reason);

  if p_to is not null then
    insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
    values (v_report, p_to, auth.uid(), 'Rerouted from a previous tanod.');

    insert into public.notifications (user_id, report_id, kind, message)
    values (p_to, v_report, 'reroute', 'A dispatch was rerouted to you.');
  else
    perform public.redispatch_report(v_report, 'rerouted to queue: ' || p_reason);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select id, v_report, 'reroute', 'A dispatch was rerouted.'
    from public.users where role = 'admin';
end $$;
