-- 0128: SMART learns words, watches quiet cases, reads the week, keeps
-- score, and routes the system's dispatches (10 Oct 2026).
--
-- Still rules and counts, reasons shown (docs/SMART.md, sections 16-20):
--
--   new words      words residents keep using that SMART does not know yet,
--                  with the kind of complaint they come with and a likely
--                  spelling; an admin teaches them (or dismisses them) in
--                  one step. The rules grow from real reports, and a person
--                  approves every word.
--   quiet cases    open cases with no update of any kind for stuck_days,
--                  even when no deadline has passed.
--   the week       when each kind of complaint comes in: weekday and hour,
--                  against its own average, for patrol planning.
--   scorecard      per kind, the share resolved within its deadline or SLA
--                  target this month, against last month.
--   routing        when the system itself dispatches (a reroute back to the
--                  system, the sweeps), it takes SMART's first choice among
--                  the same available tanods instead of only the nearest.

set search_path = public, extensions;

alter table public.smart_rules
  add column smart_routing boolean  not null default true,
  add column stuck_days    smallint not null default 3 check (stuck_days between 1 and 30),
  add column word_min_reports smallint not null default 3 check (word_min_reports >= 2);

-- ---------- 16. new words ---------------------------------------------------------------

create table public.smart_word_decisions (
  word       text primary key check (word = lower(word)),
  decision   text not null check (decision in ('learned', 'dismissed')),
  detail     text,
  decided_by uuid references public.users (id) on delete set null,
  decided_at timestamptz not null default now()
);
create index smart_word_decisions_by_idx on public.smart_word_decisions (decided_by);
alter table public.smart_word_decisions enable row level security;
create policy smart_word_decisions_admin_read on public.smart_word_decisions for select using ((select public.is_admin()));
comment on table public.smart_word_decisions is
  '0128: words an admin taught SMART or dismissed, so they are not suggested again.';

/** Little words that never carry meaning on their own, and place words
    every report has. */
create or replace function public._smart_common_words()
returns text[]
language sql
immutable
as $$
  select array['ang','ng','mga','sa','na','at','ay','si','ni','kay','ko','mo','niya','namin','natin','nila','nyo','ninyo',
    'ito','iyan','iyon','yan','yun','dito','diyan','doon','may','mayroon','meron','wala','walang','hindi','oo','po','opo',
    'din','rin','lang','lamang','pa','naman','nang','kung','kasi','dahil','pero','para','yung','iyong','siya','sila','kami',
    'tayo','kayo','ako','ikaw','ka','nasa','mula','hanggang','tapos','saka','ba','nga','daw','raw','talaga','sobrang',
    'sobra','napaka','araw','gabi','umaga','tanghali','hapon','ngayon','kahapon','kanina','bukas','lagi','palagi','minsan',
    'tuwing','gabi-gabi','paki','pakiusap','sana','agad','na-','ung','nmn','nman','kc','kse','pls','please',
    'the','and','for','with','this','that','there','here','from','have','has','been','were','they','their','them','our',
    'your','also','very','just','near','into','about','again','already','still','because','some','every','what','when',
    'kanto','kalye','bahay','harap','likod','tabi','gilid','loob','labas','purok','barangay','brgy','block','lot','phase',
    'street','avenue','corner','road','house','area','lugar','kapitbahay','neighbor','neighbors','tao','mga tao']
$$;

/** Words from the last p_days of reports that SMART does not know: not a
    rule word, not in the word list, not reachable by grammar, not common,
    not decided before; used in at least word_min_reports reports. With
    the kind they mostly come with, and a known word one or two letters
    away (likely a spelling). */
create or replace function public._smart_word_candidates(p_days integer default 30)
returns table (word text, reports integer, mostly_category public.complaint_category, share numeric,
               likely_spelling_of text, example text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_vocab text[] := public._smart_vocab();
  v_common text[] := public._smart_common_words();
  k public.smart_rules%rowtype;
begin
  select * into k from public.smart_rules where id = 1;
  return query
  with toks as (
    select distinct r.id, r.category, t.w, r.subject
      from public.reports r,
           lateral unnest(public._smart_tokens(r.subject || ' ' || r.description)) as t(w)
     where r.deleted_at is null and r.created_at > now() - make_interval(days => p_days)
       and length(t.w) >= 4 and t.w !~ '[0-9|]'
  ), counted as (
    select t.w, count(distinct t.id)::integer as n,
           mode() within group (order by t.category) as cat,
           min(t.subject) as ex
      from toks t
     where not (t.w = any (v_vocab)) and not (t.w = any (v_common))
       and not exists (select 1 from public.smart_lexicon l where l.variant = t.w)
       and not exists (select 1 from public.smart_word_decisions d where d.word = t.w)
     group by t.w
    having count(distinct t.id) >= k.word_min_reports
  ), unknown as (
    select c.* from counted c
     where not exists (select 1 from public._smart_stem(c.w, v_vocab) s where s.root is not null)
  )
  select u.w, u.n, u.cat,
         round(100.0 * (select count(distinct t.id) from toks t where t.w = u.w and t.category = u.cat) / u.n, 0),
         (select v from unnest(v_vocab) v where length(v) >= 4 and levenshtein(u.w, v) between 1 and 2
           order by levenshtein(u.w, v), v limit 1),
         u.ex
    from unknown u
   order by u.n desc, u.w
   limit 50;
end $$;

revoke all on function public._smart_word_candidates(integer) from public, anon, authenticated;

create or replace function public.smart_word_suggestions(p_days integer default 30)
returns table (word text, reports integer, mostly_category public.complaint_category, share numeric,
               likely_spelling_of text, example text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can teach SMART words.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_word_candidates(p_days);
end $$;

revoke all on function public.smart_word_suggestions(integer) from public, anon;
grant execute on function public.smart_word_suggestions(integer) to authenticated;

/** Admins: teach SMART a word.
      p_as 'spelling' | 'synonym' | 'form'  ->  the word list: p_word is read as p_target
      p_as 'category'                        ->  a word of the kind p_target (category hint)
      p_as 'urgent'                          ->  a word of the urgent-word group labelled p_target
      p_as 'dismiss'                         ->  not suggested again
    Open reports are scored again. */
create or replace function public.smart_teach_word(p_word text, p_as text, p_target text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_word text := lower(trim(p_word));
  v_target text := lower(trim(coalesce(p_target, '')));
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can teach SMART words.' using errcode = 'insufficient_privilege';
  end if;
  if v_word !~ '^[a-zñ]{2,30}$' then
    raise exception 'One word, letters only.' using errcode = 'check_violation';
  end if;
  if p_as in ('spelling', 'synonym', 'form') then
    if v_target !~ '^[a-zñ]{2,30}$' then raise exception 'Say which known word it means.' using errcode = 'check_violation'; end if;
    insert into public.smart_lexicon (variant, root, kind, note) values (v_word, v_target, p_as, 'taught from reports')
    on conflict (variant) do update set root = excluded.root, kind = excluded.kind;
  elsif p_as = 'category' then
    if not exists (select 1 from public.smart_rules k where k.id = 1 and k.category_words ? v_target) then
      raise exception 'No such kind of complaint: %', p_target using errcode = 'check_violation';
    end if;
    update public.smart_rules
       set category_words = jsonb_set(category_words, array[v_target], (category_words -> v_target) || to_jsonb(v_word))
     where id = 1 and not (category_words -> v_target) ? v_word;
  elsif p_as = 'urgent' then
    if not exists (select 1 from public.smart_rules k, jsonb_array_elements(k.keyword_groups) g
                    where k.id = 1 and lower(g ->> 'label') = v_target) then
      raise exception 'No such urgent-word group: %', p_target using errcode = 'check_violation';
    end if;
    update public.smart_rules k
       set keyword_groups = (select jsonb_agg(case when lower(g ->> 'label') = v_target and not (g -> 'words') ? v_word
                                                   then jsonb_set(g, '{words}', (g -> 'words') || to_jsonb(v_word)) else g end
                                              order by o)
                               from jsonb_array_elements(k.keyword_groups) with ordinality as x(g, o))
     where id = 1;
  elsif p_as <> 'dismiss' then
    raise exception 'Teach it as spelling, synonym, form, category, urgent, or dismiss it.' using errcode = 'check_violation';
  end if;

  insert into public.smart_word_decisions (word, decision, detail, decided_by)
  values (v_word, case when p_as = 'dismiss' then 'dismissed' else 'learned' end,
          case when p_as = 'dismiss' then null else p_as || coalesce(': ' || nullif(v_target, ''), '') end, auth.uid())
  on conflict (word) do update set decision = excluded.decision, detail = excluded.detail,
                                   decided_by = excluded.decided_by, decided_at = now();
  if p_as <> 'dismiss' then
    perform public.smart_triage(id) from public.reports
     where deleted_at is null and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled');
  end if;
end $$;

revoke all on function public.smart_teach_word(text, text, text) from public, anon;
grant execute on function public.smart_teach_word(text, text, text) to authenticated;

-- ---------- 17. quiet cases ------------------------------------------------------------------

/** Open cases with no update of any kind (status, tanod step or note,
    message, dispatch, detail request) for stuck_days. */
create or replace function public._smart_stuck()
returns table (report_id uuid, tracking_id text, status public.report_status, days_quiet integer,
               last_activity text, last_activity_at timestamptz)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with k as (select stuck_days from public.smart_rules where id = 1),
       open_cases as (
         select r.id, r.tracking_id, r.status, r.created_at
           from public.reports r
          where r.deleted_at is null
            and r.status in ('validated', 'assigned', 'in_progress', 'offline_investigation')
       ),
       last_touch as (
         select o.*, x.what, x.at
           from open_cases o
           cross join lateral (
             select what, at from (
               select 'filed' as what, o.created_at as at
               union all select 'status: ' || l.new_status::text, l.created_at from public.status_logs l where l.report_id = o.id
               union all select 'tanod update', u.created_at from public.dispatch_updates u
                           join public.dispatches d on d.id = u.dispatch_id where d.report_id = o.id
               union all select 'dispatch', coalesce(d.accepted_at, d.assigned_at) from public.dispatches d where d.report_id = o.id
               union all select 'message', m.created_at from public.report_messages m where m.report_id = o.id
               union all select 'detail request', coalesce(q.responded_at, q.requested_at) from public.detail_requests q where q.report_id = o.id
             ) a order by at desc limit 1) x
       )
  select t.id, t.tracking_id, t.status, floor(extract(epoch from now() - t.at) / 86400)::integer, t.what, t.at
    from last_touch t, k
   where t.at < now() - make_interval(days => k.stuck_days)
   order by t.at
$$;

revoke all on function public._smart_stuck() from public, anon, authenticated;

create or replace function public.smart_stuck_cases()
returns table (report_id uuid, tracking_id text, status public.report_status, days_quiet integer,
               last_activity text, last_activity_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see quiet cases.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_stuck();
end $$;

revoke all on function public.smart_stuck_cases() from public, anon;
grant execute on function public.smart_stuck_cases() to authenticated;

-- ---------- 18. the week --------------------------------------------------------------------

/** When each kind of complaint comes in, over the last p_days: weekday and
    3-hour block (Manila), where there were at least 5 reports and at least
    twice the kind's average block. With the most common place label. */
create or replace function public.smart_time_patterns(p_days integer default 90,
                                                      p_category public.complaint_category default null)
returns table (category public.complaint_category, weekday text, hours text, reports integer,
               times_usual numeric, place text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see weekly patterns.' using errcode = 'insufficient_privilege';
  end if;
  return query
  with base as (
    select r.category, r.location_label,
           extract(isodow from r.created_at at time zone 'Asia/Manila')::integer as dow,
           (extract(hour from r.created_at at time zone 'Asia/Manila')::integer / 3) as blk
      from public.reports r
     where r.deleted_at is null and r.status not in ('rejected', 'cancelled')
       and r.created_at > now() - make_interval(days => p_days)
       and (p_category is null or r.category = p_category)
  ), cells as (
    select b.category as cat, b.dow, b.blk, count(*)::integer as n,
           mode() within group (order by b.location_label) as place
      from base b group by b.category, b.dow, b.blk
  ), avgs as (
    select b.category as cat, count(*)::numeric / 56 as per_cell from base b group by b.category
  )
  select c.cat,
         (array['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[c.dow],
         lpad((c.blk * 3)::text, 2, '0') || ':00-' || lpad(((c.blk * 3 + 3) % 24)::text, 2, '0') || ':00',
         c.n, round(c.n / a.per_cell, 1), c.place
    from cells c join avgs a on a.cat = c.cat
   where c.n >= 5 and c.n >= 2 * a.per_cell
   order by c.n / a.per_cell desc, c.n desc;
end $$;

revoke all on function public.smart_time_patterns(integer, public.complaint_category) from public, anon;
grant execute on function public.smart_time_patterns(integer, public.complaint_category) to authenticated;

-- ---------- 19. scorecard -------------------------------------------------------------------

/** Per kind: cases finished in the month (Manila) of p_month, how many
    within their deadline (or, without one, the SLA target), the share, and
    the same for the month before; plus open cases already overdue now. */
create or replace function public.smart_sla_scorecard(p_month date default null)
returns table (category public.complaint_category, finished integer, on_time integer, on_time_pct numeric,
               last_month_pct numeric, change_pct numeric, overdue_now integer)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Manila')::date))::date;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see the scorecard.' using errcode = 'insufficient_privilege';
  end if;
  return query
  with fin as (
    select r.category,
           (coalesce(r.resolved_at, r.closed_at) at time zone 'Asia/Manila')::date as day,
           coalesce(r.resolved_at, r.closed_at) <= coalesce(r.due_at, r.created_at + make_interval(hours => p.resolution_hours)) as ok
      from public.reports r
      left join public.sla_policies p on p.category = r.category
     where r.deleted_at is null and coalesce(r.resolved_at, r.closed_at) is not null
       and r.referred_to is null
       and coalesce(r.resolved_at, r.closed_at) >= (v_from - interval '1 month')::timestamp at time zone 'Asia/Manila'
       and coalesce(r.resolved_at, r.closed_at) <  (v_from + interval '1 month')::timestamp at time zone 'Asia/Manila'
  ), m as (
    select f.category,
           count(*) filter (where f.day >= v_from)::integer as n,
           count(*) filter (where f.day >= v_from and f.ok)::integer as ok_n,
           count(*) filter (where f.day < v_from)::integer as n_prev,
           count(*) filter (where f.day < v_from and f.ok)::integer as ok_prev
      from fin f group by f.category
  ), od as (
    select r.category, count(*)::integer as n
      from public.reports r
     where r.deleted_at is null and r.due_at < now() and r.resolved_at is null
       and r.status in ('validated', 'assigned', 'in_progress', 'offline_investigation')
     group by r.category
  )
  select c.cat, coalesce(m.n, 0), coalesce(m.ok_n, 0),
         case when m.n > 0 then round(100.0 * m.ok_n / m.n, 0) end,
         case when m.n_prev > 0 then round(100.0 * m.ok_prev / m.n_prev, 0) end,
         case when m.n > 0 and m.n_prev > 0 then round(100.0 * m.ok_n / m.n - 100.0 * m.ok_prev / m.n_prev, 0) end,
         coalesce(od.n, 0)
    from (select unnest(enum_range(null::public.complaint_category)) as cat) c
    left join m on m.category = c.cat
    left join od on od.category = c.cat
   where coalesce(m.n, 0) + coalesce(m.n_prev, 0) + coalesce(od.n, 0) > 0
   order by c.cat;
end $$;

revoke all on function public.smart_sla_scorecard(date) from public, anon;
grant execute on function public.smart_sla_scorecard(date) to authenticated;

-- ---------- 20. routing the system's own dispatches -----------------------------------------

create or replace function public._smart_tanod_ranking(p_report uuid)
returns table (tanod_id uuid, full_name text, score integer, metres integer,
               active_jobs integer, closed_nearby integer, location_fresh boolean, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  return query
  with c as (
    select n.tanod_id, n.full_name, n.metres,
           (select count(*)::integer from public.dispatches d
             where d.tanod_id = n.tanod_id and d.state in ('assigned', 'accepted')) as active,
           (select count(*)::integer from public.dispatches d
              join public.reports o on o.id = d.report_id
             where d.tanod_id = n.tanod_id and d.state = 'resolved'
               and d.resolved_at > now() - interval '90 days'
               and st_dwithin(o.geom, (select geom from public.reports where id = p_report), 300)) as nearby,
           public.location_is_fresh(u.last_location_at) as fresh,
           u.last_location_at as fix_at
      from public.nearest_available_tanod(p_report) n
      join public.users u on u.id = n.tanod_id
  ), s as (
    select c.*,
           case when c.metres is null then 50 else least(round(c.metres / 20)::integer, 50) end as dist_pen,
           c.active * 15 as load_pen,
           least(c.nearby * 5, 20) as area_bonus,
           case when c.fresh then 0 else 10 end as stale_pen
      from c
  )
  select s.tanod_id, s.full_name,
         greatest(0, 100 - s.dist_pen - s.load_pen + s.area_bonus - s.stale_pen),
         round(s.metres)::integer, s.active, s.nearby, s.fresh,
         jsonb_build_array(
           jsonb_build_object('factor', 'distance',
             'detail', case when s.metres is null then 'no location yet' else round(s.metres) || ' m away' end,
             'points', -s.dist_pen),
           jsonb_build_object('factor', 'workload', 'detail', s.active || ' job(s) in hand', 'points', -s.load_pen),
           jsonb_build_object('factor', 'knows the area', 'detail', s.nearby || ' case(s) closed within 300 m, last 90 days',
             'points', s.area_bonus),
           -- One reading at a time, never tracking (live tracking was removed
           -- in 0072): the age of the tanod's last reading.
           jsonb_build_object('factor', 'location', 'detail', case
               when s.fix_at is null then 'no location yet'
               when s.fix_at > now() - interval '2 minutes' then 'last reading just now'
               when s.fix_at > now() - interval '2 hours'
                 then 'last reading ' || floor(extract(epoch from now() - s.fix_at) / 60) || ' min ago'
               else 'last reading over 2 hours ago' end,
             'points', -s.stale_pen))
    from s
   order by 3 desc, s.metres nulls last;
end $$;


revoke all on function public._smart_tanod_ranking(uuid) from public, anon, authenticated;

/** Admins: the ranking (see _smart_tanod_ranking). */
create or replace function public.smart_tanod_ranking(p_report uuid)
returns table (tanod_id uuid, full_name text, score integer, metres integer,
               active_jobs integer, closed_nearby integer, location_fresh boolean, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can rank tanods.' using errcode = 'insufficient_privilege';
  end if;
  return query select * from public._smart_tanod_ranking(p_report);
end $$;

create or replace function public.auto_dispatch(p_report uuid)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
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

  update public.reports set status = 'assigned' where id = p_report;

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


-- ---------- the watcher and the digest, with quiet cases and new words ----------------------

create or replace function public.smart_watch()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  k public.smart_rules%rowtype;
  r record;
  v_sent integer := 0;
  v_key text;
begin
  select * into k from public.smart_rules where id = 1;

  -- storm mode ends on its own
  if k.storm_mode and k.storm_until is not null and k.storm_until < now() then
    update public.smart_rules set storm_mode = false, storm_until = null, storm_reason = null where id = 1;
    perform public.smart_triage(id) from public.reports
     where deleted_at is null and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled');
    perform public._notify_admins('SMART: storm mode has ended; open reports re-scored.');
    v_sent := v_sent + 1;
    select * into k from public.smart_rules where id = 1;
  end if;

  -- urgent and high reports waiting for a tanod
  for r in
    select t.report_id, t.effective_level, t.score, rp.tracking_id, rp.created_at
      from public.report_triage t
      join public.reports rp on rp.id = t.report_id
     where t.alerted_at is null
       and t.effective_level in ('urgent', 'high')
       and rp.deleted_at is null
       and rp.status in ('pending_review', 'validated')
       and rp.created_at < now() - make_interval(mins => case t.effective_level
             when 'urgent' then k.urgent_dispatch_minutes else k.high_dispatch_minutes end)
       and not exists (select 1 from public.dispatches d
                        where d.report_id = rp.id and d.state in ('assigned', 'accepted'))
     order by t.score desc
     limit 50
  loop
    insert into public.notifications (user_id, kind, report_id, message)
    select a.id, 'sla_warning', r.report_id,
           format('SMART: %s report %s has waited %s min without a tanod.',
                  initcap(r.effective_level), r.tracking_id,
                  floor(extract(epoch from now() - r.created_at) / 60)::integer)
      from public.users a
     where a.role = 'admin' and not coalesce(a.is_suspended, false);
    update public.report_triage set alerted_at = now() where report_id = r.report_id;
    v_sent := v_sent + 1;
  end loop;

  -- cases likely to miss their deadline (high risk), told once
  for r in
    select d.* from public._smart_deadline_risk() d
     where d.risk = 'high'
       and not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = 'deadline:' || d.report_id)
     limit 50
  loop
    insert into public.notifications (user_id, kind, report_id, message)
    select a.id, 'sla_warning', r.report_id,
           format('SMART: %s will probably miss its deadline (%s h left; such cases usually take %s h).',
                  r.tracking_id, r.hours_left, r.typical_hours)
      from public.users a
     where a.role = 'admin' and not coalesce(a.is_suspended, false);
    insert into public.smart_patterns_seen (pattern_key, reports) values ('deadline:' || r.report_id, 1);
    v_sent := v_sent + 1;
  end loop;

  -- recurring problems not seen before
  for r in select p.* from public._smart_patterns(null) p loop
    if not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = r.pattern_key) then
      insert into public.smart_patterns_seen (pattern_key, reports) values (r.pattern_key, r.reports);
      perform public._notify_admins(format(
        'SMART: recurring problem. %s reports of %s near the same spot over %s weeks (%s still open). Latest: %s.',
        r.reports, replace(r.category::text, '_', ' '), r.weeks, r.still_open, r.tracking_ids[1]));
      v_sent := v_sent + 1;
    else
      update public.smart_patterns_seen set last_seen_at = now(), reports = r.reports where pattern_key = r.pattern_key;
    end if;
  end loop;

  -- spikes, once per kind per week
  for r in select s.* from public._smart_spikes() s loop
    v_key := 'spike:' || r.category || ':' || to_char(now() at time zone 'Asia/Manila', 'IYYY-IW');
    if not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = v_key) then
      insert into public.smart_patterns_seen (pattern_key, reports) values (v_key, r.this_week);
      perform public._notify_admins(format(
        'SMART: spike. %s %s reports in the last 7 days, %s times the usual week (%s)%s.',
        r.this_week, replace(r.category::text, '_', ' '), r.times_usual, r.usual,
        coalesce('; mostly ' || r.place, '')));
      v_sent := v_sent + 1;
    end if;
  end loop;

  -- cases nobody has touched for stuck_days, once per quiet spell
  for r in select s.* from public._smart_stuck() s loop
    v_key := 'stuck:' || r.report_id || ':' || to_char(r.last_activity_at, 'YYYYMMDDHH24MISS');
    if not exists (select 1 from public.smart_patterns_seen s where s.pattern_key = v_key) then
      insert into public.smart_patterns_seen (pattern_key, reports) values (v_key, 1);
      insert into public.notifications (user_id, kind, report_id, message)
      select a.id, 'sla_warning', r.report_id,
             format('SMART: %s has had no update for %s days (last: %s).', r.tracking_id, r.days_quiet, r.last_activity)
        from public.users a
       where a.role = 'admin' and not coalesce(a.is_suspended, false);
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_sent;
end $$;

create or replace function public._smart_digest_text()
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_open integer; v_urgent integer; v_high integer; v_overdue integer; v_today integer;
  v_risk integer; v_new integer; v_rec integer; v_storm boolean; v_stuck integer; v_words integer;
  v_spike record;
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v text;
begin
  select count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
         count(*) filter (where r.due_at < now() and r.resolved_at is null
                            and r.status in ('validated', 'assigned', 'in_progress', 'offline_investigation')),
         count(*) filter (where (r.due_at at time zone 'Asia/Manila')::date = v_day and r.resolved_at is null),
         count(*) filter (where (r.created_at at time zone 'Asia/Manila')::date = v_day - 1)
    into v_open, v_overdue, v_today, v_new
    from public.reports r where r.deleted_at is null;
  select count(*) filter (where t.effective_level = 'urgent'), count(*) filter (where t.effective_level = 'high')
    into v_urgent, v_high
    from public.report_triage t join public.reports r on r.id = t.report_id
   where r.deleted_at is null and r.status in ('pending_review', 'validated')
     and not exists (select 1 from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'));
  select count(*) into v_risk from public._smart_deadline_risk() where risk = 'high';
  select count(*) into v_rec from public._smart_patterns(null) where still_open > 0;
  select * into v_spike from public._smart_spikes() limit 1;
  select storm_mode into v_storm from public.smart_rules where id = 1;
  select count(*) into v_stuck from public._smart_stuck();
  select count(*) into v_words from public._smart_word_candidates(30);

  v := format('SMART morning digest, %s. Open: %s. Waiting for a tanod: %s urgent, %s high. Overdue: %s. Due today: %s. '
              || 'Likely to miss the deadline: %s. Filed yesterday: %s. Recurring problems still open: %s.',
              to_char(v_day, 'Mon DD'), v_open, v_urgent, v_high, v_overdue, v_today, v_risk, v_new, v_rec);
  if v_spike.category is not null then
    v := v || format(' Spike: %s, %s this week (usually %s)%s.', replace(v_spike.category::text, '_', ' '),
                     v_spike.this_week, v_spike.usual, coalesce(', mostly ' || v_spike.place, ''));
  end if;
  if v_stuck > 0 then v := v || format(' No update for %s+ days: %s.', (select stuck_days from public.smart_rules where id = 1), v_stuck); end if;
  if v_words > 0 then v := v || format(' New words for SMART to learn: %s (Settings, SMART).', v_words); end if;
  if v_storm then v := v || ' Storm mode is on.'; end if;
  return v;
end $$;


-- ---------- no JIT for the new SMART functions (see 0127) -------------------------------------
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'public'::regnamespace and (p.proname ~ '^_?smart_' or p.proname = 'auto_dispatch')
  loop
    execute format('alter function %s set jit = off', f);
  end loop;
end $$;
