#!/usr/bin/env python3
"""Class A generator: log instead of swallow. For the engine functions that swallow an error with only RAISE WARNING (server log, not queryable) or that make a
best-effort side effect abort the main press, emit DRAFT 'engine_failures_recorded': the triage trigger records 'engine_error' in smart_events when SMART fails
(filing still succeeds), and _smart_event itself becomes best-effort. Reads out/inject_findings.json to confirm the gap is still there.
usage: python fix/gen_log_swallowed.py"""
import json, re
from fixlib import *


def main():
    d = fn_def("_smart_triage_after_write()")
    if "'engine_error'" in d:
        print("already records engine_error; nothing to do"); return
    m = re.search(r"raise warning 'SMART triage after write failed: %', sqlerrm;", d)
    if not m:
        print("handler shape changed; do by hand"); return
    d2 = d.replace(m.group(0), m.group(0) + "\n  begin\n    perform public._smart_event('engine_error', new.id, 'SMART triage after write failed: ' || sqlerrm, jsonb_build_object('where', '_smart_triage_after_write'));\n  exception when others then null;   -- the record itself must never break filing\n  end;")
    ev = """create or replace function public._smart_event(p_kind text, p_report uuid, p_summary text, p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.smart_events (kind, report_id, actor, summary, detail)
  values (p_kind, p_report, auth.uid(), left(p_summary, 300), coalesce(p_detail, '{}'));
exception when others then
  raise warning 'SMART event not recorded (%): %', p_kind, sqlerrm;   -- a log line may fail; the press it describes must not
end $$;"""
    up = d2.replace("CREATE OR REPLACE FUNCTION", "create or replace function") + "\n\n" + ev
    tr = psqlj("select pg_get_function_arguments(p.oid) a, pg_get_function_result(p.oid) r from pg_proc p where p.oid = 'public.smart_triage(uuid)'::regprocedure")[0]
    break_triage = f"    create or replace function public.smart_triage({tr['a']}) returns {tr['r']} language plpgsql as $f$ begin raise exception 'injected: engine down'; end $f$;"
    fr = "    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Probe file', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);"
    checks = [("filing still succeeds when SMART triage fails", break_triage + "\n" + as_role("v_res", fr) + "\n    if not exists (select 1 from public.reports where subject = 'Probe file') then raise exception 'the report was not filed'; end if;"),
              ("and the failure is recorded in smart_events (kind engine_error), where an administrator can see it", "    if not exists (select 1 from public.smart_events where kind = 'engine_error' and report_id = (select id from public.reports where subject = 'Probe file')) then raise exception 'no engine_error row was recorded'; end if;"),
              ("a log line that cannot be written no longer aborts the action it describes", "    alter table public.smart_events rename to smart_events_x;\n    perform public._smart_event('probe', null, 'probe');\n    alter table public.smart_events_x rename to smart_events;")]
    emit_and_prove("engine_failures_recorded", "record SMART engine failures instead of swallowing them; a failing event log must not abort the press",
                   "tools/sweep/inject.py (failure injection): with smart_triage() or the scoring tables broken, file_report still succeeds (good) but the only trace is a\nRAISE WARNING in the server log, nothing an administrator can see; and when the _smart_event log write fails it aborts admin_dispatch (a best-effort log line\nstopping a real action). This records the triage failure as an 'engine_error' event and makes _smart_event best-effort.",
                   "restore _smart_triage_after_write and _smart_event from 0123/0170 (create or replace); recorded engine_error rows can simply be deleted.", up, "-- restore the two functions from their previous definitions", test_file("engine_failures_recorded (draft)", checks), "gen_log_swallowed.py")


if __name__ == "__main__":
    main()
