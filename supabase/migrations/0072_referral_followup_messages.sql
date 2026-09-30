-- 0072_referral_followup_messages.sql
--
-- Rose's notes (30 Sep 2026):
--
--   * Escalation is the admin's call, and it means the case goes outside
--     the barangay (a VAWC desk, the police, DSWD…). So the system no
--     longer escalates anything on its own. sweep_overdue_reports() now
--     only notices that an admin-set deadline has passed: it tells the
--     admins (and the tanod on the case) once, and the screens say
--     "Overdue". The admin refers with refer_report(): the complaint is
--     closed here, marked with the agency, and the resident is told
--     where it went.
--
--   * The resident can follow up a case that is past its deadline
--     (follow_up_report), and has a place to ask the barangay about
--     their complaint: a message thread per complaint, like chatting
--     with a seller (report_messages, post_report_message).
--
-- escalation_level / escalated_at stay on reports for the history they
-- hold; nothing writes them any more.

set search_path = public, extensions;

-- ---------- columns ----------------------------------------------------

alter table public.reports
  add column if not exists referred_to      text,
  add column if not exists referral_note    text,
  add column if not exists referred_at      timestamptz,
  add column if not exists referred_by      uuid references public.users (id),
  add column if not exists overdue_notified_at timestamptz,
  add column if not exists followed_up_at   timestamptz,
  add column if not exists follow_up_count  integer not null default 0;

comment on column public.reports.referred_to is
  'The outside authority the admin referred this complaint to (0072), '
  'e.g. VAWC Desk. Set together with status closed.';

-- ---------- the sweep: overdue, not escalated ---------------------------
-- Replaces 0063's version. No escalation levels, no automatic
-- cancellation: once per deadline, the admins and the tanod on the case
-- hear that it has passed.

create or replace function public.sweep_overdue_reports()
returns void language plpgsql security definer set search_path = public as $$
begin
  with late as (
    update public.reports
       set overdue_notified_at = now()
     where due_at is not null
       and due_at < now()
       and (overdue_notified_at is null or overdue_notified_at < due_at)
       and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and deleted_at is null
    returning id, tracking_id
  ),
  to_admins as (
    insert into public.notifications (user_id, report_id, kind, message)
    select u.id, l.id, 'sla_warning',
           'Complaint ' || l.tracking_id || ' is overdue: its target date has passed.'
      from late l cross join public.users u
     where u.role = 'admin'
    returning 1
  )
  insert into public.notifications (user_id, report_id, kind, message)
  select d.tanod_id, l.id, 'sla_warning',
         'Your dispatch ' || l.tracking_id || ' is overdue: its target date has passed.'
    from late l
    join public.dispatches d on d.report_id = l.id and d.state in ('assigned', 'accepted');
end $$;

comment on function public.sweep_overdue_reports() is
  '0072: tells admins and the dispatched tanod once when an admin-set '
  'deadline passes. Escalation is the admin''s referral (refer_report).';

-- ---------- refer_report() ---------------------------------------------

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
    raise exception 'Only an administrator may refer a complaint';
  end if;
  if v_agency is null then
    raise exception 'Choose the office the complaint is referred to';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null for update;
  if not found then
    raise exception 'No such report';
  end if;
  if v_report.status in ('closed', 'archived', 'rejected', 'cancelled') then
    raise exception 'This complaint is already closed';
  end if;

  -- A tanod still on it is stood down; their window shows it closed.
  update public.dispatches
     set state = 'rerouted', rerouted_at = now(),
         reroute_reason = 'Referred to ' || v_agency
   where report_id = p_report and state in ('assigned', 'accepted');

  update public.reports
     set status        = 'closed',
         closed_at     = now(),
         referred_to   = v_agency,
         referral_note = v_note,
         referred_at   = now(),
         referred_by   = auth.uid()
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'closed',
          'Referred to ' || v_agency || coalesce(': ' || v_note, '.'));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          format('Your complaint %s has been referred to the %s, which handles this kind of case.%s',
                 v_report.tracking_id, v_agency,
                 coalesce(' Note from the barangay: ' || v_note, '')));
end $$;

revoke execute on function public.refer_report(uuid, text, text) from public, anon;
grant execute on function public.refer_report(uuid, text, text) to authenticated;

-- ---------- report_messages ------------------------------------------

create table if not exists public.report_messages (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.reports (id) on delete cascade,
  author_id     uuid not null references public.users (id),
  from_barangay boolean not null,
  body          text not null check (char_length(trim(body)) between 1 and 1000),
  created_at    timestamptz not null default now()
);

create index if not exists report_messages_idx
  on public.report_messages (report_id, created_at);

alter table public.report_messages enable row level security;

drop policy if exists report_messages_read on public.report_messages;
create policy report_messages_read on public.report_messages
  for select using (
    public.is_admin()
    or exists (select 1 from public.reports r
                where r.id = report_messages.report_id
                  and r.resident_id = auth.uid()
                  and r.deleted_at is null)
  );

comment on table public.report_messages is
  'A complaint''s question thread between the resident and the barangay '
  '(0072). Read by the resident who filed it and admins; written only '
  'through post_report_message() and follow_up_report().';

-- ---------- follow_up_report() -----------------------------------------
-- The resident's "up" on a complaint past its deadline. Once a day at
-- most; an optional message also lands in the complaint's thread.

create or replace function public.follow_up_report(p_report uuid, p_message text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_msg    text := nullif(trim(coalesce(p_message, '')), '');
begin
  select * into v_report from public.reports
   where id = p_report and resident_id = auth.uid() and deleted_at is null
   for update;
  if not found then
    raise exception 'Complaint not found';
  end if;
  if v_report.status in ('resolved', 'closed', 'archived', 'rejected', 'cancelled') then
    raise exception 'This complaint is already finished';
  end if;
  if v_report.due_at is null or v_report.due_at > now() then
    raise exception 'You can follow up once the target date has passed';
  end if;
  if v_report.followed_up_at is not null
     and v_report.followed_up_at > now() - interval '24 hours' then
    raise exception 'You already followed up today. The barangay has been told.';
  end if;
  if v_msg is not null and char_length(v_msg) > 1000 then
    raise exception 'Keep the message under 1000 characters';
  end if;

  update public.reports
     set followed_up_at = now(), follow_up_count = follow_up_count + 1
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, v_report.status,
          'The resident followed up on this overdue complaint.');

  if v_msg is not null then
    insert into public.report_messages (report_id, author_id, from_barangay, body)
    values (p_report, auth.uid(), false, v_msg);
  end if;

  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, p_report, 'sla_warning',
         'The resident followed up on overdue complaint ' || v_report.tracking_id
         || coalesce(': ' || left(v_msg, 140), '.')
    from public.users u where u.role = 'admin';
end $$;

revoke execute on function public.follow_up_report(uuid, text) from public, anon;
grant execute on function public.follow_up_report(uuid, text) to authenticated;

create or replace function public.post_report_message(p_report uuid, p_body text)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report public.reports%rowtype;
  v_admin  boolean := public.is_admin();
  v_body   text := nullif(trim(coalesce(p_body, '')), '');
  v_id     uuid;
begin
  if v_body is null then
    raise exception 'Write a message first';
  end if;
  if char_length(v_body) > 1000 then
    raise exception 'Keep the message under 1000 characters';
  end if;

  select * into v_report from public.reports
   where id = p_report and deleted_at is null;
  if not found or (not v_admin and v_report.resident_id is distinct from auth.uid()) then
    raise exception 'Complaint not found';
  end if;

  insert into public.report_messages (report_id, author_id, from_barangay, body)
  values (p_report, auth.uid(), v_admin, v_body)
  returning id into v_id;

  if v_admin then
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_report.resident_id, p_report, 'status_change',
            'The barangay replied about ' || v_report.tracking_id || ': ' || left(v_body, 140));
  else
    insert into public.notifications (user_id, report_id, kind, message)
    select u.id, p_report, 'status_change',
           'A resident asked about ' || v_report.tracking_id || ': ' || left(v_body, 140)
      from public.users u where u.role = 'admin';
  end if;

  return v_id;
end $$;

revoke execute on function public.post_report_message(uuid, text) from public, anon;
grant execute on function public.post_report_message(uuid, text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'report_messages') then
    alter publication supabase_realtime add table public.report_messages;
  end if;
end $$;

-- ---------- tanod live tracking, removed ---------------------------------
-- Rose: remove all tanod live tracking. The app stopped streaming in
-- branch B (0067); what 0059 left behind goes here: the location history,
-- the live-position and path-heatmap reads, and the nightly purge. A
-- tanod's single last known location stays on users — dispatch needs it.

create or replace function public.update_my_location(p_lat double precision,
                                                     p_lon double precision)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_geom geography(Point, 4326) :=
    st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  update public.users
     set last_geom = v_geom,
         last_location_at = now()
   where id = auth.uid()
     and role = 'tanod'
     and duty_status = 'on_duty';

  if not found then
    raise exception 'Location is only recorded for a tanod who is on duty';
  end if;
end $$;

drop function if exists public.tanod_live_positions();
drop function if exists public.tanod_path_heatmap(timestamptz, timestamptz, uuid);

do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-old-tanod-locations') then
    perform cron.unschedule('purge-old-tanod-locations');
  end if;
end $$;

drop table if exists public.tanod_locations;

-- ---------- dashboard: referrals are the escalations ---------------------
-- 0056's dashboard_metrics, with referred complaints in their own bucket
-- (not counted as resolved) and the Escalated tile counting referrals.

create or replace function public.dashboard_metrics(
  p_from     timestamptz,
  p_to       timestamptz,
  p_category complaint_category default null)
returns json
language plpgsql stable set search_path = public, extensions as $$
declare
  v_out json;
begin
  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'Invalid reporting period';
  end if;

  with scoped as (
    select r.*,
           -- "Finished" covers resolved and closed alike: a complaint
           -- the barangay has dealt with, whether or not the resident
           -- has since confirmed it.
           (r.status in ('resolved', 'closed', 'archived'))         as is_done,
           coalesce(r.resolved_at, r.closed_at)                     as finished_at
      from public.reports r
     where r.deleted_at is null
       and r.created_at >= p_from
       and r.created_at <  p_to
  ),
  classified as (
    select s.*,
           case
             -- Sent to an outside office (0072): neither resolved here
             -- nor still open.
             when s.referred_to is not null                then 'referred'
             -- Finished after the deadline it was given.
             when s.is_done and s.due_at is not null
                  and s.finished_at > s.due_at              then 'late'
             -- Finished in time, or finished with no deadline set.
             when s.is_done                                then 'done'
             -- Still open and the deadline has passed.
             when s.due_at is not null and now() > s.due_at then 'overdue'
             -- Still open, still inside the window. Rejected complaints
             -- are not work in progress and are counted separately.
             when s.status = 'rejected'                    then 'rejected'
             else                                               'processing'
           end as bucket
      from scoped s
  )
  select json_build_object(

    'period', json_build_object('from', p_from, 'to', p_to),

    'total', (select count(*) from scoped),

    -- Reports filed per calendar day, Manila time, with empty days
    -- present as zeroes so the line does not lie by skipping them.
    'daily', (
      select coalesce(json_agg(json_build_object(
               'day',   to_char(d.day, 'YYYY-MM-DD'),
               'label', to_char(d.day, 'FMDD'),
               'filed', coalesce(c.n, 0)) order by d.day), '[]'::json)
        from generate_series(
               (p_from at time zone 'Asia/Manila')::date,
               (p_to   at time zone 'Asia/Manila')::date - 1,
               interval '1 day') as d(day)
        left join (
          select (created_at at time zone 'Asia/Manila')::date as day, count(*) as n
            from scoped group by 1) c on c.day = d.day::date
    ),

    'resolution_status', (
      select json_build_object(
               'done',       count(*) filter (where bucket = 'done'),
               'overdue',    count(*) filter (where bucket = 'overdue'),
               'late',       count(*) filter (where bucket = 'late'),
               'processing', count(*) filter (where bucket = 'processing'),
               'rejected',   count(*) filter (where bucket = 'rejected'),
               'referred',   count(*) filter (where bucket = 'referred'))
        from classified
    ),

    'categories', (
      select coalesce(json_agg(json_build_object(
               'category', category, 'n', n) order by n desc, category), '[]'::json)
        from (select category::text as category, count(*) as n
                from scoped group by 1) t
    ),

    -- The three counters. Resolved and escalated are counts; the third
    -- is every complaint whose deadline has passed with nobody having
    -- finished it, which is the number an admin actually needs to see.
    'tiles', (
      select json_build_object(
               'resolved',  count(*) filter (where bucket in ('done', 'late')),
               -- 0072: escalated now means referred outside the barangay;
               -- the key keeps its name for the dashboard's sake.
               'escalated', count(*) filter (where bucket = 'referred'),
               'overdue',   count(*) filter (where bucket = 'overdue'))
        from classified
    ),

    -- Resolution efficiency: for each day, the mean hours between filing
    -- and finishing for the complaints finished that day, against the
    -- policy window they were held to. Two lines, one chart — "we took
    -- 31 hours" means nothing without "we were allowed 48". p_category
    -- (0056), when given, narrows this one chart only — every other key
    -- above is computed from the unfiltered `scoped`/`classified` CTEs.
    'efficiency', (
      select coalesce(json_agg(json_build_object(
               'day',     to_char(d.day, 'YYYY-MM-DD'),
               'label',   to_char(d.day, 'FMDD'),
               'actual',  e.avg_hours,
               'allowed', e.avg_target,
               'n',       coalesce(e.n, 0)) order by d.day), '[]'::json)
        from generate_series(
               (p_from at time zone 'Asia/Manila')::date,
               (p_to   at time zone 'Asia/Manila')::date - 1,
               interval '1 day') as d(day)
        left join (
          select (c.finished_at at time zone 'Asia/Manila')::date as day,
                 count(*) as n,
                 round(avg(extract(epoch from (c.finished_at - c.created_at)) / 3600)::numeric, 1)
                   as avg_hours,
                 round(avg(p.resolution_hours)::numeric, 1) as avg_target
            from classified c
            join public.sla_policies p on p.category = c.category
           where c.finished_at is not null
             and (p_category is null or c.category = p_category)
           group by 1) e on e.day = d.day::date
    )

  ) into v_out;

  return v_out;
end $$;

revoke execute on function public.dashboard_metrics(timestamptz, timestamptz, complaint_category) from public, anon;
grant  execute on function public.dashboard_metrics(timestamptz, timestamptz, complaint_category) to authenticated;
