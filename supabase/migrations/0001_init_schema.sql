-- =============================================================
-- SmartSumbong — 0001 Core schema
-- Barangay 183, Pasay City
-- Actor naming: "tanod" throughout (per panel revision).
-- =============================================================

create extension if not exists "postgis";
create extension if not exists "pgcrypto";

-- ---------- Enumerated domains -------------------------------
-- Declared as enums rather than free TEXT so the documented
-- scope is enforced by the database, not by convention.

create type user_role as enum ('resident', 'tanod', 'admin');

create type verification_state as enum ('pending', 'verified', 'rejected');

-- Four states defined by the Update Availability Status use case.
create type duty_state as enum ('on_duty', 'break', 'lunch', 'offline');

-- The seven categories fixed in Scope and Limitations.
create type complaint_category as enum (
  'street_obstruction',
  'public_safety_infrastructure',
  'environmental_waste_hazard',
  'animal_welfare',
  'traffic_violation',
  'barangay_service',
  'peace_order_nuisance'
);

-- Lifecycle states named across the use case reports.
create type report_status as enum (
  'pending_review',
  'validated',
  'assigned',
  'in_progress',
  'offline_investigation',
  'resolved',
  'closed',
  'archived',
  'rejected'
);

create type notification_kind as enum (
  'verification',
  'assignment',
  'reroute',
  'status_change',
  'escalation',
  'sla_warning'
);

-- ---------- users --------------------------------------------
-- Mirrors auth.users. Supabase owns credentials; this row owns
-- everything the barangay cares about.

create table public.users (
  id                        uuid primary key references auth.users (id) on delete cascade,
  full_name                 text        not null,
  email                     text        not null unique,
  mobile_number             text        not null unique,
  role                      user_role   not null default 'resident',

  -- Identity verification (Register Account / Verify User Account)
  id_image_url              text,
  verification_status       verification_state not null default 'pending',
  verification_submitted_at timestamptz,
  verification_due_at       timestamptz,   -- submitted_at + 2h (panel: max 2 hours)
  verified_at               timestamptz,
  verified_by               uuid references public.users (id),
  rejection_reason          text,

  -- Duty / dispatch availability (tanod only)
  duty_status               duty_state,
  is_dispatchable           boolean     not null default false,

  is_suspended              boolean     not null default false,
  suspended_reason          text,

  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint duty_only_for_tanod
    check (duty_status is null or role = 'tanod')
);

create index users_role_idx           on public.users (role);
create index users_verification_idx   on public.users (verification_status)
  where verification_status = 'pending';
create index users_dispatchable_idx   on public.users (is_dispatchable)
  where is_dispatchable = true;

-- Verification SLA: stamp the 2-hour deadline on submission.
create or replace function public.set_verification_deadline()
returns trigger language plpgsql as $$
begin
  if new.verification_submitted_at is not null
     and (old.verification_submitted_at is null
          or old.verification_submitted_at is distinct from new.verification_submitted_at) then
    new.verification_due_at := new.verification_submitted_at + interval '2 hours';
  end if;
  return new;
end $$;

create trigger users_verification_deadline
  before insert or update on public.users
  for each row execute function public.set_verification_deadline();

-- A tanod is only dispatchable while actually on duty.
create or replace function public.sync_dispatchable()
returns trigger language plpgsql as $$
begin
  new.is_dispatchable := (new.role = 'tanod'
                          and new.duty_status = 'on_duty'
                          and new.verification_status = 'verified'
                          and not new.is_suspended);
  return new;
end $$;

create trigger users_sync_dispatchable
  before insert or update on public.users
  for each row execute function public.sync_dispatchable();

-- ---------- sla_policies -------------------------------------
-- Resolution and acceptance windows are DATA, not constants, so
-- the barangay can tune them without a migration.

create table public.sla_policies (
  category          complaint_category primary key,
  resolution_hours  integer not null check (resolution_hours > 0),
  accept_minutes    integer not null check (accept_minutes  > 0),
  updated_at        timestamptz not null default now()
);

comment on table public.sla_policies is
  'Per-category SLA windows. resolution_hours drives reports.due_at; '
  'accept_minutes drives dispatches.accept_due_at. Values are placeholders '
  'pending barangay confirmation.';

-- ---------- reports ------------------------------------------

create sequence public.report_seq;

create table public.reports (
  id                uuid primary key default gen_random_uuid(),
  tracking_id       text not null unique,          -- BRG-YYYY-NNNN
  resident_id       uuid not null references public.users (id) on delete restrict,
  is_anonymous      boolean not null default false,

  category          complaint_category not null,
  subject           text not null check (char_length(subject) between 3 and 150),
  description       text not null check (char_length(description) between 10 and 2000),

  latitude          double precision not null check (latitude  between -90  and 90),
  longitude         double precision not null check (longitude between -180 and 180),
  geom              geography(Point, 4326)
                      generated always as
                      (st_setsrid(st_makepoint(longitude, latitude), 4326)::geography) stored,

  status            report_status not null default 'pending_review',

  -- SLA / escalation. Without these, Figures 18 and 19 are undeliverable.
  due_at            timestamptz,
  escalated_at      timestamptz,
  escalation_level  smallint not null default 0 check (escalation_level between 0 and 3),
  reopened_count    smallint not null default 0 check (reopened_count >= 0),

  resolved_at       timestamptz,
  closed_at         timestamptz,
  deleted_at        timestamptz,                   -- soft delete only: never DELETE a report

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index reports_geom_idx     on public.reports using gist (geom);
create index reports_status_idx   on public.reports (status);
create index reports_category_idx on public.reports (category);
create index reports_due_idx      on public.reports (due_at)
  where status not in ('resolved', 'closed', 'archived');
create index reports_created_idx  on public.reports (created_at desc);

-- Tracking ID in the documented BRG-YYYY-NNNN format.
create or replace function public.assign_tracking_id()
returns trigger language plpgsql as $$
begin
  if new.tracking_id is null then
    new.tracking_id := 'BRG-' || to_char(now(), 'YYYY') || '-' ||
                       lpad(nextval('public.report_seq')::text, 4, '0');
  end if;
  return new;
end $$;

create trigger reports_tracking_id
  before insert on public.reports
  for each row execute function public.assign_tracking_id();

-- Resolution deadline derived from the category's SLA policy.
create or replace function public.set_report_deadline()
returns trigger language plpgsql as $$
declare hrs integer;
begin
  if new.due_at is null then
    select resolution_hours into hrs
      from public.sla_policies where category = new.category;
    if hrs is not null then
      new.due_at := new.created_at + make_interval(hours => hrs);
    end if;
  end if;
  return new;
end $$;

create trigger reports_deadline
  before insert on public.reports
  for each row execute function public.set_report_deadline();

-- ---------- report_media -------------------------------------
-- UC8 permits multiple resident photos (10 MB combined), so this
-- cannot be a single media_url column on reports.

create table public.report_media (
  id           uuid primary key default gen_random_uuid(),
  report_id    uuid not null references public.reports (id) on delete cascade,
  media_url    text not null,
  mime_type    text not null check (mime_type in ('image/jpeg', 'image/png')),
  bytes        integer not null check (bytes > 0),
  uploaded_at  timestamptz not null default now()
);

create index report_media_report_idx on public.report_media (report_id);

-- Enforce the documented 10 MB combined cap per report.
create or replace function public.enforce_media_cap()
returns trigger language plpgsql as $$
declare total bigint;
begin
  select coalesce(sum(bytes), 0) into total
    from public.report_media where report_id = new.report_id;
  if total + new.bytes > 10 * 1024 * 1024 then
    raise exception 'Combined media for this report exceeds the 10 MB limit';
  end if;
  return new;
end $$;

create trigger report_media_cap
  before insert on public.report_media
  for each row execute function public.enforce_media_cap();

-- ---------- status_logs --------------------------------------
-- Append-only audit trail. Backs the resident timeline (UC9) and
-- the tanod activity log in the Report Summary use case.

create table public.status_logs (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  changed_by  uuid references public.users (id),
  old_status  report_status,
  new_status  report_status not null,
  remark      text,
  is_system   boolean not null default false,
  created_at  timestamptz not null default now()
);

create index status_logs_report_idx  on public.status_logs (report_id, created_at);
create index status_logs_actor_idx   on public.status_logs (changed_by, created_at desc);

-- ---------- feedback -----------------------------------------

create table public.feedback (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null unique references public.reports (id) on delete cascade,
  resident_id   uuid not null references public.users (id) on delete restrict,
  rating        smallint not null check (rating between 1 and 5),
  comment       text check (char_length(comment) <= 500),
  submitted_at  timestamptz not null default now()
);

-- ---------- attendance ---------------------------------------
-- Panel comment (Mandigma): duty attendance recorded in the app.

create table public.attendance (
  id            uuid primary key default gen_random_uuid(),
  tanod_id      uuid not null references public.users (id) on delete cascade,
  duty_status   duty_state not null,
  logged_at     timestamptz not null default now(),
  geom          geography(Point, 4326),
  shift_date    date generated always as ((logged_at at time zone 'Asia/Manila')::date) stored
);

create index attendance_tanod_idx on public.attendance (tanod_id, logged_at desc);
create index attendance_date_idx  on public.attendance (shift_date);

-- ---------- notifications ------------------------------------

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  report_id   uuid references public.reports (id) on delete cascade,
  kind        notification_kind not null,
  message     text not null,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, is_read, created_at desc);

-- ---------- updated_at maintenance ---------------------------

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger users_touch    before update on public.users
  for each row execute function public.touch_updated_at();
create trigger reports_touch  before update on public.reports
  for each row execute function public.touch_updated_at();
