-- DRAFT: not applied until Ace says apply 0190
-- 0190_smart_module_set_based: smart_module() reads the visible-case set once instead of the case rule once per case
--
-- smart_module() (the SMART panel of every administrator, called on pages) ran the case rule once per open case (2 call sites; 3.4 s for a Kagawad at 20,000 cases).
-- 0189 added the set helper _my_scoped_case_ids() that the policies read once per query; this reads the same set. No other behaviour changes: the document it returns is the same
-- for every rung (proved by test 70 against the old body on the exhaustive fixture, and at 250x by tools/sweep/exp_smart_module.py).
--
-- UNDO (plain language): supabase/drafts/0190_undo.sql restores the previous body of smart_module() (create or replace); nothing else changed.
-- Proof: supabase/drafts/tests/0190_smart_module_set_based.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_smart_module_set.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

create or replace function public.smart_module()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
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
       and (v_full or r.id in (select s.id from public._my_scoped_case_ids() s(id)))
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
      'mine',           (select count(*) from open_cases where handler_id = v_me),
      'to_accept',      (select count(*) from public.reports r where r.assigned_to = v_me and r.deleted_at is null)),
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
          from public._snap_deadline_risk() d join open_cases o on o.id = d.report_id
         order by d.hours_left limit 8) x), '[]'::jsonb),
    'quiet', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.days_quiet desc) from (
        select s.report_id, s.tracking_id, s.status, s.days_quiet, s.last_activity
          from public._snap_stuck() s join open_cases o on o.id = s.report_id
         order by s.days_quiet desc limit 8) x), '[]'::jsonb),
    'spikes', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.times_usual desc) from (
        select s.category, s.this_week, s.usual, s.times_usual, s.place
          from public._snap_spikes() s where v_full or s.category::text = any (v_cats)) x), '[]'::jsonb),
    'patterns', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.still_open desc, x.reports desc) from (
        select p.pattern_key, p.category, p.reports, p.weeks, p.residents, p.still_open, p.hazard, p.last_at, case when v_tier = 'moderator' then array(select r.tracking_id from public.reports r where r.tracking_id = any (p.tracking_ids[1:3]) and r.id in (select s.id from public._my_scoped_case_ids() s(id))) else p.tracking_ids[1:3] end as tracking_ids
          from public._snap_patterns() p where v_full or p.category::text = any (v_cats)
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
end $function$;

-- UNDO SQL (not run; for the person applying this):
-- -- see supabase/drafts/0190_undo.sql
