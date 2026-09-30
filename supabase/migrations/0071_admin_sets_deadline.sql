-- 0071_admin_sets_deadline.sql
--
-- Rose (27 Sep 2026): when a complaint comes in, the admin assigns the
-- tanod, the deadline and the instructions — the system should not hand
-- any of them out on its own — and the admin should set the complainant's
-- expectations about the timeline.
--
-- 0070 already stopped the system dispatching at filing. This does the
-- deadline:
--
--   * No resolution deadline is computed at filing any more (0001's
--     reports_deadline trigger), nor on appeal (0057) or reopen (0002).
--     A complaint has no due date until the admin gives it one.
--   * admin_dispatch() refuses to send a tanod without a target date and
--     without instructions.
--   * set_resolution_target() now tells the resident the date, in words
--     meant for them, both as a notification and on their timeline.
--
-- sla_policies.resolution_hours stays: the portal shows it as guidance
-- next to the date field, and the dashboard's efficiency figures still
-- read it. Complaints already carrying a policy date keep it.

set search_path = public, extensions;

-- ---------- no deadline at filing -------------------------------------

drop trigger if exists reports_deadline on public.reports;

comment on function public.set_report_deadline() is
  'Unused since 0071: the admin sets each complaint''s target date '
  '(set_resolution_target) before dispatching.';

-- ---------- appeal and reopen: no automatic date ----------------------

create or replace function public.appeal_report(
  p_report uuid,
  p_remark text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
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

  -- 0071: no fresh policy window; the admin sets the date when assigning.
  update public.reports
     set status      = 'validated',
         appealed_at = now(),
         due_at      = null
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
  'Grants a resident appeal: rejected back to validated, marks appealed_at, '
  'clears the target date for the admin to set again (0071), logs and '
  'notifies the resident. Admin only.';

create or replace function public.reopen_report(p_report uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_old report_status;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reopen a complaint';
  end if;

  select status into v_old from public.reports where id = p_report;

  -- 0071: the old 24-hour window is gone; the admin sets a new date
  -- when assigning again.
  update public.reports
     set status = 'validated',
         reopened_count = reopened_count + 1,
         resolved_at = null,
         due_at = null
   where id = p_report and status in ('resolved', 'closed');

  if not found then
    raise exception 'Report is not in a reopenable state';
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_old, 'validated', 'Reopened: ' || p_reason);
end $$;

-- ---------- the target date, told to the resident ---------------------

create or replace function public.set_resolution_target(
  p_report uuid,
  p_due    timestamptz)
returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_when   text;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may change a resolution target';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;

  if not found then
    raise exception 'No such report';
  end if;

  if p_due is null then
    raise exception 'A target date is required';
  end if;

  if p_due <= now() then
    raise exception 'The target date must be in the future';
  end if;

  if v_report.status in ('resolved', 'closed', 'archived', 'rejected') then
    raise exception 'This complaint is already finished; its target cannot be moved';
  end if;

  -- Same date, nothing to say.
  if v_report.due_at is not distinct from p_due then
    return p_due;
  end if;

  update public.reports set due_at = p_due where id = p_report;

  v_when := to_char(p_due at time zone 'Asia/Manila', 'FMMonth FMDD, YYYY, FMHH12:MI AM');

  -- Worded for the complainant: this line is on their timeline.
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_report.status,
          case when v_report.due_at is null
            then format('Expected to be resolved by %s.', v_when)
            else format('Expected resolution moved to %s.', v_when)
          end);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case when v_report.due_at is null
            then format('The barangay expects to resolve %s by %s.', v_report.tracking_id, v_when)
            else format('The expected resolution of %s is now %s.', v_report.tracking_id, v_when)
          end);

  return p_due;
end $$;

comment on function public.set_resolution_target(uuid, timestamptz) is
  'The admin sets or moves a complaint''s target date (0071: the only way '
  'it gets one). Logged on the timeline and told to the resident.';

-- ---------- no dispatch without a date and instructions ---------------
-- 0034's admin_dispatch, with two checks added before anything is
-- written. admin_reroute_dispatch (0070) passes its own instructions and
-- the complaint already has its date by then.

create or replace function public.admin_dispatch(
  p_report uuid, p_tanod uuid, p_instructions text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    public.users%rowtype;
  v_busy     text;
  v_dispatch uuid;
  v_metres   double precision;
  v_note     text := nullif(trim(coalesce(p_instructions, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may assign a dispatch manually';
  end if;

  select * into v_report from public.reports where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;

  -- Set, not necessarily future: a reroute of an overdue complaint comes
  -- through here too. The assign form itself only takes a future date.
  if v_report.due_at is null then
    raise exception 'Set a target resolution date before dispatching';
  end if;

  if v_note is null then
    raise exception 'Write instructions for the tanod before dispatching';
  end if;

  select * into v_tanod from public.users where id = p_tanod;
  if not found or v_tanod.role <> 'tanod' then
    raise exception 'That account is not a tanod';
  end if;

  if not v_tanod.is_dispatchable then
    raise exception '% is not available for dispatch (duty status: %)',
      v_tanod.full_name, coalesce(v_tanod.duty_status::text, 'not set');
  end if;

  select r.subject into v_busy
    from public.dispatches d
    join public.reports r on r.id = d.report_id
   where d.tanod_id = p_tanod and d.state in ('assigned', 'accepted')
   limit 1;

  if v_busy is not null then
    raise exception
      '% is already handling an active incident. Choose another available tanod.',
      v_tanod.full_name;
  end if;

  select st_distance(v_tanod.last_geom, v_report.geom) into v_metres;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, p_tanod, auth.uid(), v_note)
  returning id into v_dispatch;

  update public.reports
     set status = 'assigned', awaiting_unit_since = null
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'assigned',
          case when v_metres is null
            then format('Manually assigned to %s by admin', v_tanod.full_name)
            else format('Manually assigned to %s by admin (%s m from the incident)',
                        v_tanod.full_name, round(v_metres))
          end);

  insert into public.notifications (user_id, report_id, kind, message)
  values (p_tanod, p_report, 'assignment',
          format('Assigned by the barangay admin: %s', v_report.subject));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;
