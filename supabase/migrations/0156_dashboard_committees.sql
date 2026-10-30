-- =============================================================
-- SmartSumbong — 0156 The Dashboard's super admin module
--
-- Roles and pages, step 6 (docs/ROLES_AND_PAGES.md, "Dashboard"; decided
-- with Ace on 30 Oct 2026).
--
--   dashboard_committees()  the engine panel's "Needs me today" (what waits
--                           for a super admin: escalations to decide, cases
--                           handed up to place, tanods proposed for a
--                           committee; overdue; in no committee; open now)
--                           and "The committees" (open, overdue and filed
--                           this month for each, and "No committee yet")
--   dashboard_slice()       the cases behind one donut segment (a status
--                           bucket or a category), classified exactly as
--                           dashboard_metrics() counts them, for the box
--                           beside the donut
--   smart_chart_notes()     the brain buttons: what the engine notices about
--                           "Total reports received" or "Resolution
--                           efficiency" for the month, as facts the page
--                           words in English or Tagalog
--
-- All three run as the caller, so row level security decides what is
-- counted, as it does for dashboard_metrics().
-- =============================================================

set search_path = public, extensions;

create or replace function public.dashboard_committees(p_month_from timestamptz default date_trunc('month', now()))
returns jsonb
language sql stable set search_path = public, extensions as $$
  with open_cases as (
    select r.id, r.due_at, r.created_at, r.awaiting_placement, public.case_committee(r) as com
      from public.reports r
     where r.deleted_at is null and r.referred_to is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected')
  ),
  month_cases as (
    select public.case_committee(r) as com from public.reports r where r.deleted_at is null and r.created_at >= p_month_from
  )
  select jsonb_build_object(
    'needs_me', jsonb_build_object(
      'escalations', (select count(*) from public.escalation_requests e where e.status = 'pending'),
      'to_place',    (select count(*) from open_cases where awaiting_placement),
      'tanods',      (select count(*) from public.tanod_committees where status = 'proposed'),
      'overdue',     (select count(*) from open_cases where due_at < now()),
      'no_committee',(select count(*) from open_cases where com is null),
      'open',        (select count(*) from open_cases)),
    'committees', coalesce((
      select jsonb_agg(jsonb_build_object('key', c.key,
               'open',    (select count(*) from open_cases o where o.com = c.key),
               'overdue', (select count(*) from open_cases o where o.com = c.key and o.due_at < now()),
               'month',   (select count(*) from month_cases m where m.com = c.key)) order by c.sort, c.key)
        from public.committees c where c.active), '[]'::jsonb),
    'none', jsonb_build_object(
      'open',    (select count(*) from open_cases where com is null),
      'overdue', (select count(*) from open_cases where com is null and due_at < now()),
      'month',   (select count(*) from month_cases where com is null)))
$$;

create or replace function public.dashboard_slice(p_from timestamptz, p_to timestamptz, p_kind text, p_key text, p_limit integer default 40)
returns jsonb
language sql stable set search_path = public, extensions as $$
  with classified as (
    select r.id, r.tracking_id, r.subject, r.status, r.category, r.created_at, r.due_at, public.case_committee(r) as com,
           case
             when r.referred_to is not null then 'referred'
             when r.status in ('resolved', 'closed', 'archived') and r.due_at is not null
                  and coalesce(r.resolved_at, r.closed_at) > r.due_at then 'late'
             when r.status in ('resolved', 'closed', 'archived') then 'done'
             when r.due_at is not null and now() > r.due_at then 'overdue'
             when r.status = 'rejected' then 'rejected'
             else 'processing'
           end as bucket
      from public.reports r
     where r.deleted_at is null and r.created_at >= p_from and r.created_at < p_to
  ),
  picked as (
    select * from classified
     where case p_kind when 'status' then bucket = p_key when 'category' then category::text = p_key else false end
  )
  select jsonb_build_object(
    'total', (select count(*) from picked),
    'cases', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'tracking_id', p.tracking_id, 'subject', p.subject, 'status', p.status,
                                         'category', p.category, 'created_at', p.created_at, 'due_at', p.due_at, 'committee', p.com) order by p.created_at desc)
                         from (select * from picked order by created_at desc limit greatest(1, least(coalesce(p_limit, 40), 100))) p), '[]'::jsonb))
$$;

/**
 * What the engine notices about one chart for a month. 'received': how many were filed against the month before, the busiest
 * day, the weekday most come in, the kind and the place most of them are, and the days with none. 'efficiency': how many
 * finished in time, the typical hours taken against allowed, and the slowest and fastest kinds.
 */
create or replace function public.smart_chart_notes(p_chart text, p_from timestamptz, p_to timestamptz, p_category public.complaint_category default null)
returns jsonb
language sql stable set search_path = public, extensions as $$
  with m as (
    select r.*, (r.created_at at time zone 'Asia/Manila')::date as day, coalesce(r.resolved_at, r.closed_at) as finished_at
      from public.reports r
     where r.deleted_at is null and r.created_at >= p_from and r.created_at < p_to
       and (p_category is null or p_chart <> 'efficiency' or r.category = p_category)
  ),
  prev as (
    select count(*) as n from public.reports r
     where r.deleted_at is null and r.created_at >= p_from - (p_to - p_from) and r.created_at < p_from
  ),
  fin as (
    select m.category, extract(epoch from m.finished_at - m.created_at) / 3600 as taken,
           extract(epoch from m.due_at - m.created_at) / 3600 as allowed, m.finished_at <= m.due_at as on_time
      from m where m.finished_at is not null and m.due_at is not null
  )
  select case p_chart
    when 'received' then jsonb_build_object(
      'total', (select count(*) from m),
      'prev_total', (select n from prev),
      'busiest_day', (select jsonb_build_object('day', day, 'n', count(*)) from m group by day order by count(*) desc, day limit 1),
      'weekday', (select jsonb_build_object('dow', extract(isodow from day)::int, 'n', count(*)) from m group by 1 order by count(*) desc limit 1),
      'top_category', (select jsonb_build_object('category', category, 'n', count(*), 'share', round(100.0 * count(*) / greatest((select count(*) from m), 1)))
                         from m group by category order by count(*) desc limit 1),
      'top_place', (select jsonb_build_object('place', location_label, 'n', count(*)) from m where nullif(trim(location_label), '') is not null
                      group by location_label having count(*) >= 2 order by count(*) desc limit 1),
      'quiet_days', (select count(*) from generate_series((p_from at time zone 'Asia/Manila')::date,
                                                          least((p_to at time zone 'Asia/Manila')::date - 1, (now() at time zone 'Asia/Manila')::date), interval '1 day') d
                       where not exists (select 1 from m where m.day = d::date)))
    when 'efficiency' then jsonb_build_object(
      'finished', (select count(*) from fin),
      'on_time', (select count(*) from fin where on_time),
      'median_taken', (select round((percentile_cont(0.5) within group (order by taken))::numeric, 1) from fin),
      'median_allowed', (select round((percentile_cont(0.5) within group (order by allowed))::numeric, 1) from fin),
      'slowest', (select jsonb_build_object('category', category, 'taken', round(avg(taken)::numeric, 1), 'allowed', round(avg(allowed)::numeric, 1), 'n', count(*))
                    from fin group by category having count(*) >= 2 order by avg(taken / nullif(allowed, 0)) desc nulls last limit 1),
      'fastest', (select jsonb_build_object('category', category, 'taken', round(avg(taken)::numeric, 1), 'allowed', round(avg(allowed)::numeric, 1), 'n', count(*))
                    from fin group by category having count(*) >= 2 order by avg(taken / nullif(allowed, 0)) asc nulls last limit 1),
      'open_overdue', (select count(*) from m where m.finished_at is null and m.due_at < now() and m.status not in ('rejected')))
    else '{}'::jsonb end
$$;

-- ---------- Notifications by committee ----------

/** The committee of the case a notification is about (null: none yet, or not about a case): a column the list shows and filters by. */
create or replace function public.notification_committee(n public.notifications)
returns text
language sql stable security definer set search_path = public as $$
  select case when n.report_id is null then null else public._case_committee(n.report_id) end
$$;
revoke all on function public.notification_committee(public.notifications) from public, anon;
grant execute on function public.notification_committee(public.notifications) to authenticated;

-- System alerts (the portal down, a failed job, the engine's barangay-wide notes) are for the super admins only; a committee's
-- admins keep what is about their cases and about them.
create or replace function public._notifications_scope()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role text; v_tier text;
begin
  select role::text, coalesce(admin_tier, 'super') into v_role, v_tier from public.users where id = new.user_id;
  if v_role <> 'admin' or v_tier not in ('committee', 'moderator') then return new; end if;
  if new.report_id is null then
    if new.subject_user_id is null
       and (new.message like 'System check:%' or new.message like 'The admin portal %' or new.message like 'SMART:%') then
      return null;
    end if;
    return new;
  end if;
  if not coalesce((select public._user_sees_case(new.user_id, r.id, r.category, r.handler_id) from public.reports r where r.id = new.report_id), false) then
    return null;
  end if;
  return new;
end $$;

revoke all on function public.dashboard_committees(timestamptz), public.dashboard_slice(timestamptz, timestamptz, text, text, integer),
                       public.smart_chart_notes(text, timestamptz, timestamptz, public.complaint_category) from public, anon;
grant execute on function public.dashboard_committees(timestamptz), public.dashboard_slice(timestamptz, timestamptz, text, text, integer),
                          public.smart_chart_notes(text, timestamptz, timestamptz, public.complaint_category) to authenticated;
