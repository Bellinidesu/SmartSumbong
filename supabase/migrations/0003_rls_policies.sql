-- =============================================================
-- SmartSumbong — 0003 Row Level Security
-- Residents see their own. Tanod see what they are dispatched to.
-- Admin sees everything. Nobody deletes.
-- =============================================================

alter table public.users          enable row level security;
alter table public.reports        enable row level security;
alter table public.report_media   enable row level security;
alter table public.dispatches     enable row level security;
alter table public.dispatch_media enable row level security;
alter table public.status_logs    enable row level security;
alter table public.feedback       enable row level security;
alter table public.attendance     enable row level security;
alter table public.notifications  enable row level security;
alter table public.sla_policies   enable row level security;
alter table public.sla_extensions enable row level security;

-- Helper: role of the caller. SECURITY DEFINER avoids recursive
-- policy evaluation when a users policy needs to read users.
create or replace function public.my_role()
returns user_role language sql stable security definer set search_path = public as $$
  select role from public.users where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'admin', false)
$$;

-- ---------- users --------------------------------------------
create policy users_self_read on public.users
  for select using (id = auth.uid() or public.is_admin());

-- RLS gates ROWS, not COLUMNS. This policy alone let a resident run
-- `update public.users set role='admin' where id = auth.uid()` and succeed.
-- The trigger below is what actually protects the privileged columns.
create policy users_self_update on public.users
  for update using (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.guard_privileged_user_fields()
returns trigger language plpgsql as $$
begin
  -- auth.uid() is null only for service_role / backend contexts, which
  -- bypass RLS anyway; an unauthenticated client never reaches this row.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.role                   is distinct from old.role
     or new.verification_status is distinct from old.verification_status
     or new.is_suspended        is distinct from old.is_suspended
     or new.verified_by         is distinct from old.verified_by
     or new.verified_at         is distinct from old.verified_at
     or new.rejection_reason    is distinct from old.rejection_reason then
    raise exception
      'Only an administrator may change account role, verification, or suspension state';
  end if;
  return new;
end $$;

create trigger users_guard_privileged
  before update on public.users
  for each row execute function public.guard_privileged_user_fields();

create policy users_admin_all on public.users
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------- reports ------------------------------------------
create policy reports_resident_read on public.reports
  for select using (
    deleted_at is null and (
      resident_id = auth.uid()
      or public.is_admin()
      or exists (select 1 from public.dispatches d
                  where d.report_id = reports.id and d.tanod_id = auth.uid())
    )
  );

-- Only verified, unsuspended residents may file.
create policy reports_resident_insert on public.reports
  for insert with check (
    resident_id = auth.uid()
    and exists (select 1 from public.users u
                 where u.id = auth.uid()
                   and u.verification_status = 'verified'
                   and not u.is_suspended)
  );

create policy reports_admin_update on public.reports
  for update using (public.is_admin()) with check (public.is_admin());

-- ---------- report_media -------------------------------------
create policy report_media_read on public.report_media
  for select using (
    exists (select 1 from public.reports r
             where r.id = report_media.report_id
               and (r.resident_id = auth.uid()
                    or public.is_admin()
                    or exists (select 1 from public.dispatches d
                                where d.report_id = r.id and d.tanod_id = auth.uid())))
  );

create policy report_media_insert on public.report_media
  for insert with check (
    exists (select 1 from public.reports r
             where r.id = report_media.report_id and r.resident_id = auth.uid())
  );

-- ---------- dispatches ---------------------------------------
create policy dispatches_read on public.dispatches
  for select using (tanod_id = auth.uid() or public.is_admin());

create policy dispatches_admin_write on public.dispatches
  for all using (public.is_admin()) with check (public.is_admin());
-- Tanod act on dispatches through accept_dispatch() / reroute_dispatch()
-- / submit_field_report(), never by direct UPDATE.

-- ---------- dispatch_media -----------------------------------
create policy dispatch_media_read on public.dispatch_media
  for select using (
    exists (select 1 from public.dispatches d
             where d.id = dispatch_media.dispatch_id
               and (d.tanod_id = auth.uid() or public.is_admin()))
  );

create policy dispatch_media_insert on public.dispatch_media
  for insert with check (
    exists (select 1 from public.dispatches d
             where d.id = dispatch_media.dispatch_id and d.tanod_id = auth.uid())
  );

-- ---------- status_logs (append-only, never updated) ---------
create policy status_logs_read on public.status_logs
  for select using (
    public.is_admin()
    or exists (select 1 from public.reports r
                where r.id = status_logs.report_id and r.resident_id = auth.uid())
    or exists (select 1 from public.dispatches d
                where d.report_id = status_logs.report_id and d.tanod_id = auth.uid())
  );

-- `auth.uid() is not null` let any resident forge trail entries, including
-- with is_system = true. The transition functions are SECURITY DEFINER and
-- run as the table owner, so they bypass this policy and keep working; the
-- only direct writer left is an admin writing under their own id.
create policy status_logs_insert on public.status_logs
  for insert with check (
    public.is_admin() and changed_by = auth.uid() and is_system = false
  );

-- ---------- feedback -----------------------------------------
create policy feedback_read on public.feedback
  for select using (resident_id = auth.uid() or public.is_admin());

-- Feedback only once the complaint is actually finished.
create policy feedback_insert on public.feedback
  for insert with check (
    resident_id = auth.uid()
    and exists (select 1 from public.reports r
                 where r.id = feedback.report_id
                   and r.resident_id = auth.uid()
                   and r.status in ('resolved', 'closed'))
  );

-- ---------- attendance ---------------------------------------
create policy attendance_read on public.attendance
  for select using (tanod_id = auth.uid() or public.is_admin());

create policy attendance_insert on public.attendance
  for insert with check (tanod_id = auth.uid());

-- ---------- notifications ------------------------------------
create policy notifications_read on public.notifications
  for select using (user_id = auth.uid());

create policy notifications_update on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- sla_policies / extensions ------------------------
create policy sla_policies_read on public.sla_policies
  for select using (auth.uid() is not null);

create policy sla_policies_admin on public.sla_policies
  for all using (public.is_admin()) with check (public.is_admin());

create policy sla_extensions_read on public.sla_extensions
  for select using (public.is_admin());

create policy sla_extensions_admin on public.sla_extensions
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------- function execution grants ------------------------
-- SECURITY DEFINER functions are granted to PUBLIC by default. The
-- transition functions carry their own caller checks, but anon has no
-- business calling them, and the cron sweeps are not a client surface.

revoke execute on function
  public.accept_dispatch(uuid),
  public.reroute_dispatch(uuid, text, uuid),
  public.submit_field_report(uuid, text),
  public.reopen_report(uuid, text)
from public, anon;

grant execute on function
  public.accept_dispatch(uuid),
  public.reroute_dispatch(uuid, text, uuid),
  public.submit_field_report(uuid, text),
  public.reopen_report(uuid, text)
to authenticated;

revoke execute on function
  public.sweep_overdue_reports(),
  public.sweep_unaccepted_dispatches(),
  public.sweep_overdue_verifications()
from public, anon, authenticated;
