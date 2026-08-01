-- =============================================================
-- SmartSumbong — 0010 Operational settings the barangay owns
--
-- Every timing and threshold decision so far has been a number chosen
-- by the developer and buried in a function body. They were reasonable
-- guesses, but they are operational policy, not engineering: how long
-- a tanod has to accept, how many refusals before a human takes over,
-- how stale a position may be before it stops counting.
--
-- After turnover the barangay owns those decisions. Baked into
-- functions, changing one means a migration and a developer. Here, it
-- means an admin editing a form.
--
-- This also settles the dispatch trigger point without guessing. Some
-- categories should reach a tanod the moment they are filed; others
-- should wait for an admin to look first. Which is which is a barangay
-- judgement, so it lives beside the SLA numbers as a per-category flag.
-- =============================================================

set search_path = public, extensions;

create table public.operational_settings (
  id                        smallint primary key default 1 check (id = 1),

  -- How many times automatic routing may be refused before the report
  -- is handed to an admin. Waiting for a unit does not count.
  max_dispatch_attempts     smallint not null default 3
                            check (max_dispatch_attempts between 1 and 10),

  -- A tanod position older than this is not trusted for "nearest".
  location_freshness_minutes smallint not null default 15
                            check (location_freshness_minutes between 1 and 120),

  -- How long a report may sit with nobody on duty before an admin is
  -- told. This is a staffing signal, not a dispatch one.
  awaiting_alert_hours      smallint not null default 4
                            check (awaiting_alert_hours between 1 and 48),

  updated_at                timestamptz not null default now(),
  updated_by                uuid references public.users (id)
);

insert into public.operational_settings (id) values (1);

comment on table public.operational_settings is
  'Operational policy owned by the barangay, not the developer. Single row.';

-- ---------- per-category dispatch trigger --------------------
-- auto_dispatch_on_file = true  : goes to the nearest tanod immediately
-- auto_dispatch_on_file = false : waits for an admin to validate first
--
-- Defaults below are a starting position for the barangay to correct,
-- not a recommendation. They assume anything touching safety should
-- not wait for an admin to be awake, and anything administrative can.

alter table public.sla_policies
  add column auto_dispatch_on_file boolean not null default false;

-- seed.sql is the source of truth for this column and carries the same
-- values, so a rebuilt database matches a migrated one. This update
-- exists for a database that was already seeded before 0010 ran; on a
-- fresh build it matches zero rows and the seed supplies them.
update public.sla_policies set auto_dispatch_on_file = true
 where category in ('peace_order_nuisance',
                    'public_safety_infrastructure',
                    'traffic_violation');

comment on column public.sla_policies.auto_dispatch_on_file is
  'True: dispatched to the nearest tanod on filing. False: held until an admin validates it. Barangay policy.';

-- ---------- functions read settings instead of literals -------

create or replace function public.location_is_fresh(p_at timestamptz)
returns boolean language sql stable set search_path = public, extensions as $$
  select p_at is not null
     and p_at > now() - make_interval(mins => (
           select location_freshness_minutes from public.operational_settings where id = 1))
$$;

create or replace function public.redispatch_report(p_report uuid, p_why text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_attempts smallint;
  v_max      smallint;
  v_next     uuid;
begin
  select max_dispatch_attempts into v_max from public.operational_settings where id = 1;

  update public.reports
     set dispatch_attempts = dispatch_attempts + 1,
         status = 'validated'
   where id = p_report
  returning dispatch_attempts into v_attempts;

  if v_attempts > v_max then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    select p_report, r.resident_id, 'validated', 'validated',
           format('Automatic dispatch gave up after %s offers (%s) — manual assignment required',
                  v_attempts, p_why), true
      from public.reports r where r.id = p_report;

    insert into public.notifications (user_id, report_id, kind, message)
    select id, p_report, 'escalation',
           'A report could not be dispatched automatically and needs manual assignment.'
      from public.users where role = 'admin';
    return null;
  end if;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  select p_report, r.resident_id, 'assigned', 'validated',
         format('Re-dispatching: %s (offer %s of %s)', p_why, v_attempts, v_max), true
    from public.reports r where r.id = p_report;

  select public.auto_dispatch(p_report) into v_next;
  return v_next;
end $$;

create or replace function public.sweep_awaiting_units()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r      record;
  v_hours smallint;
begin
  select awaiting_alert_hours into v_hours from public.operational_settings where id = 1;

  for r in
    select id, awaiting_unit_since
      from public.reports
     where awaiting_unit_since is not null
       and deleted_at is null
       and status in ('pending_review', 'validated')
     order by awaiting_unit_since
  loop
    if r.awaiting_unit_since < now() - make_interval(hours => v_hours)
       and not exists (
         select 1 from public.notifications n
          where n.report_id = r.id and n.kind = 'escalation') then
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, r.id, 'escalation',
             format('A report has been waiting over %s hours with no tanod on duty in range.', v_hours)
        from public.users u where u.role = 'admin';
    end if;

    perform public.auto_dispatch(r.id);
  end loop;
end $$;

-- ---------- the trigger point --------------------------------
-- Fires on filing. Categories flagged for automatic dispatch go
-- straight to proximity routing; the rest wait for Validate Report.

create or replace function public.dispatch_on_file()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_auto boolean;
begin
  select auto_dispatch_on_file into v_auto
    from public.sla_policies where category = new.category;

  if coalesce(v_auto, false) then
    perform public.auto_dispatch(new.id);
  end if;

  return null;
end $$;

-- AFTER INSERT so the report row and its tracking id already exist.
create trigger reports_dispatch_on_file
  after insert on public.reports
  for each row execute function public.dispatch_on_file();

-- ---------- admin-editable, admin-only -----------------------

alter table public.operational_settings enable row level security;

create policy settings_read  on public.operational_settings
  for select using (auth.uid() is not null);
create policy settings_write on public.operational_settings
  for update using (public.is_admin()) with check (public.is_admin());

create or replace function public.touch_settings()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger settings_touch before update on public.operational_settings
  for each row execute function public.touch_settings();
