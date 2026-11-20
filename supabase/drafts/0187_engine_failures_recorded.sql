-- DRAFT: not applied until Ace says apply 0187
-- 0187_engine_failures_recorded: record SMART engine failures instead of swallowing them; a failing event log must not abort the press
--
-- tools/sweep/inject.py (failure injection): with smart_triage() or the scoring tables broken, file_report still succeeds (good) but the only trace is a
-- RAISE WARNING in the server log, nothing an administrator can see; and when the _smart_event log write fails it aborts admin_dispatch (a best-effort log line
-- stopping a real action). This records the triage failure as an 'engine_error' event and makes _smart_event best-effort.
--
-- UNDO (plain language): restore _smart_triage_after_write and _smart_event from 0123/0170 (create or replace); recorded engine_error rows can simply be deleted.
-- Proof: supabase/drafts/tests/0187_engine_failures_recorded.test.sql fails before this file and passes after it (run by tools/sweep/fix/gen_log_swallowed.py).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.

create or replace function public._smart_triage_after_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
declare
  k public.smart_rules%rowtype;
  v_id uuid;
begin
  perform public.smart_triage(new.id);
  select * into k from public.smart_rules where id = 1;
  for v_id in
    select o.id from public.reports o
     where o.id <> new.id
       and o.category = new.category
       and o.deleted_at is null
       and o.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
       and o.created_at > new.created_at - make_interval(hours => k.corroboration_hours)
       and st_dwithin(o.geom, new.geom, greatest(k.corroboration_metres, k.duplicate_metres))
     limit 20
  loop
    perform public.smart_triage(v_id);
  end loop;
  return null;
exception when others then
  raise warning 'SMART triage after write failed: %', sqlerrm;
  begin
    perform public._smart_event('engine_error', new.id, 'SMART triage after write failed: ' || sqlerrm, jsonb_build_object('where', '_smart_triage_after_write'));
  exception when others then null;   -- the record itself must never break filing
  end;
  return null;
end $function$;

create or replace function public._smart_event(p_kind text, p_report uuid, p_summary text, p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.smart_events (kind, report_id, actor, summary, detail)
  values (p_kind, p_report, auth.uid(), left(p_summary, 300), coalesce(p_detail, '{}'));
exception when others then
  raise warning 'SMART event not recorded (%): %', p_kind, sqlerrm;   -- a log line may fail; the press it describes must not
end $$;

-- UNDO SQL (not run; for the person applying this):
-- -- restore the two functions from their previous definitions
