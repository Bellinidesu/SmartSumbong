#!/usr/bin/env python3
"""K-04 / 0189: direct timings (EXPLAIN ANALYZE as the real role, row level security on) of the case-rule queries a page or Realtime makes, on the
throwaway database at its current scale. Bulk: counts and lists over every table the rule guards. Point: one row by id, which is what Supabase
Realtime runs per subscriber per change. usage: python time_0189.py TAG   (called by loadcost.py --compare; appends to out/time_0189.json)"""
import json, re, sys
from common import *

WHO = {"Kagawad": "Sweep, Rung 4", "staff": "Sweep, Rung 12", "super": "Sweep, Rung 1", "resident": "Sweep, Resident 1", "tanod": "Sweep, Rung 25"}
BULK = {
    "reports count": "select count(*) from public.reports",
    "cases list 50": "select id, tracking_id, subject, category, status, created_at from public.reports where deleted_at is null order by created_at desc limit 50",
    "pending count": "select count(*) from public.reports where deleted_at is null and status = 'pending_review'",
    "status_logs + case (activity)": "select l.id, l.new_status, r.tracking_id from public.status_logs l join public.reports r on r.id = l.report_id order by l.created_at desc limit 50",
    "status_logs count": "select count(*) from public.status_logs",
    "dispatches + case (1000)": "select d.tanod_id, r.tracking_id from public.dispatches d left join public.reports r on r.id = d.report_id order by d.assigned_at desc limit 1000",
    "notifications (own 50)": "select * from public.notifications where user_id = auth.uid() order by created_at desc limit 50",
    "pending residents count": "select count(*) from public.users where role = 'resident' and verification_status = 'pending'",
    "report_concerns count": "select count(*) from public.report_concerns",
    "report_media count": "select count(*) from public.report_media",
    "case_handler_log count": "select count(*) from public.case_handler_log",
    "public map (500)": "select id, category, status, latitude, longitude from public.reports where is_public limit 500",
}
POINT = {
    "reports by id": "select * from public.reports where id = '{case}'",
    "status_logs of a case": "select * from public.status_logs where report_id = '{case}'",
    "status_log by id (Realtime)": "select * from public.status_logs where id = '{log}'",
    "dispatch by id (Realtime)": "select * from public.dispatches where id = '{disp}'",
    "notification by id (Realtime)": "select * from public.notifications where id = '{note}'",
    "users by id": "select * from public.users where id = '{res}'",
}


def ms(uid, q, timeout=60):
    sql = (f"begin; set local statement_timeout = '{timeout}s'; set local role authenticated; select set_config('request.jwt.claim.sub', '{uid}', true); "
           f"explain (analyze, timing off, summary on) {q}; rollback;")
    try:
        out = psql(sql, raw=True)
    except Exception as e:
        return f">{timeout}s" if "statement timeout" in str(e) else "err"
    m = re.search(r"Execution Time: ([0-9.]+) ms", out)
    return round(float(m.group(1)), 1) if m else "?"


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "now"
    n = int(psql("select count(*) from public.reports")[0][0])
    ids = {k: psql(f"select id from public.users where full_name = '{v}'")[0][0] for k, v in WHO.items()}
    kag = ids["Kagawad"]
    case = (psql(f"select id from public.reports where handler_id = '{kag}' order by created_at desc limit 1") or psql("select id from public.reports order by created_at desc limit 1"))[0][0]
    fill = {"case": case, "log": (psql(f"select id from public.status_logs where report_id = '{case}' limit 1") or psql("select id from public.status_logs limit 1"))[0][0],
            "disp": (psql("select id from public.dispatches order by assigned_at desc limit 1") or [[case]])[0][0],
            "note": psql(f"select id from public.notifications order by created_at desc limit 1")[0][0],
            "res": psql(f"select resident_id from public.reports where id = '{case}'")[0][0]}
    res = {}
    for who, uid in ids.items():
        for qn, q in list(BULK.items()) + list(POINT.items()):
            res[f"{who} | {qn}"] = ms(uid, q.format(**fill))
    f = OUT / "time_0189.json"
    allr = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
    allr[f"{n} cases | {tag}"] = res
    f.write_text(json.dumps(allr, indent=1), encoding="utf-8")
    print(f"time_0189 {n} cases {tag}: " + ", ".join(f"{k}={v}" for k, v in res.items() if k.startswith(("Kagawad", "staff")) and ("count" in k or "Realtime" in k))[:600], flush=True)


if __name__ == "__main__":
    main()
