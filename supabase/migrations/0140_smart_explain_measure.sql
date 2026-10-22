-- =============================================================
-- SmartSumbong — 0140 SMART explains itself and is measured (Iteration 2)
--
-- Ace (22 Oct 2026): the engine must be comprehensive for the phone and the
-- portal, and measurable. Until now SMART decided and the app showed none of
-- it, and nothing recorded whether the barangay followed its advice.
--
--   1. smart_events: one log of what SMART decides and what people do with
--      it (picked, fix asked, fix answered; later modes and rule changes).
--   2. dispatches.smart_*: where SMART ranked the tanod the admin chose,
--      saved with the dispatch, with the reasons. The tanod's "Why you"
--      reads it; smart_pick_stats() says how often the top pick was taken.
--   3. resolution_checks: when a case is resolved the resident is asked
--      "Naayos na ba? / Was it fixed?". "No" puts the case back in the
--      SMART queue (stage recheck) until the barangay reopens or answers.
--   4. smart_why_order(): a plain sentence for the resident, in English and
--      Tagalog, never a score.
--   5. smart_engine_health(): when the watcher last ran, what is unscored.
--   6. smart_fix_stats(): asked, answered and fixed, per kind.
-- A reading of SMART is advice; nothing here decides for a person.
-- =============================================================

set search_path = public, extensions;

-- ---------- 1. the event log -------------------------------------------

create table public.smart_events (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default clock_timestamp(),
  kind      text not null,
  report_id uuid references public.reports (id) on delete set null,
  actor     uuid references public.users (id) on delete set null,
  summary   text not null check (char_length(summary) <= 300),
  detail    jsonb not null default '{}'
);
create index smart_events_at_idx on public.smart_events (at desc);
create index smart_events_report_idx on public.smart_events (report_id, at desc) where report_id is not null;
alter table public.smart_events enable row level security;
create policy smart_events_admin_read on public.smart_events for select using ((select public.is_admin()));
comment on table public.smart_events is
  '0140: what SMART decided and what people did with it. Written only by _smart_event() from SMART''s own functions; kept 180 days.';

create or replace function public._smart_event(p_kind text, p_report uuid, p_summary text, p_detail jsonb default '{}')
returns void
language sql security definer set search_path = public as $$
  insert into public.smart_events (kind, report_id, actor, summary, detail)
  values (p_kind, p_report, auth.uid(), left(p_summary, 300), coalesce(p_detail, '{}'));
$$;
revoke all on function public._smart_event(text, uuid, text, jsonb) from public, anon, authenticated;

select cron.schedule('smart-events-purge', '55 3 * * *', $$ delete from public.smart_events where at < now() - interval '180 days' $$);

-- ---------- 2. SMART's pick, saved with the dispatch --------------------

alter table public.dispatches
  add column if not exists smart_rank smallint,
  add column if not exists smart_of smallint,
  add column if not exists smart_score smallint,
  add column if not exists smart_reasons jsonb;
comment on column public.dispatches.smart_rank is
  '0140: where SMART ranked this tanod (1 = its first choice) among the tanods it could have sent when the dispatch was made. Null: not on its list, or made before 0140. smart_of is how many were on the list.';

alter table public.smart_rules
  add column if not exists queue_recheck_points smallint not null default 30 check (queue_recheck_points between 0 and 100);
comment on column public.smart_rules.queue_recheck_points is
  '0140: queue points for a resolved case the resident says is not fixed.';


-- ---------- 3. "Was it fixed?" ----------------------------------------

create table public.resolution_checks (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  resident_id uuid not null references public.users (id) on delete cascade,
  asked_at    timestamptz not null default now(),
  answered_at timestamptz,
  fixed       boolean,
  note        text check (char_length(note) <= 300),
  handled_at  timestamptz,
  handled_by  uuid references public.users (id),
  check ((answered_at is null) = (fixed is null))
);
create unique index resolution_checks_one_open on public.resolution_checks (report_id) where answered_at is null;
create index resolution_checks_report_idx on public.resolution_checks (report_id, asked_at desc);
alter table public.resolution_checks enable row level security;
create policy resolution_checks_owner_read on public.resolution_checks for select using (resident_id = (select auth.uid()));
create policy resolution_checks_admin_read on public.resolution_checks for select using ((select public.is_admin()));
comment on table public.resolution_checks is
  '0140: "Naayos na ba? / Was it fixed?" asked of the resident when a case is resolved. Answered only through confirm_fix(), within 14 days.';

create or replace function public._ask_if_fixed()
returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.deleted_at is null and new.resident_id is not null
     and not exists (select 1 from public.resolution_checks c where c.report_id = new.id and c.answered_at is null) then
    insert into public.resolution_checks (report_id, resident_id) values (new.id, new.resident_id);
    insert into public.notifications (user_id, report_id, kind, message)
    values (new.resident_id, new.id, 'status_change',
            format('Naayos na ba? / Was it fixed? Please tell us about %s in the app.', new.tracking_id));
    perform public._smart_event('fix_asked', new.id, format('Asked the resident if %s was fixed', new.tracking_id));
  end if;
  return null;
end $$;

drop trigger if exists reports_ask_if_fixed on public.reports;
create trigger reports_ask_if_fixed after update of status on public.reports
  for each row when (new.status = 'resolved' and old.status is distinct from 'resolved')
  execute function public._ask_if_fixed();

create or replace function public.confirm_fix(p_report uuid, p_fixed boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  c public.resolution_checks%rowtype;
  v_tick text;
  v_note text := left(nullif(trim(coalesce(p_note, '')), ''), 300);
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_fixed is null then raise exception 'Say whether it was fixed'; end if;
  select * into c from public.resolution_checks
   where report_id = p_report and resident_id = auth.uid() and answered_at is null for update;
  if not found then raise exception 'There is nothing to confirm for this report'; end if;
  if c.asked_at < now() - interval '14 days' then raise exception 'This check has closed'; end if;

  update public.resolution_checks set answered_at = now(), fixed = p_fixed, note = v_note where id = c.id;
  select tracking_id into v_tick from public.reports where id = p_report;
  perform public._smart_event('fix_answered', p_report,
    format('The resident says %s %s', v_tick, case when p_fixed then 'is fixed' else 'is not fixed' end),
    jsonb_build_object('fixed', p_fixed));

  if not p_fixed then
    insert into public.notifications (user_id, report_id, kind, message)
    select a.id, p_report, 'status_change',
           format('A resident says %s is not fixed.%s', v_tick, case when v_note is null then '' else ' "' || v_note || '"' end)
      from public.users a where a.role = 'admin' and not coalesce(a.is_suspended, false);
  end if;
end $$;

-- ---------- 4. a plain sentence for the resident -----------------------

create or replace function public.smart_why_order(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_owner uuid;
  v_en text[] := '{}';
  v_fil text[] := '{}';
  r jsonb;
begin
  select resident_id into v_owner from public.reports where id = p_report and deleted_at is null;
  if not found then return null; end if;
  if v_owner is distinct from auth.uid() and not public.is_admin() then
    raise exception 'That is not your report' using errcode = 'insufficient_privilege';
  end if;
  for r in select e from public.report_triage t, jsonb_array_elements(t.reasons) e where t.report_id = p_report loop
    case r ->> 'factor'
      when 'category' then
        if r ->> 'detail' = 'public_safety_infrastructure' then
          v_en := array_append(v_en, 'it involves public safety'); v_fil := array_append(v_fil, 'may kinalaman ito sa kaligtasan ng publiko');
        elsif r ->> 'detail' = 'peace_order_nuisance' then
          v_en := array_append(v_en, 'it involves peace and order'); v_fil := array_append(v_fil, 'may kinalaman ito sa katahimikan at kaayusan');
        elsif r ->> 'detail' = 'environmental_waste_hazard' then
          v_en := array_append(v_en, 'it is a health or environment hazard'); v_fil := array_append(v_fil, 'panganib ito sa kalusugan o kapaligiran');
        end if;
      when 'words' then
        v_en := array_append(v_en, 'it mentions a danger to people'); v_fil := array_append(v_fil, 'may nabanggit itong panganib sa tao');
      when 'hazard zone' then
        v_en := array_append(v_en, 'it is in an area that floods easily'); v_fil := array_append(v_fil, 'nasa lugar ito na madaling bahain');
      when 'nearby reports' then
        v_en := array_append(v_en, 'other residents reported the same problem nearby'); v_fil := array_append(v_fil, 'may iba pang residente na nag-ulat ng parehong problema sa malapit');
      else null;
    end case;
  end loop;
  return jsonb_build_object(
    'en', 'Reports are handled in order of how urgent they are, and the longer one waits, the higher it moves.'
          || case when cardinality(v_en) > 0 then ' Yours is higher because ' || array_to_string(v_en, ', ') || '.' else '' end,
    'fil', 'Inaayos ang mga report ayon sa pagkaapurahan, at habang tumatagal ang isa, tumataas ito.'
          || case when cardinality(v_fil) > 0 then ' Mas mataas ang sa iyo dahil ' || array_to_string(v_fil, ', ') || '.' else '' end);
end $$;

-- ---------- 5. is the engine running? ---------------------------------

create or replace function public.smart_engine_health()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_last record;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  select d.status, d.start_time into v_last
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname = 'smart-watch' order by d.start_time desc limit 1;
  return jsonb_build_object(
    'watch_last_at', v_last.start_time,
    'watch_last_ok', v_last.status = 'succeeded',
    'watch_failures_24h', (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                            where j.jobname = 'smart-watch' and d.status <> 'succeeded' and d.start_time > now() - interval '24 hours'),
    'open_reports', (select count(*) from public.reports r where r.deleted_at is null
                      and r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
    'unscored', (select count(*) from public.reports r where r.deleted_at is null
                  and r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
                  and not exists (select 1 from public.report_triage t where t.report_id = r.id)),
    'last_scored_at', (select max(computed_at) from public.report_triage),
    'events_24h', (select count(*) from public.smart_events where at > now() - interval '24 hours'),
    'routing_on', (select smart_routing from public.smart_rules where id = 1),
    'queue_on', (select smart_queue from public.smart_rules where id = 1));
end $$;

-- ---------- 6. measuring it ---------------------------------------------

create or replace function public.smart_pick_stats(p_days integer default 90)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  return (
    select jsonb_build_object(
      'days', p_days,
      'dispatches', count(*),
      'ranked', count(*) filter (where smart_rank is not null),
      'top_pick', count(*) filter (where smart_rank = 1),
      'top_three', count(*) filter (where smart_rank <= 3),
      'top_pick_pct', case when count(*) filter (where smart_rank is not null) = 0 then null
                           else round(100.0 * count(*) filter (where smart_rank = 1) / count(*) filter (where smart_rank is not null), 1) end)
      from public.dispatches where assigned_at > now() - make_interval(days => greatest(1, p_days)));
end $$;

create or replace function public.smart_fix_stats(p_days integer default 90)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  return jsonb_build_object(
    'days', p_days,
    'asked', (select count(*) from public.resolution_checks where asked_at > now() - make_interval(days => greatest(1, p_days))),
    'answered', (select count(*) from public.resolution_checks where answered_at > now() - make_interval(days => greatest(1, p_days))),
    'fixed', (select count(*) from public.resolution_checks where fixed and answered_at > now() - make_interval(days => greatest(1, p_days))),
    'not_fixed', (select count(*) from public.resolution_checks where fixed is false and answered_at > now() - make_interval(days => greatest(1, p_days))),
    'waiting_for_barangay', (select count(*) from public.resolution_checks where fixed is false and handled_at is null),
    'by_kind', coalesce((select jsonb_agg(jsonb_build_object('category', k.category, 'answered', k.n, 'fixed', k.f) order by k.n desc)
                           from (select r.category, count(*) n, count(*) filter (where c.fixed) f
                                   from public.resolution_checks c join public.reports r on r.id = c.report_id
                                  where c.answered_at > now() - make_interval(days => greatest(1, p_days)) group by r.category) k), '[]'));
end $$;

revoke all on function public.confirm_fix(uuid, boolean, text), public.smart_why_order(uuid), public.smart_engine_health(),
  public.smart_pick_stats(integer), public.smart_fix_stats(integer) from public, anon;
grant execute on function public.confirm_fix(uuid, boolean, text), public.smart_why_order(uuid), public.smart_engine_health(),
  public.smart_pick_stats(integer), public.smart_fix_stats(integer) to authenticated;

-- ---------- the dispatch and queue code, with the additions above ----------

CREATE OR REPLACE FUNCTION public.admin_dispatch(p_report uuid, p_tanod uuid, p_instructions text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $$
declare
  v_report   public.reports%rowtype;
  v_tanod    public.users%rowtype;
  v_busy     text;
  v_dispatch uuid;
  v_metres   double precision;
  v_note     text := nullif(trim(coalesce(p_instructions, '')), '');
  v_rank     smallint;
  v_of       smallint;
  v_score    smallint;
  v_reasons  jsonb;
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

  select case when count(*) >= public.tanod_dispatch_cap() then max(r.subject) end into v_busy
    from public.dispatches d
    join public.reports r on r.id = d.report_id
   where d.tanod_id = p_tanod and d.state in ('assigned', 'accepted');

  if v_busy is not null then
    raise exception
      '% already has the most dispatches a tanod can hold at once. Choose another available tanod.',
      v_tanod.full_name;
  end if;

  select st_distance(v_tanod.last_geom, v_report.geom) into v_metres;

  -- 0140: where SMART ranked this tanod among those it could have sent, before this dispatch changes their load.
  -- Null when the tanod was not on its list (nothing is hidden: the admin's choice stands either way).
  select q.rn, q.n, q.score, q.reasons into v_rank, v_of, v_score, v_reasons
    from (select r.tanod_id, r.score, r.reasons,
                 row_number() over (order by r.score desc, r.metres nulls last)::smallint as rn,
                 count(*) over ()::smallint as n
            from public._smart_tanod_ranking(p_report) r) q
   where q.tanod_id = p_tanod;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions,
                                 smart_rank, smart_of, smart_score, smart_reasons)
  values (p_report, p_tanod, auth.uid(), v_note, v_rank, v_of, v_score, v_reasons)
  returning id into v_dispatch;

  perform public._smart_event('picked', p_report,
    format('%s assigned%s', v_tanod.full_name,
           case when v_rank is null then ' (not on SMART''s list)' else format(' (SMART''s #%s of %s)', v_rank, v_of) end),
    jsonb_build_object('tanod', p_tanod, 'rank', v_rank, 'of', v_of, 'score', v_score, 'by', auth.uid()));

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

CREATE OR REPLACE FUNCTION public.auto_dispatch(p_report uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $$
declare
  v_report     public.reports%rowtype;
  v_tanod      uuid;
  v_tanod_name text;
  v_metres     double precision;
  v_dispatch   uuid;
  v_system     uuid;
  v_last       text;
  v_smart      boolean;
  v_pick       record;
begin
  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  -- 0139: past the cap the case is the barangay's: no further automatic offers, and nothing logged.
  if v_report.dispatch_attempts > (select max_dispatch_attempts from public.operational_settings where id = 1) then
    return null;
  end if;

  -- NEW (0064): the newest remark on this report's trail, so a retry
  -- that changes nothing doesn't log the same line again.
  select remark into v_last
    from public.status_logs
   where report_id = p_report
   order by created_at desc
   limit 1;

  -- Out of jurisdiction: refer, do not dispatch.
  if not public.is_within_barangay(v_report.latitude, v_report.longitude) then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    if v_last is distinct from 'Outside Barangay 183 — referred to city services' then
      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'Outside Barangay 183 — referred to city services', true);
    end if;
    return null;
  end if;

  -- 0128: the same tanods as before (nearest_available_tanod decides who
  -- can take it); SMART only decides the order, by distance, jobs in hand,
  -- cases closed nearby and location age, when smart_rules.smart_routing
  -- is on. Off: the nearest, as before.
  select coalesce((select smart_routing from public.smart_rules where id = 1), false) into v_smart;
  if v_smart then
    select t.tanod_id, t.full_name, t.metres, t.score, t.active_jobs, t.closed_nearby into v_pick
      from public._smart_tanod_ranking(p_report) t limit 1;
    v_tanod := v_pick.tanod_id; v_tanod_name := v_pick.full_name; v_metres := v_pick.metres;
  else
    select t.tanod_id, t.full_name, t.metres into v_tanod, v_tanod_name, v_metres
      from public.nearest_available_tanod(p_report) t limit 1;
  end if;

  if v_tanod is null then
    -- 0139: a reroute that found no one waits in line (sweep_awaiting_units retries it, within its limits). A
    -- first filing does not: every first dispatch is the admin's (0070).
    if v_report.dispatch_attempts > 0 and v_report.awaiting_unit_since is null then
      update public.reports set awaiting_unit_since = now() where id = p_report;
    end if;
    if v_last is distinct from
         'No tanod available for automatic dispatch — awaiting manual assignment' then
      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'No tanod available for automatic dispatch — awaiting manual assignment', true);
    end if;
    return null;
  end if;

  -- assigned_by records the system, using the report's own admin-less
  -- path: attributed to the nearest tanod's own id would be wrong, so
  -- the first admin on record stands as the dispatching authority.
  select id into v_system from public.users where role = 'admin' order by created_at limit 1;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, v_tanod, coalesce(v_system, v_tanod),
          case when v_smart then
                 format('Automatic dispatch — SMART pick: %s, %s job(s) in hand, %s case(s) closed nearby.',
                        coalesce(round(v_metres) || ' m from the incident', 'no location shared yet'),
                        v_pick.active_jobs, v_pick.closed_nearby)
               when v_metres is null
               then 'Automatic dispatch — on-duty unit; no location shared yet.'
               else format('Automatic dispatch — nearest available unit, %s m from the incident.',
                           round(v_metres)) end)
  returning id into v_dispatch;

  -- 0140: the system's own pick is SMART's first choice, with the reasons the tanod can read
  if v_smart then
    update public.dispatches
       set smart_rank = 1, smart_score = v_pick.score,
           smart_of = (select count(*)::smallint from public._smart_tanod_ranking(p_report)),
           smart_reasons = jsonb_build_array(
             jsonb_build_object('factor', 'distance', 'detail', coalesce(round(v_metres) || ' m away', 'no location yet')),
             jsonb_build_object('factor', 'workload', 'detail', v_pick.active_jobs || ' job(s) in hand'),
             jsonb_build_object('factor', 'knows the area', 'detail', v_pick.closed_nearby || ' case(s) closed within 300 m, last 90 days'))
     where id = v_dispatch;
    perform public._smart_event('picked', p_report, format('%s auto-dispatched (SMART''s #1)', v_tanod_name),
      jsonb_build_object('tanod', v_tanod, 'rank', 1, 'score', v_pick.score, 'auto', true));
  end if;

  update public.reports set status = 'assigned', awaiting_unit_since = null where id = p_report;

  -- NEW (0047): names the tanod, same pattern admin_dispatch already
  -- uses ("Manually assigned to %s by admin ...") -- the resident's
  -- timeline now answers "who is coming", not just "how far".
  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          case when v_metres is null
               then format('Auto-dispatched to %s', v_tanod_name)
               else format('Auto-dispatched to %s (%s m away)', v_tanod_name, round(v_metres)) end, true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment',
          format('New dispatch: %s', v_report.subject));

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'assignment',
          format('A tanod has been dispatched to your report %s.', v_report.tracking_id));

  return v_dispatch;
end $$;

CREATE OR REPLACE FUNCTION public._smart_queue()
 RETURNS TABLE(report_id uuid, tracking_id text, subject text, category complaint_category, stage text, next_action text, waiting_since timestamp with time zone, level text, priority integer, reasons jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $$
  with k as (select * from public.smart_rules where id = 1),
  risky as (select dr.report_id from public._smart_deadline_risk() dr where dr.risk = 'high'),
  open_cases as (
    select r.* from public.reports r
     where r.deleted_at is null
       and (r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
            -- 0140: a resolved case the resident says is not fixed, until the barangay reopens it or answers them
            or (r.status = 'resolved' and exists (
                  select 1 from public.resolution_checks c
                   where c.report_id = r.id and c.fixed is false and c.handled_at is null
                     and not exists (select 1 from public.report_messages m
                                      where m.report_id = r.id and m.from_barangay and m.created_at >= c.answered_at))))
  ),
  facts as materialized (
    select o.id, o.tracking_id, o.subject, o.category, o.status, o.due_at, o.created_at,
           o.resolution_submitted_at, o.awaiting_unit_since, o.updated_at,
           (select min(e.created_at) from public.escalation_requests e where e.report_id = o.id and e.status = 'pending') as esc_at,
           (select min(d.assigned_at) from public.dispatches d where d.report_id = o.id and d.state = 'assigned') as unaccepted_at,
           (select max(c.answered_at) from public.resolution_checks c
             where c.report_id = o.id and c.fixed is false and c.handled_at is null and o.status = 'resolved') as recheck_at,
           exists (select 1 from public.dispatches d where d.report_id = o.id and d.state in ('assigned', 'accepted')) as live,
           (select m.created_at from public.report_messages m where m.report_id = o.id
             order by m.created_at desc limit 1) as last_msg_at,
           (select not m.from_barangay from public.report_messages m where m.report_id = o.id
             order by m.created_at desc limit 1) as last_msg_resident,
           (select l.created_at from public.status_logs l where l.report_id = o.id and l.new_status = o.status
             order by l.created_at desc limit 1) as status_at
      from open_cases o
  ),
  staged as (
    select f.*,
      case when f.esc_at is not null then 'escalation'
           when f.recheck_at is not null then 'recheck'
           when f.resolution_submitted_at is not null then 'approve'
           when f.status = 'pending_review' then 'review'
           when f.status = 'validated' and not f.live then 'dispatch'
           when f.unaccepted_at is not null then 'accept'
           when coalesce(f.last_msg_resident, false) then 'reply'
           else 'follow_up' end as stage
      from facts f
  ),
  timed as (
    select s.*,
      case s.stage
        when 'escalation' then s.esc_at
        when 'recheck'    then s.recheck_at
        when 'approve'    then s.resolution_submitted_at
        when 'review'     then s.created_at
        when 'dispatch'   then coalesce(s.awaiting_unit_since, s.status_at, s.created_at)
        when 'accept'     then s.unaccepted_at
        when 'reply'      then s.last_msg_at
        else greatest(s.status_at, s.last_msg_at, s.created_at) end as since
      from staged s
  ),
  scored as (
    select t.*,
           tr.effective_level,
           case when tr.override_level is not null
                then (array[10, 35, 55, 80])[array_position(array['low', 'normal', 'high', 'urgent'], tr.override_level)]
                else coalesce(tr.score, 0) end as base,
           least(k.queue_aging_cap, floor(extract(epoch from now() - t.since) / 60 / k.queue_aging_minutes))::integer as aging,
           (t.due_at is not null and t.due_at < now()) as overdue,
           (rk.report_id is not null) as at_risk,
           (t.stage = 'follow_up' and t.since < now() - make_interval(days => k.stuck_days)) as quiet,
           k.queue_overdue_points as p_over, k.queue_risk_points as p_risk, k.queue_quiet_points as p_quiet, k.queue_recheck_points as p_recheck
      from timed t
      cross join k
      left join public.report_triage tr on tr.report_id = t.id
      left join risky rk on rk.report_id = t.id
  )
  select s.id, s.tracking_id, s.subject, s.category, s.stage,
         case s.stage
           when 'escalation' then 'Decide the escalation request'
           when 'recheck'    then 'The resident says it is not fixed: reopen it or answer them'
           when 'approve'    then 'Approve or return the tanod''s resolution'
           when 'review'     then 'Review the complaint'
           when 'dispatch'   then 'Assign a tanod'
           when 'accept'     then 'Waiting for the tanod to accept'
           when 'reply'      then 'Reply to the resident'
           else 'Follow up' end,
         s.since, coalesce(s.effective_level, 'unscored'),
         (s.base + s.aging + case when s.overdue then s.p_over else 0 end
                 + case when s.at_risk then s.p_risk else 0 end
                 + case when s.quiet then s.p_quiet else 0 end
                 + case when s.stage = 'recheck' then s.p_recheck else 0 end)::integer,
         jsonb_build_array(
           jsonb_build_object('factor', 'urgency', 'points', s.base,
             'detail', coalesce(initcap(s.effective_level), 'Not scored')),
           jsonb_build_object('factor', 'waiting', 'points', s.aging,
             'detail', format('%s h at this stage', floor(extract(epoch from now() - s.since) / 3600)::integer)))
         || case when s.overdue then jsonb_build_array(jsonb_build_object('factor', 'overdue', 'points', s.p_over,
                    'detail', 'past its deadline')) else '[]'::jsonb end
         || case when s.at_risk then jsonb_build_array(jsonb_build_object('factor', 'deadline risk', 'points', s.p_risk,
                    'detail', 'likely to miss its deadline')) else '[]'::jsonb end
         || case when s.quiet then jsonb_build_array(jsonb_build_object('factor', 'quiet', 'points', s.p_quiet,
                    'detail', 'no update for days')) else '[]'::jsonb end
         || case when s.stage = 'recheck' then jsonb_build_array(jsonb_build_object('factor', 'not fixed', 'points', s.p_recheck,
                    'detail', 'the resident says it is not fixed')) else '[]'::jsonb end
    from scored s
   order by 9 desc, s.since
$$;

CREATE OR REPLACE FUNCTION public.reopen_report(p_report uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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

  -- 0140: the resident's "not fixed" has been answered
  update public.resolution_checks set handled_at = now(), handled_by = auth.uid()
   where report_id = p_report and fixed is false and handled_at is null;
end $$;
