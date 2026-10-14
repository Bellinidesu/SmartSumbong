-- 0131: three briefings a day.
-- Ace's pick for Notifications (14 Oct 2026): the engine briefs the administrators in the morning, the afternoon and at
-- night, not only at 07:00. The morning text is the one already sent (0127); the afternoon reads the day so far and the
-- night reads it back. Each is one short notification to every administrator, and the portal's Notifications page shows
-- the same numbers live.

create or replace function public._smart_briefing_text(p_period text)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_day   date := (now() at time zone 'Asia/Manila')::date;
  v_start timestamptz := ((now() at time zone 'Asia/Manila')::date::timestamp at time zone 'Asia/Manila');
  v_since timestamptz := ((now() at time zone 'Asia/Manila')::date::timestamp + interval '6 hours') at time zone 'Asia/Manila';
  v_open integer; v_overdue integer; v_tmrw integer; v_in_since integer; v_out_since integer; v_in_day integer; v_out_day integer;
  v_urgent integer; v_high integer; v_risk integer;
begin
  if p_period = 'morning' then
    return public._smart_digest_text();
  elsif p_period not in ('afternoon', 'night') then
    raise exception 'Unknown briefing %', p_period using errcode = 'invalid_parameter_value';
  end if;

  select count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')),
         count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation') and r.due_at < now()),
         count(*) filter (where r.status in ('pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation')
                            and r.due_at >= v_start + interval '1 day' and r.due_at < v_start + interval '2 days'),
         count(*) filter (where r.created_at >= v_since), count(*) filter (where r.resolved_at >= v_since),
         count(*) filter (where r.created_at >= v_start), count(*) filter (where r.resolved_at >= v_start)
    into v_open, v_overdue, v_tmrw, v_in_since, v_out_since, v_in_day, v_out_day
    from public.reports r where r.deleted_at is null;
  select count(*) filter (where t.effective_level = 'urgent'), count(*) filter (where t.effective_level = 'high')
    into v_urgent, v_high
    from public.report_triage t join public.reports r on r.id = t.report_id
   where r.deleted_at is null and r.status in ('pending_review', 'validated')
     and not exists (select 1 from public.dispatches d where d.report_id = r.id and d.state in ('assigned', 'accepted'));
  select count(*) into v_risk from public._smart_deadline_risk() where risk = 'high';

  if p_period = 'afternoon' then
    return format('SMART afternoon check, %s. Since 6 AM: %s came in, %s resolved. Still waiting for a tanod: %s urgent, %s high. Overdue: %s. Likely to miss the deadline: %s.',
                  to_char(v_day, 'Mon DD'), v_in_since, v_out_since, v_urgent, v_high, v_overdue, v_risk);
  end if;
  return format('SMART day review, %s. Today: %s filed, %s resolved. Staying open overnight: %s. Due tomorrow: %s. Overdue: %s.',
                to_char(v_day, 'Mon DD'), v_in_day, v_out_day, v_open, v_tmrw, v_overdue);
end $$;

revoke all on function public._smart_briefing_text(text) from public, anon, authenticated;

create or replace function public.smart_digest_send(p_period text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if (select digest_enabled from public.smart_rules where id = 1) then
    perform public._notify_admins(public._smart_briefing_text(p_period));
  end if;
end $$;

revoke all on function public.smart_digest_send(text) from public, anon, authenticated;

-- 14:00 in Manila is 06:00 UTC; 20:00 is 12:00 UTC. (The morning one stays at 07:00, 0127.)
select cron.schedule('smart-afternoon-digest', '0 6 * * *', $$ select public.smart_digest_send('afternoon') $$);
select cron.schedule('smart-night-digest', '0 12 * * *', $$ select public.smart_digest_send('night') $$);
