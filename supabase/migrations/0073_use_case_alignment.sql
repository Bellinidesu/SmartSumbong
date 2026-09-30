-- 0073_use_case_alignment.sql
--
-- The system follows the project's use cases (30 Sep 2026). What they
-- ask for that the database did not yet do:
--
--   Approve Complaint Resolution — a tanod's resolution waits for the
--     admin. submit_field_report() finishes the tanod's dispatch but
--     leaves the complaint In Progress with resolution_submitted_at set;
--     approve_resolution() makes it Resolved/Completed and tells the
--     resident; reject_resolution() gives it back to the tanod.
--   Update Resolution Status — admin_set_status(): In Progress, Offline
--     Investigation or Resolved, logged, the resident told.
--   Manage User Account (3.2) — admin_update_user(): the admin corrects
--     a resident's or tanod's name and email.
--   Manage Escalation Request — the tanod on a case asks to escalate it
--     (request_escalation); the admin approves by naming the office
--     (approve_escalation, which escalates through refer_report) or
--     denies with a reason (deny_escalation).
--   Monitor Real-Time Map (resident) — the admin publishes chosen
--     incidents (set_report_public); residents see them through
--     public_incidents(): category, status and place only.
--
-- Wording: an approved escalation IS the referral to an outside office
-- (0072), so the trail and the resident now read "Escalated to …".

set search_path = public, extensions;

-- ---------- columns ----------------------------------------------------

alter table public.reports
  add column if not exists resolution_submitted_at timestamptz,
  add column if not exists resolution_returned_reason text,
  add column if not exists is_public boolean not null default false;

-- ---------- escalation requests (from the tanod) -----------------------

create table if not exists public.escalation_requests (
  id              uuid primary key default gen_random_uuid(),
  report_id       uuid not null references public.reports (id) on delete cascade,
  dispatch_id     uuid references public.dispatches (id) on delete set null,
  requested_by    uuid not null references public.users (id),
  reason          text not null check (char_length(trim(reason)) between 1 and 1000),
  suggested_office text,
  status          text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  decided_by      uuid references public.users (id),
  decided_at      timestamptz,
  decided_office  text,
  decision_note   text,
  created_at      timestamptz not null default now()
);

create unique index if not exists escalation_requests_one_open
  on public.escalation_requests (report_id) where status = 'pending';
create index if not exists escalation_requests_status_idx
  on public.escalation_requests (status, created_at desc);

alter table public.escalation_requests enable row level security;

drop policy if exists escalation_requests_read on public.escalation_requests;
create policy escalation_requests_read on public.escalation_requests
  for select using (public.is_admin() or requested_by = auth.uid());

-- ---------- escalation: the referral, worded as the use cases do -------

create or replace function public.refer_report(
  p_report uuid, p_agency text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_agency text := nullif(trim(coalesce(p_agency, '')), '');
  v_note   text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may escalate a complaint';
  end if;
  if v_agency is null then
    raise exception 'Choose the office the complaint is escalated to';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.referred_to is not null then
    raise exception 'This complaint was already escalated to %', v_report.referred_to;
  end if;
  if v_report.status in ('closed', 'archived', 'rejected', 'cancelled') then
    raise exception 'This complaint is already closed';
  end if;

  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = 'Escalated to ' || v_agency
   where report_id = p_report and state in ('assigned', 'accepted');

  update public.reports
     set status        = 'closed',
         closed_at     = now(),
         referred_to   = v_agency,
         referral_note = v_note,
         referred_at   = now(),
         referred_by   = auth.uid()
   where id = p_report;

  -- Any request still waiting on this complaint is settled by this.
  update public.escalation_requests
     set status = 'approved', decided_by = auth.uid(), decided_at = now(),
         decided_office = v_agency
   where report_id = p_report and status = 'pending';

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'closed',
          'Escalated to ' || v_agency || coalesce(': ' || v_note, '.'));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          format('Your complaint %s has been escalated to the %s, which handles this kind of case.%s',
                 v_report.tracking_id, v_agency,
                 coalesce(' Note from the barangay: ' || v_note, '')));
end $$;

create or replace function public.request_escalation(
  p_dispatch uuid, p_reason text, p_office text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_d      public.dispatches%rowtype;
  v_tick   text;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_id     uuid;
begin
  select * into v_d from public.dispatches
   where id = p_dispatch and tanod_id = auth.uid() and state = 'accepted';
  if not found then
    raise exception 'Dispatch not found, not yours, or not accepted';
  end if;
  if v_reason is null then
    raise exception 'Say why this needs to go beyond the barangay';
  end if;
  if exists (select 1 from public.escalation_requests
              where report_id = v_d.report_id and status = 'pending') then
    raise exception 'An escalation request for this complaint is already waiting';
  end if;

  insert into public.escalation_requests (report_id, dispatch_id, requested_by, reason, suggested_office)
  values (v_d.report_id, p_dispatch, auth.uid(), v_reason, nullif(trim(coalesce(p_office, '')), ''))
  returning id into v_id;

  select tracking_id into v_tick from public.reports where id = v_d.report_id;

  insert into public.dispatch_updates (dispatch_id, author_id, kind, body)
  values (p_dispatch, auth.uid(), 'note', 'Escalation requested: ' || v_reason);

  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, v_d.report_id, 'escalation',
         'Escalation requested for ' || v_tick || ': ' || left(v_reason, 140)
    from public.users u where u.role = 'admin';

  return v_id;
end $$;

create or replace function public.approve_escalation(
  p_request uuid, p_office text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_r public.escalation_requests%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may decide an escalation request';
  end if;
  select * into v_r from public.escalation_requests where id = p_request for update;
  if not found or v_r.status <> 'pending' then
    raise exception 'That request has already been decided';
  end if;

  perform public.refer_report(v_r.report_id, p_office, p_note);

  update public.escalation_requests
     set decision_note = nullif(trim(coalesce(p_note, '')), '')
   where id = p_request;

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_r.requested_by, v_r.report_id, 'status_change',
          'Your escalation request was approved: escalated to the ' || trim(p_office) || '.');
end $$;

create or replace function public.deny_escalation(p_request uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_r      public.escalation_requests%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_tick   text;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may decide an escalation request';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to deny an escalation request';
  end if;
  select * into v_r from public.escalation_requests where id = p_request for update;
  if not found or v_r.status <> 'pending' then
    raise exception 'That request has already been decided';
  end if;

  update public.escalation_requests
     set status = 'denied', decided_by = auth.uid(), decided_at = now(),
         decision_note = v_reason
   where id = p_request;

  select tracking_id into v_tick from public.reports where id = v_r.report_id;

  -- The complaint stays with the barangay, in progress.
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  select v_r.report_id, auth.uid(), r.status, r.status,
         'Escalation request denied: ' || v_reason
    from public.reports r where r.id = v_r.report_id;

  if v_r.dispatch_id is not null then
    insert into public.dispatch_updates (dispatch_id, author_id, kind, body)
    values (v_r.dispatch_id, auth.uid(), 'note', 'Escalation request denied: ' || v_reason);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_r.requested_by, v_r.report_id, 'status_change',
          'Your escalation request for ' || v_tick || ' was denied: ' || left(v_reason, 140));
end $$;

-- ---------- resolution waits for the admin -----------------------------

create or replace function public.submit_field_report(p_dispatch uuid, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v_report uuid; v_status report_status; v_tick text;
begin
  update public.dispatches
     set state = 'resolved', field_report_text = p_text, resolved_at = now()
   where id = p_dispatch and tanod_id = auth.uid() and state = 'accepted'
  returning report_id into v_report;

  if v_report is null then
    raise exception 'Dispatch not found, not yours, or not in an accepted state';
  end if;

  update public.reports
     set resolution_submitted_at = now(), resolution_returned_reason = null
   where id = v_report
  returning status, tracking_id into v_status, v_tick;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (v_report, auth.uid(), v_status, v_status,
          'Resolution report submitted by the tanod, waiting for the barangay''s approval.');

  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, v_report, 'status_change',
         'A tanod submitted the resolution of ' || v_tick || '. Review and approve it.'
    from public.users u where u.role = 'admin';
end $$;

create or replace function public.approve_resolution(p_report uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_d      public.dispatches%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may approve a resolution';
  end if;
  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.resolution_submitted_at is null or v_report.status = 'resolved' then
    raise exception 'There is no resolution waiting for approval';
  end if;

  select * into v_d from public.dispatches
   where report_id = p_report and state = 'resolved'
   order by resolved_at desc nulls last limit 1;

  update public.reports
     set status = 'resolved', resolved_at = now(), resolution_submitted_at = null
   where id = p_report;

  -- The tanod's own words stay the resolution note the resident reads.
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'resolved',
          coalesce(nullif(trim(v_d.field_report_text), ''), 'Resolution approved by the barangay.'));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          'Your complaint ' || v_report.tracking_id || ' has been resolved.');

  if v_d.tanod_id is not null then
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_d.tanod_id, p_report, 'status_change',
            'The barangay approved your resolution of ' || v_report.tracking_id || '.');
  end if;
end $$;

create or replace function public.reject_resolution(p_report uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_d      public.dispatches%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may return a resolution';
  end if;
  if v_reason is null then
    raise exception 'Say what the tanod still needs to do';
  end if;
  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found or v_report.resolution_submitted_at is null then
    raise exception 'There is no resolution waiting for approval';
  end if;

  select * into v_d from public.dispatches
   where report_id = p_report and state = 'resolved'
   order by resolved_at desc nulls last limit 1;

  -- Back to the tanod: their dispatch is open again.
  if v_d.id is not null then
    update public.dispatches set state = 'accepted', resolved_at = null where id = v_d.id;
    insert into public.dispatch_updates (dispatch_id, author_id, kind, body)
    values (v_d.id, auth.uid(), 'note', 'Resolution returned: ' || v_reason);
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_d.tanod_id, p_report, 'status_change',
            'The barangay returned your resolution of ' || v_report.tracking_id || ': ' || left(v_reason, 140));
  end if;

  update public.reports
     set status = 'in_progress', resolution_submitted_at = null,
         resolution_returned_reason = v_reason
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'in_progress',
          'Resolution returned to the tanod: ' || v_reason);
end $$;

-- ---------- the admin sets a status (Update Resolution Status) --------

create or replace function public.admin_set_status(
  p_report uuid, p_status text, p_remark text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_new    report_status;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may change a complaint''s status';
  end if;
  if p_status not in ('in_progress', 'offline_investigation', 'resolved') then
    raise exception 'Choose In Progress, Offline Investigation or Resolved';
  end if;
  v_new := p_status::report_status;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.status in ('closed', 'archived', 'rejected', 'cancelled', 'pending_review') then
    raise exception 'This complaint''s status cannot be changed here';
  end if;
  if v_report.status = v_new then
    raise exception 'The complaint is already %', replace(p_status, '_', ' ');
  end if;

  if v_new = 'resolved' then
    -- Anyone still on it is stood down.
    update public.dispatches
       set state = 'rerouted', rerouted_at = now(), reroute_reason = 'Resolved by the barangay'
     where report_id = p_report and state in ('assigned', 'accepted');
    update public.reports
       set status = 'resolved', resolved_at = now(), resolution_submitted_at = null
     where id = p_report;
  else
    update public.reports set status = v_new where id = p_report;
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_new,
          coalesce(v_remark, case v_new
            when 'in_progress' then 'Status set to In Progress by the barangay.'
            when 'offline_investigation' then 'Status set to Offline Investigation by the barangay.'
            else 'Marked resolved by the barangay.' end));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case v_new
            when 'in_progress' then 'Your complaint ' || v_report.tracking_id || ' is in progress.'
            when 'offline_investigation' then 'Your complaint ' || v_report.tracking_id || ' is under offline investigation by the barangay.'
            else 'Your complaint ' || v_report.tracking_id || ' has been resolved.' end
          || coalesce(' ' || v_remark, ''));
end $$;

-- ---------- the admin corrects a profile (Manage User Account 3.2) -----

create or replace function public.admin_update_user(
  p_user uuid, p_full_name text, p_email text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user  public.users%rowtype;
  v_name  text := nullif(regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g'), '');
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may correct a profile';
  end if;
  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;
  if v_user.role = 'admin' then
    raise exception 'Administrators edit their own profile under Edit Profile';
  end if;
  if v_name is null then
    raise exception 'Enter the full name';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That email address does not look right';
  end if;
  if v_email is not null and exists (select 1 from public.users
                                      where lower(email) = v_email and id <> p_user) then
    raise exception 'Another account already uses that email address';
  end if;

  update public.users
     set full_name = v_name,
         email = coalesce(v_email, email)
   where id = p_user;

  insert into public.notifications (user_id, report_id, kind, message)
  values (p_user, null, 'verification',
          'The barangay corrected your profile details. Check them under Edit Profile.');
end $$;

-- ---------- published incidents (resident map) -------------------------

create or replace function public.set_report_public(p_report uuid, p_public boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may publish an incident';
  end if;
  update public.reports set is_public = coalesce(p_public, false)
   where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;
end $$;

-- What a resident may see of someone else's published complaint: what
-- kind, where, and how far along. No names, words or photos.
create or replace function public.public_incidents()
returns table (id uuid, category complaint_category, status report_status,
               latitude double precision, longitude double precision,
               created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.category, r.status, r.latitude, r.longitude, r.created_at
    from public.reports r
   where r.is_public
     and r.deleted_at is null
     and r.status not in ('rejected', 'cancelled')
     and auth.uid() is not null
   order by r.created_at desc
   limit 500
$$;

-- ---------- grants and live ---------------------------------------------

revoke execute on function public.request_escalation(uuid, text, text) from public, anon;
revoke execute on function public.approve_escalation(uuid, text, text) from public, anon;
revoke execute on function public.deny_escalation(uuid, text) from public, anon;
revoke execute on function public.approve_resolution(uuid) from public, anon;
revoke execute on function public.reject_resolution(uuid, text) from public, anon;
revoke execute on function public.admin_set_status(uuid, text, text) from public, anon;
revoke execute on function public.admin_update_user(uuid, text, text) from public, anon;
revoke execute on function public.set_report_public(uuid, boolean) from public, anon;
revoke execute on function public.public_incidents() from public, anon;
grant execute on function public.request_escalation(uuid, text, text) to authenticated;
grant execute on function public.approve_escalation(uuid, text, text) to authenticated;
grant execute on function public.deny_escalation(uuid, text) to authenticated;
grant execute on function public.approve_resolution(uuid) to authenticated;
grant execute on function public.reject_resolution(uuid, text) to authenticated;
grant execute on function public.admin_set_status(uuid, text, text) to authenticated;
grant execute on function public.admin_update_user(uuid, text, text) to authenticated;
grant execute on function public.set_report_public(uuid, boolean) to authenticated;
grant execute on function public.public_incidents() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'escalation_requests') then
    alter publication supabase_realtime add table public.escalation_requests;
  end if;
end $$;
