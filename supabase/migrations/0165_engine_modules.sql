-- =============================================================
-- SmartSumbong — 0165 Each rung's SMART engine module
--
-- Ace, 4 Nov 2026 (Priority 2, part 2): every rung's pages are powered by its own module of the SMART engine, the way the
-- super admin's are powered by theirs. The engine's readings (deadline risk, spikes, recurring problems, quiet cases) were
-- for full viewers only; smart_module() gives each administrator the module for their rung, worked out from the same engine:
--
--   barangay   (super admin, captain)  every case; the decisions waiting on the super admins (a captain sees no decisions)
--   committee  (Kagawad)                the committee's cases only; the decisions waiting on the Kagawad: escalations to
--                                       approve, reroute questions (pick a tanod), cases forwarded to them, their staff's flags
--   staff      (moderator)              the committee's cases only; no decisions: their own cases, the ones nobody has taken
--
-- Every list is the engine's own reading, kept to the cases the person may open (_user_sees_case, the rule row level
-- security uses), and to the kinds of complaint their committee sees for the barangay-wide signals (spikes, recurring).
-- =============================================================

set search_path = public, extensions;

create or replace function public.smart_module()
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
set jit = off
as $$
declare
  v_me   uuid := auth.uid();
  v_tier text := public.admin_tier();
  v_full boolean := coalesce(public.is_full_viewer(), false);
  v_com  text;
  v_mod  text;
  v_cats text[];
  v jsonb;
begin
  if v_tier is null then raise exception 'Only an administrator has a SMART module.' using errcode = 'insufficient_privilege'; end if;
  select u.committee into v_com from public.users u where u.id = v_me;
  v_mod := case when v_full then 'barangay' when v_tier = 'committee' then 'committee' else 'staff' end;
  if not v_full then
    select coalesce(array_agg(cc.category::text order by cc.category), '{}') into v_cats
      from public.committee_categories cc join public.committees c on c.key = cc.committee and c.active
     where cc.committee = v_com;
  end if;

  with open_cases as (
    select r.id, r.tracking_id, r.category, r.status, r.due_at, r.handler_id, r.awaiting_placement, r.subject
      from public.reports r
     where r.deleted_at is null and r.referred_to is null
       and r.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and (v_full or public._user_sees_case(v_me, r.id, r.category, r.handler_id))
  ),
  waiting as (   -- validated or still in review, and no tanod on it: what the triage level is for
    select o.id, t.effective_level as lvl from open_cases o join public.report_triage t on t.report_id = o.id
     where o.status in ('pending_review', 'validated')
       and not exists (select 1 from public.dispatches d where d.report_id = o.id and d.state in ('assigned', 'accepted'))
  ),
  members as (   -- the tanods this module watches: every active tanod, or the committee's approved ones
    select u.id, u.duty_status,
           exists (select 1 from public.dispatches d where d.tanod_id = u.id and d.state in ('assigned', 'accepted')) as busy
      from public.users u
     where u.role = 'tanod' and u.removed_at is null and u.verification_status = 'verified'
       and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false)
       and (v_full or exists (select 1 from public.tanod_committees tc where tc.tanod_id = u.id and tc.committee = v_com and tc.status = 'approved'))
  )
  select jsonb_build_object(
    'module', v_mod,
    'committee', case when v_full then null else v_com end,
    'categories', case when v_full then null else to_jsonb(v_cats) end,
    'counts', jsonb_build_object(
      'open',           (select count(*) from open_cases),
      'urgent_waiting', (select count(*) from waiting where lvl = 'urgent'),
      'high_waiting',   (select count(*) from waiting where lvl = 'high'),
      'overdue',        (select count(*) from open_cases where due_at < now()),
      'due_24h',        (select count(*) from open_cases where due_at >= now() and due_at < now() + interval '24 hours'),
      'untaken',        (select count(*) from open_cases where handler_id is null and not awaiting_placement),
      'mine',           (select count(*) from open_cases where handler_id = v_me)),
    'decisions', case
      when v_mod = 'staff' or v_tier = 'captain' then null
      else jsonb_build_object(
        'escalations', (select count(*) from public.escalation_requests e join open_cases o on o.id = e.report_id where e.status = 'pending'),
        'reroute',     (select count(*) from public.reroute_questions q where q.state = 'open' and (v_full or q.committee = v_com)),
        'forwarded',   (select count(*) from public.notifications n where n.user_id = v_me and n.kind = 'case_forwarded' and not n.is_read),
        'flags',       (select count(*) from public.case_forward_flags f where (v_full and f.to_super) or (not v_full and f.from_committee = v_com)),
        'to_place',    case when v_full then (select count(*) from public.reports r where r.awaiting_placement and r.deleted_at is null) end,
        'tanods_proposed', case when v_full then (select count(*) from public.tanod_committees where status = 'proposed') end)
    end,
    'deadline_risk', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.hours_left) from (
        select d.report_id, d.tracking_id, d.due_at, round(d.hours_left, 1) as hours_left, d.risk, d.reasons
          from public._smart_deadline_risk() d join open_cases o on o.id = d.report_id
         order by d.hours_left limit 8) x), '[]'::jsonb),
    'quiet', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.days_quiet desc) from (
        select s.report_id, s.tracking_id, s.status, s.days_quiet, s.last_activity
          from public._smart_stuck() s join open_cases o on o.id = s.report_id
         order by s.days_quiet desc limit 8) x), '[]'::jsonb),
    'spikes', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.times_usual desc) from (
        select s.category, s.this_week, s.usual, s.times_usual, s.place
          from public._smart_spikes() s where v_full or s.category::text = any (v_cats)) x), '[]'::jsonb),
    'patterns', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.still_open desc, x.reports desc) from (
        select p.pattern_key, p.category, p.reports, p.weeks, p.residents, p.still_open, p.hazard, p.last_at, p.tracking_ids[1:3] as tracking_ids
          from public._smart_patterns(null) p where v_full or p.category::text = any (v_cats)
         order by p.still_open desc, p.reports desc limit 6) x), '[]'::jsonb),
    'tanods', jsonb_build_object(
      'total',    (select count(*) from members),
      'on_duty',  (select count(*) from members where duty_status = 'on_duty' and not busy),
      'busy',     (select count(*) from members where busy),
      'lunch',    (select count(*) from members where duty_status = 'lunch'),
      'break',    (select count(*) from members where duty_status = 'break'),
      'offline',  (select count(*) from members where coalesce(duty_status, 'offline') = 'offline' and not busy)),
    'at', now())
  into v;
  return v;
end $$;
revoke all on function public.smart_module() from public, anon;
grant execute on function public.smart_module() to authenticated;
comment on function public.smart_module() is '0165: the SMART engine module for the caller''s rung: barangay (super admin, captain), committee (Kagawad), staff. Counts, the decisions waiting on them, deadline risk, quiet cases, spikes, recurring problems and tanods, kept to what they may see.';
