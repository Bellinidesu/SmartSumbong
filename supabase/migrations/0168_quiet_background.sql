-- 0168: quiet background jobs (7 Nov 2026, the gap search).
--
-- pg_stat_statements on the live database: the scheduled jobs, not the portal's pages, used most of the database's time, on a
-- small shared instance where every page competes with them.
--   sweep_awaiting_units (every 2 minutes)  38.6% of all execution time, ~62 ms a run: it computed the whole SMART priority
--                                           queue on every run, even when no case was waiting for a tanod (almost always).
--   smart_watch (every 5 minutes)           29.4%, ~500 ms a run: it rescanned recurring patterns and spikes over 90 days of
--                                           reports twelve times an hour, though they only change when reports change.
-- Nothing either job does is changed; they skip work that cannot have a different answer.
--   1. sweep_awaiting_units returns as soon as no case is in the waiting line.
--   2. smart_watch rescans patterns and spikes only when a report was filed or changed since its last scan, and at least hourly
--      (a safety net for windows that move with time). Deadline risk, the warnings and quiet cases still run every time.

-- ---------- 1. the waiting line ----------
create or replace function public.sweep_awaiting_units()
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  r      record;
  v_hours smallint;
  v_max   smallint;
  v_smart boolean;
begin
  select awaiting_alert_hours, max_dispatch_attempts into v_hours, v_max from public.operational_settings where id = 1;

  -- 0139: the line is bounded. A case leaves it past the cap on offers, after a day, or once it is no longer
  -- waiting; from then on it is the barangay's (the waiting-hours notice below has gone out once by then).
  update public.reports
     set awaiting_unit_since = null
   where awaiting_unit_since is not null
     and (awaiting_unit_since < now() - interval '24 hours'
          or dispatch_attempts > v_max
          or deleted_at is not null
          or status not in ('pending_review', 'validated'));

  -- 0168: nobody waiting, nothing to do (and the priority queue below is not computed for nothing)
  if not exists (select 1 from public.reports rp
                  where rp.awaiting_unit_since is not null and rp.deleted_at is null and rp.status in ('pending_review', 'validated')) then
    return;
  end if;

  select coalesce((select smart_queue from public.smart_rules where id = 1), false) into v_smart;

  for r in
    select rp.id, rp.awaiting_unit_since
      from public.reports rp
      left join (select q.report_id, q.priority from public._smart_queue() q) q
        on v_smart and q.report_id = rp.id
     where rp.awaiting_unit_since is not null
       and rp.deleted_at is null
       and rp.status in ('pending_review', 'validated')
     order by q.priority desc nulls last, rp.awaiting_unit_since
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

    -- 0130: a sensitive case (VAWC and the like) is never sent to a tanod by the waiting line: a person decides
    if not exists (select 1 from public.reports s where s.id = r.id and s.is_sensitive) then
      perform public.auto_dispatch(r.id);
    end if;
  end loop;
end $$;

-- ---------- 2. the watcher ----------
-- When the watcher last scanned patterns and spikes. One row; read and written only by smart_watch (security definer).
create table public.smart_watch_state (
  id         smallint primary key default 1 check (id = 1),
  scanned_at timestamptz
);
alter table public.smart_watch_state enable row level security;
revoke all on public.smart_watch_state from public, anon, authenticated;
comment on table public.smart_watch_state is 'When smart_watch last scanned recurring patterns and spikes (0168). Internal to the watcher.';

do $$
declare d text; n integer;
begin
  d := replace(pg_get_functiondef('public.smart_watch()'::regprocedure), E'\r', '');

  -- a flag: scan patterns and spikes this time?
  n := (length(d) - length(replace(d, E'  v_key text;\n', ''))) / length(E'  v_key text;\n');
  if n <> 1 then raise exception '0168: smart_watch declare anchor found % times', n; end if;
  d := replace(d, E'  v_key text;\n', E'  v_key text;\n  v_scan boolean;\n');

  -- decided right after the rules are read (the first of the two reads of smart_rules)
  d := regexp_replace(d, E'(  select \\* into k from public\\.smart_rules where id = 1;\n)',
    E'\\1\n  -- 0168: patterns and spikes only change when reports do: rescan when a report was filed or changed since the last scan,\n'
    || E'  -- and at least hourly (windows that move with time)\n'
    || E'  select coalesce((select max(greatest(rp.created_at, coalesce(rp.updated_at, rp.created_at))) from public.reports rp), ''epoch''::timestamptz)\n'
    || E'           >= coalesce((select scanned_at from public.smart_watch_state where id = 1), ''epoch''::timestamptz)\n'
    || E'      or coalesce((select scanned_at from public.smart_watch_state where id = 1), ''epoch''::timestamptz) < now() - interval ''1 hour''\n'
    || E'    into v_scan;\n');
  if position('into v_scan;' in d) = 0 then raise exception '0168: the scan decision did not go in'; end if;

  -- the two scans run only when it is worth it; the time of the scan is kept
  n := (length(d) - length(replace(d, E'  -- recurring problems not seen before\n', ''))) / length(E'  -- recurring problems not seen before\n');
  if n <> 1 then raise exception '0168: patterns anchor found % times', n; end if;
  d := replace(d, E'  -- recurring problems not seen before\n', E'  if v_scan then\n  -- recurring problems not seen before\n');
  n := (length(d) - length(replace(d, E'  -- cases nobody has touched for stuck_days', ''))) / length(E'  -- cases nobody has touched for stuck_days');
  if n <> 1 then raise exception '0168: stuck anchor found % times', n; end if;
  d := replace(d, E'  -- cases nobody has touched for stuck_days',
    E'  insert into public.smart_watch_state (id, scanned_at) values (1, now())\n'
    || E'    on conflict (id) do update set scanned_at = excluded.scanned_at;\n'
    || E'  end if;   -- 0168: v_scan\n\n'
    || E'  -- cases nobody has touched for stuck_days');
  execute d;
end $$;
comment on function public.smart_watch() is
  'SMART watcher (every 5 minutes): storm end, SLA and deadline warnings, quiet cases every time; recurring patterns and spikes when reports changed since the last scan or hourly (0168).';
