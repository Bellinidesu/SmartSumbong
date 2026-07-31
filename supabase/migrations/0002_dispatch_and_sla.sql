-- =============================================================
-- SmartSumbong — 0002 Dispatch, accept/reroute, escalation, SLA
--
-- Backs these use cases:
--   Assign Tanod                (Complaint Management System UC)
--   Receive Dispatch Ticket     (accept / reroute / justification)
--   View Ticket Details         (admin instructions, SLA deadline)
--   Upload Report Status        (field report + photo proof)
--   Manage SLA Deadline Extension
-- =============================================================

create type dispatch_state as enum (
  'assigned',    -- admin assigned, tanod has not responded
  'accepted',    -- tanod accepted; report moves to in_progress
  'rerouted',    -- tanod declined with justification
  'resolved',    -- field report submitted
  'expired'      -- accept window elapsed with no response
);

-- ---------- dispatches ---------------------------------------

create table public.dispatches (
  id                  uuid primary key default gen_random_uuid(),
  report_id           uuid not null references public.reports (id) on delete cascade,
  tanod_id            uuid not null references public.users (id) on delete restrict,

  assigned_by         uuid not null references public.users (id),
  assigned_at         timestamptz not null default now(),
  admin_instructions  text check (char_length(admin_instructions) <= 500),

  state               dispatch_state not null default 'assigned',

  -- Acceptance clock. The Receive Dispatch Ticket exception requires
  -- the Admin to be alerted when a tanod does not respond in time.
  accept_due_at       timestamptz,
  accepted_at         timestamptz,
  is_primary          boolean not null default false,

  -- Reroute (mandatory justification, target is another tanod or the queue)
  rerouted_at         timestamptz,
  reroute_reason      text check (char_length(reroute_reason) <= 200),
  rerouted_to         uuid references public.users (id),   -- null = admin queue

  -- Field resolution
  field_report_text   text check (char_length(field_report_text) <= 300),
  resolved_at         timestamptz,

  created_at          timestamptz not null default now(),

  -- A reroute is meaningless without its reason.
  constraint reroute_needs_reason
    check (rerouted_at is null or reroute_reason is not null)
);

-- Only one LIVE dispatch per tanod per report. A plain unique constraint on
-- (report_id, tanod_id, assigned_at) enforced nothing, since assigned_at
-- makes every row distinct by construction. Historical rerouted/expired
-- rows must stay insertable, so this is a partial index on live states only.
create unique index dispatches_one_live_per_tanod
  on public.dispatches (report_id, tanod_id)
  where state in ('assigned', 'accepted');

create index dispatches_report_idx  on public.dispatches (report_id);
create index dispatches_tanod_idx   on public.dispatches (tanod_id, state);
create index dispatches_accept_idx  on public.dispatches (accept_due_at)
  where state = 'assigned';

-- Acceptance deadline from the category's policy.
create or replace function public.set_accept_deadline()
returns trigger language plpgsql as $$
declare mins integer;
begin
  if new.accept_due_at is null then
    select p.accept_minutes into mins
      from public.sla_policies p
      join public.reports r on r.category = p.category
     where r.id = new.report_id;
    if mins is not null then
      new.accept_due_at := new.assigned_at + make_interval(mins => mins);
    end if;
  end if;
  return new;
end $$;

create trigger dispatches_accept_deadline
  before insert on public.dispatches
  for each row execute function public.set_accept_deadline();

-- ---------- dispatch_media -----------------------------------
-- Tanod photo proof (UC: Upload Report Status to Admin).

create table public.dispatch_media (
  id           uuid primary key default gen_random_uuid(),
  dispatch_id  uuid not null references public.dispatches (id) on delete cascade,
  media_url    text not null,
  mime_type    text not null check (mime_type in ('image/jpeg', 'image/png')),
  bytes        integer not null check (bytes > 0 and bytes <= 10 * 1024 * 1024),
  uploaded_at  timestamptz not null default now()
);

create index dispatch_media_idx on public.dispatch_media (dispatch_id);

-- ---------- sla_extensions -----------------------------------
-- "Manage SLA Deadline Extension" needs an auditable record, or an
-- extension is indistinguishable from quietly moving the goalposts.

create table public.sla_extensions (
  id           uuid primary key default gen_random_uuid(),
  report_id    uuid not null references public.reports (id) on delete cascade,
  requested_by uuid not null references public.users (id),
  approved_by  uuid references public.users (id),
  previous_due timestamptz not null,
  new_due      timestamptz not null,
  reason       text not null check (char_length(reason) between 5 and 300),
  approved_at  timestamptz,
  created_at   timestamptz not null default now(),
  constraint extension_moves_forward check (new_due > previous_due)
);

create index sla_extensions_report_idx on public.sla_extensions (report_id);

-- =============================================================
-- Transitions
-- =============================================================

-- Accept: tanod becomes the primary assignee, report moves to in_progress.
create or replace function public.accept_dispatch(p_dispatch uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_report uuid; v_old report_status;
begin
  update public.dispatches
     set state = 'accepted', accepted_at = now(), is_primary = true
   where id = p_dispatch
     and tanod_id = auth.uid()
     and state = 'assigned'
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or already actioned';
  end if;

  select status into v_old from public.reports where id = v_report;

  update public.reports set status = 'in_progress' where id = v_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status)
  values (v_report, auth.uid(), v_old, 'in_progress');
end $$;

-- Reroute: justification is mandatory; Admin is alerted.
create or replace function public.reroute_dispatch(
  p_dispatch uuid, p_reason text, p_to uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_report uuid;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A justification is required to reroute a dispatch';
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = p_reason, rerouted_to = p_to
   where id = p_dispatch
     and tanod_id = auth.uid()
     and state = 'assigned'
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or already actioned';
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_report, auth.uid(), 'assigned', 'assigned', 'Rerouted: ' || p_reason);

  -- Hand straight to the named tanod, or back to the admin queue.
  if p_to is not null then
    insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
    values (v_report, p_to, auth.uid(), 'Rerouted from a previous tanod.');
  else
    update public.reports set status = 'validated' where id = v_report;
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select id, v_report, 'reroute', 'A dispatch was rerouted and needs reassignment.'
    from public.users where role = 'admin';
end $$;

-- Field resolution submitted by the tanod.
create or replace function public.submit_field_report(
  p_dispatch uuid, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v_report uuid; v_old report_status;
begin
  update public.dispatches
     set state = 'resolved', field_report_text = p_text, resolved_at = now()
   where id = p_dispatch and tanod_id = auth.uid() and state = 'accepted'
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or not in an accepted state';
  end if;

  select status into v_old from public.reports where id = v_report;
  update public.reports set status = 'resolved', resolved_at = now() where id = v_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_report, auth.uid(), v_old, 'resolved', p_text);

  insert into public.notifications (user_id, report_id, kind, message)
  select resident_id, v_report, 'status_change', 'Your complaint has been marked resolved.'
    from public.reports where id = v_report;
end $$;

-- Reopening a closed case (Escalated Report — Reopened Cases).
-- SECURITY DEFINER means this runs as the owner and bypasses RLS entirely,
-- so the authorization check has to live in the body. Without it any
-- authenticated resident could reopen any report in the barangay.
create or replace function public.reopen_report(p_report uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_old report_status;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may reopen a complaint';
  end if;

  select status into v_old from public.reports where id = p_report;

  update public.reports
     set status = 'validated',
         reopened_count = reopened_count + 1,
         resolved_at = null,
         due_at = now() + interval '24 hours'
   where id = p_report and status in ('resolved', 'closed');

  if not found then
    raise exception 'Report is not in a reopenable state';
  end if;

  -- Log the status it actually came from, not a hardcoded 'resolved'.
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_old, 'validated', 'Reopened: ' || p_reason);
end $$;

-- =============================================================
-- Scheduled SLA sweeps (STA unit 6b)
-- Requires pg_cron enabled: Dashboard → Database → Extensions.
-- =============================================================

-- 6b — resolution deadline breached.
create or replace function public.sweep_overdue_reports()
returns void language plpgsql security definer set search_path = public as $$
begin
  with breached as (
    update public.reports
       set escalated_at = now(),
           escalation_level = least(escalation_level + 1, 3)
     where due_at < now()
       and status not in ('resolved', 'closed', 'archived')
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

-- Acceptance window elapsed with no tanod response.
create or replace function public.sweep_unaccepted_dispatches()
returns void language plpgsql security definer set search_path = public as $$
begin
  with expired as (
    update public.dispatches
       set state = 'expired'
     where state = 'assigned' and accept_due_at < now()
    returning id, report_id
  )
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, e.report_id, 'sla_warning',
         'A tanod did not respond to a dispatch within the acceptance window.'
    from expired e cross join public.users u
   where u.role = 'admin';
end $$;

-- Verification queue past the 2-hour maximum.
create or replace function public.sweep_overdue_verifications()
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, kind, message)
  select a.id, 'sla_warning',
         'Account verification for ' || u.full_name || ' has passed the 2-hour limit.'
    from public.users u cross join public.users a
   where u.verification_status = 'pending'
     and u.verification_due_at < now()
     and a.role = 'admin';
end $$;

-- Schedule (safe to re-run).
select cron.schedule('sweep-overdue-reports',       '*/15 * * * *',
                     $$select public.sweep_overdue_reports()$$);
select cron.schedule('sweep-unaccepted-dispatches', '*/5  * * * *',
                     $$select public.sweep_unaccepted_dispatches()$$);
select cron.schedule('sweep-overdue-verifications', '*/10 * * * *',
                     $$select public.sweep_overdue_verifications()$$);
