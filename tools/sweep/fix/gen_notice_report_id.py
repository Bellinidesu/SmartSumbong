#!/usr/bin/env python3
"""Class A generator: a notice about a case must carry its report_id. Reads out/probe_findings.json (functions whose admin notices have no report_id; falls back
to request_reopen/request_appeal), takes each function's CURRENT definition from the local database, adds report_id to the notifications insert, and emits
DRAFT 'notice_report_id' (+ a test). The notifications_scope trigger then drops the notice for admins who cannot open the case, and the portal gets its Review link.
usage: python fix/gen_notice_report_id.py [--check]"""
import json, re, sys
from fixlib import *

NOTIF = re.compile(r"insert into public\.notifications\s*\(user_id, kind, message\)\s*select a\.id, ('status_change'),", re.I)


def main():
    fns = ["request_reopen", "request_appeal"]
    pf = OUT / "probe_findings.json"
    if pf.exists():
        found = sorted({f for f, _ in json.loads(read(pf))["norid"]})
        fns = found or fns
    ups, done = [], []
    for fn in fns:
        sig = psql(f"select oid::regprocedure::text from pg_proc where proname = '{fn}' and pronamespace = 'public'::regnamespace")[0][0]
        d = fn_def(sig.replace("public.", ""))
        if not NOTIF.search(d):
            print(f"  skipped {fn}: its notice insert does not have the expected shape (do it by hand)"); continue
        arg = re.search(r"\((p_report[a-z_]*) uuid", d).group(1)
        d2 = NOTIF.sub(lambda m: f"insert into public.notifications (user_id, report_id, kind, message)\n  select a.id, {arg}, {m.group(1)},", d)
        ups.append(d2.replace("CREATE OR REPLACE FUNCTION", "create or replace function"))
        done.append(fn)
    if not done:
        print("nothing to generate"); return
    up = "\n\n".join(ups)
    undo = "re-run the previous definitions of " + ", ".join(done) + " (0037 and 0057); no data changes."
    reopen_check = as_role("v_res", "    perform public.request_reopen(v_case, 'Bumalik ang ingay');") if "request_reopen" in done else ""
    checks = [
        ("the notice carries the case (Review link): every notice about the reopen request has a report_id", reopen_check + "\n    if exists (select 1 from public.notifications where message like 'Reopen requested%' and report_id is null) then raise exception 'a reopen notice has no report_id'; end if;"),
        ("the Kagawad of the case's committee and the super admin are told", "    if not exists (select 1 from public.notifications where user_id = v_kpo and report_id = v_case and message like 'Reopen requested%') then raise exception 'the Kagawad was not told'; end if;\n    if not exists (select 1 from public.notifications where user_id = v_sup and report_id = v_case and message like 'Reopen requested%') then raise exception 'the super admin was not told'; end if;"),
        ("nobody who cannot open the case is told (other committee's Kagawad, staff nobody assigned)", "    if exists (select 1 from public.notifications where user_id in (v_kenv, v_stf) and message like 'Reopen requested%') then raise exception 'an administrator who cannot open the case was told'; end if;"),
    ]
    if "request_appeal" in done:
        checks.append(("an appeal request is scoped the same way", "    set local session_replication_role = replica; update public.reports set status = 'rejected' where id = v_case; set local session_replication_role = origin;\n" + as_role("v_res", "    perform public.request_appeal(v_case, 'Hindi po ito tama');") + "\n    if exists (select 1 from public.notifications where user_id in (v_kenv, v_stf) and message like 'Appeal requested%') then raise exception 'an appeal notice reached an administrator who cannot open the case'; end if;\n    if exists (select 1 from public.notifications where message like 'Appeal requested%' and report_id is null) then raise exception 'an appeal notice has no report_id'; end if;"))
    emit_and_prove("notice_report_id", "reopen and appeal requests notify only admins who can open the case, with a Review link",
                   "Probe (tools/sweep/probe.py): request_reopen and request_appeal insert one notice per active admin with no report_id, so _notifications_scope (which only\nfilters notices that carry a report_id) lets them all through: 6 administrators told, 4 of whom cannot open the case, and no Review button.\nAdding the case id fixes both at once; the trigger does the scoping.",
                   undo, up, "-- restore request_reopen / request_appeal from 0037 / 0057 (create or replace with the old insert)", test_file("notice_report_id (draft)", checks), "gen_notice_report_id.py")


if __name__ == "__main__":
    main()
