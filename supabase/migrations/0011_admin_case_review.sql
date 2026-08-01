-- =============================================================
-- SmartSumbong — 0011 Admin case review
--
-- Validate Report and its denial path are use cases with no
-- implementation. The portal could almost do them with a plain UPDATE:
-- reports_admin_update lets an admin change status, and
-- status_logs_insert lets them write the trail entry under their own
-- id. What it cannot do is tell the resident. notifications has a read
-- policy and an update policy and no insert policy at all, deliberately
-- — nobody writes their own notifications. So the resident would never
-- learn their complaint was accepted or refused, which is the whole
-- point of Track Complaint Status.
--
-- Hence a definer function, matching every other transition in this
-- schema: one call, one transaction, status + trail + notification
-- together or not at all.
--
-- DECISION FOR THE BARANGAY: validating does NOT dispatch anyone. The
-- report moves to 'validated' and waits for the admin to choose a
-- tanod, because that is what the agreed design shows — Case review
-- leads to Case Assign, with a roster and an Assign button per person.
-- Automatic proximity routing still happens, but only at filing time
-- and only for the categories flagged auto_dispatch_on_file. If the
-- barangay would rather every validated complaint go straight to the
-- nearest available tanod, that is one line here and a screen removed
-- from the design.
-- =============================================================

set search_path = public, extensions;

create or replace function public.review_report(
  p_report   uuid,
  p_decision text,                    -- 'validate' | 'reject'
  p_remark   text default null)
returns report_status
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_new    report_status;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may review a complaint';
  end if;

  if p_decision not in ('validate', 'reject') then
    raise exception 'Unknown decision: %', p_decision;
  end if;

  select * into v_report
    from public.reports
   where id = p_report and deleted_at is null
     for update;

  if not found then
    raise exception 'No such report';
  end if;

  -- Reviewing is a one-time gate. A complaint already accepted, refused
  -- or out with a tanod is not sitting in the queue any more, and the
  -- second admin to open the same tab should be told so rather than
  -- quietly overwriting the first one's decision.
  if v_report.status <> 'pending_review' then
    raise exception 'This complaint has already been reviewed (current status: %)',
      replace(v_report.status::text, '_', ' ');
  end if;

  -- A refusal the resident cannot understand is worse than no refusal.
  if p_decision = 'reject' and v_remark is null then
    raise exception 'A reason is required when denying a complaint';
  end if;

  v_new := case p_decision when 'validate' then 'validated' else 'rejected' end::report_status;

  update public.reports
     set status = v_new
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_new,
          coalesce(v_remark,
                   'Complaint accepted for action by the barangay admin.'));

  -- The account binding survives an anonymous filing (Submit Complaint
  -- Report, alternative flow A1) — the name is hidden from public logs,
  -- not from the notification the filer is entitled to.
  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case p_decision
            when 'validate' then
              format('%s has been accepted and is now with the barangay.', v_report.tracking_id)
            else
              format('%s was not accepted. Reason: %s', v_report.tracking_id, v_remark)
          end);

  return v_new;
end $$;

revoke execute on function public.review_report(uuid, text, text) from public, anon;
grant  execute on function public.review_report(uuid, text, text) to authenticated;

comment on function public.review_report(uuid, text, text) is
  'Validate Report / deny path. Admin only, pending_review only. Moves status, writes the trail entry and notifies the resident in one transaction.';

-- ---------- resolution target --------------------------------
-- due_at is set on filing from sla_policies.resolution_hours. The
-- agreed design puts a "Target date resolution" field on the assign
-- screen, so the admin can move that date for a specific complaint —
-- a flooded street after a typhoon is not a 48-hour job because the
-- policy row says 48.
--
-- This is not the SLA extension use case, which is a tanod asking for
-- more time and an admin granting it against sla_extensions. This is
-- the admin setting the clock at the moment of dispatch. Both write to
-- due_at; only this one is silent to the tanod, because nothing has
-- been dispatched yet when it is used.

create or replace function public.set_resolution_target(
  p_report uuid,
  p_due    timestamptz)
returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
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

  update public.reports set due_at = p_due where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_report.status,
          case when v_report.due_at is null
            then format('Resolution target set to %s',
                        to_char(p_due at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM'))
            else format('Resolution target moved from %s to %s',
                        to_char(v_report.due_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM'),
                        to_char(p_due       at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM'))
          end);

  return p_due;
end $$;

revoke execute on function public.set_resolution_target(uuid, timestamptz) from public, anon;
grant  execute on function public.set_resolution_target(uuid, timestamptz) to authenticated;

comment on function public.set_resolution_target(uuid, timestamptz) is
  'Admin override of reports.due_at for one complaint, logged. Not the SLA extension flow.';

-- ---------- the roster the assign screen actually shows -------
-- assignable_tanods (0009) answers "who may take this", which is the
-- right answer for the dropdown but the wrong answer for the screen:
-- the design lists every tanod with ONLINE / OFFLINE beside the name,
-- so the admin can see that nobody is on duty rather than staring at
-- an empty panel and assuming the page broke.
--
-- Everyone is listed. Only the available are assignable, and the
-- reason each unavailable one is unavailable comes back with them.

create or replace function public.tanod_roster(p_report uuid)
returns table (
  tanod_id       uuid,
  full_name      text,
  duty_status    duty_state,
  assignable     boolean,
  unavailable_why text,
  metres         double precision,
  location_fresh boolean)
language sql stable set search_path = public, extensions as $$
  select u.id,
         u.full_name,
         u.duty_status,
         u.is_dispatchable and b.report_id is null,
         case
           when b.report_id is not null       then 'On another incident'
           when u.is_suspended                then 'Suspended'
           when u.verification_status <> 'verified' then 'Not yet verified'
           when coalesce(u.duty_status, 'offline') <> 'on_duty'
             then initcap(replace(coalesce(u.duty_status, 'offline')::text, '_', ' '))
           else null
         end,
         st_distance(u.last_geom, r.geom),
         public.location_is_fresh(u.last_location_at)
    from public.users u
    cross join public.reports r
    left join lateral (
      select d.report_id from public.dispatches d
       where d.tanod_id = u.id and d.state in ('assigned', 'accepted')
       limit 1) b on true
   where r.id = p_report
     and u.role = 'tanod'
   order by (u.is_dispatchable and b.report_id is null) desc,
            st_distance(u.last_geom, r.geom) nulls last,
            u.full_name
$$;

revoke execute on function public.tanod_roster(uuid) from public, anon;
grant  execute on function public.tanod_roster(uuid) to authenticated;

comment on function public.tanod_roster(uuid) is
  'Every tanod with availability and distance, for the assign screen. Available first, then nearest. assignable_tanods remains the authoritative "who may take this".';
