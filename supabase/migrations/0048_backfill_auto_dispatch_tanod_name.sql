-- =============================================================
-- SmartSumbong — 0048 Backfill tanod names into old auto-dispatch remarks
--
-- 0047 made auto_dispatch write "Auto-dispatched to <name> (X m away)"
-- instead of "Auto-dispatched to nearest unit (X m)" — but that only
-- changes what gets written going forward. status_logs.remark is stored
-- text, not computed at read time, so every report auto-dispatched
-- before 0047 was applied keeps the old distance-only wording forever
-- unless something rewrites it. This migration is that one-time rewrite,
-- requested right after 0047 shipped once a live screenshot showed an
-- already-dispatched report still reading "nearest unit".
--
-- MATCHING. report_id alone isn't a safe join key: reroute_dispatch can
-- leave more than one dispatches row against the same report, and a
-- report could in principle be auto-dispatched more than once (e.g. the
-- queue path after a reroute). auto_dispatch always writes its
-- dispatches.admin_instructions and its status_logs.remark from the same
-- round(v_metres) value in the same call, so matching on report_id AND
-- that exact distance number — pulled out of the old remark text and
-- matched against admin_instructions' own wording — picks the one
-- dispatch row that produced this exact remark, not just any dispatch on
-- the report.
--
-- SCOPE. Only rewrites status_logs rows still carrying the exact old
-- wording ("Auto-dispatched to nearest unit (X m)"); anything already in
-- the new form (written by 0047 after it was applied) is left alone. A
-- row with no matching dispatches (data predates the dispatches table,
-- or the tanod row was since deleted) is left as-is rather than guessed
-- at — silently wrong is worse than unchanged here.
--
-- SAFE TO RE-RUN. The where clause only ever matches the old wording, so
-- running this again after some reports already show the new wording is
-- a no-op on everything already backfilled.
-- =============================================================

set search_path = public, extensions;

do $$
declare
  r record;
  v_name text;
begin
  for r in
    select sl.id as log_id, sl.report_id,
           (regexp_match(sl.remark, '\((\d+) m\)'))[1] as metres_text
    from public.status_logs sl
    where sl.remark ~ '^Auto-dispatched to nearest unit \(\d+ m\)$'
  loop
    v_name := null;

    select u.full_name into v_name
      from public.dispatches d
      join public.users u on u.id = d.tanod_id
     where d.report_id = r.report_id
       and d.admin_instructions = format(
             'Automatic dispatch — nearest available unit, %s m from the incident.',
             r.metres_text)
     order by d.assigned_at
     limit 1;

    if v_name is not null then
      update public.status_logs
         set remark = format('Auto-dispatched to %s (%s m away)', v_name, r.metres_text)
       where id = r.log_id;
    end if;
  end loop;
end $$;
