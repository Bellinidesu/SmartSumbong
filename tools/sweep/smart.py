#!/usr/bin/env python3
"""Step 3: the SMART engine on the throwaway database. `measure(scale)` is called by loadcost.py after each seed; `python smart.py` prints the table.
Times smart_queue per role, the engine triggers on filing a report, the snapshot refresh and the watcher; proves a failing engine does not
block filing; lists tables that only grow (no retention anywhere) and the engine's cache/log table sizes. Details: out/smart_<scale>x.json."""
import json, re, sys
from common import *

ROLES = {"super": "Sweep, Rung 1", "captain": "Sweep, Rung 3", "committee": "Sweep, Rung 4", "moderator": "Sweep, Rung 12"}


def timed(sql, runs=3, role_user=None):
    """best-of-N wall ms of a statement, inside a rolled-back DO block, optionally as the API's role."""
    setup = ""
    if role_user:
        setup = f"set local role authenticated; select set_config('request.jwt.claim.sub', (select id::text from public.users where full_name = '{role_user}'), true);"
    best = None
    for _ in range(runs):
        t = psql(f"begin; {setup} select 1; explain (analyze, timing on, summary on) {sql}; rollback;", raw=True)
        m = re.search(r"Execution Time: ([0-9.]+) ms", t)
        ms = float(m.group(1)) if m else None
        trig = re.findall(r"Trigger ([a-z_]+): time=([0-9.]+)", t)
        if ms is not None and (best is None or ms < best[0]):
            best = (ms, trig)
    return best


def measure(scale):
    out = {"scale": scale, "reports": int(psql("select count(*) from public.reports")[0][0])}
    # queue per role (as that rung's own role, so row level security runs)
    for k, nm in ROLES.items():
        r = timed("select count(*) from public.smart_queue(null, 50)", role_user=nm)
        out[f"smart_queue_{k}_ms"] = round(r[0], 1) if r else None
    r = timed("select count(*) from public._smart_queue()"); out["_smart_queue_ms"] = round(r[0], 1) if r else None
    # filing: one insert as the resident's own row; the triggers' own times are in the plan
    ins = ("insert into public.reports (resident_id, category, subject, description, latitude, longitude) select id, 'environmental_waste_hazard', 'Sweep file test', "
           "'May baha sa kanto, tulong po', 14.5165, 121.0162 from public.users where full_name = 'Sweep, Resident 1'")
    r = timed(ins); out["file_report_total_ms"] = round(r[0], 1) if r else None
    out["file_report_triggers_ms"] = {n: float(v) for n, v in (r[1] if r else [])}
    # the engine failing must not stop filing: break its lexicon inside a rolled-back transaction and file
    try:
        res = psql(f"begin; alter table public.smart_lexicon rename to smart_lexicon_x; {ins}; select 'filed:' || count(*) from public.reports where subject = 'Sweep file test'; rollback;", raw=True)
        out["filing_survives_engine_failure"] = "filed:1" in res
    except Exception as e:
        out["filing_survives_engine_failure"] = False
        out["filing_failure_error"] = str(e)[:160]
    for name, sql in (("snapshot_refresh_ms", "select public._smart_snapshot_refresh(true)"), ("smart_watch_ms", "select public.smart_watch()"),
                      ("smart_engine_health_ms", "select public.smart_engine_health()"), ("smart_patterns_ms", "select count(*) from public._smart_patterns(30)")):
        try:
            r = timed(sql, runs=2); out[name] = round(r[0], 1) if r else None
        except Exception as e:
            out[name] = "err: " + str(e)[:60]
    out["smart_table_rows"] = {r[0]: int(r[1]) for r in psql("select relname, n_live_tup from pg_stat_user_tables where schemaname = 'public' and (relname like 'smart%' or relname like 'report_triage' or relname like 'command%') order by 2 desc")}
    save(f"smart_{scale}x.json", out)
    return out


def growth():
    """tables nothing ever deletes from (function, cron job): unbounded growth candidates, with live rows"""
    bodies = "\n".join(r["prosrc"] for r in psqlj("select prosrc from pg_proc where pronamespace = 'public'::regnamespace"))
    cron = "\n".join(r[0] for r in psql("select command from cron.job"))
    live_rows = {r["relname"]: r["n"] for r in json.loads(read(OUT / "live_counts.json"))} if (OUT / "live_counts.json").exists() else {}
    rows = []
    for (t,) in psql("select relname from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname <> 'spatial_ref_sys'"):
        has_del = bool(re.search(r"(delete\s+from|truncate)\s+(table\s+)?(public\.)?" + t + r"(?![a-z_])", bodies + cron, re.I))
        ins = bool(re.search(r"insert\s+into\s+(public\.)?" + t + r"(?![a-z_])", bodies, re.I))
        rows.append((t, ins, has_del, live_rows.get(t)))
    return rows


def main():
    sc = sorted(int(f.stem.split("_")[1][:-1]) for f in OUT.glob("smart_*x.json"))
    d = {s: json.loads(read(OUT / f"smart_{s}x.json")) for s in sc}
    keys = [k for k in d[sc[0]] if k.endswith("_ms")] if d else []
    print("SMART ENGINE (ms)  " + "  ".join(f"{s}x ({d[s]['reports']} cases)" for s in sc))
    for k in keys:
        print(f"  {k:<28}" + "  ".join(f"{d[s].get(k)!s:>14}" for s in sc))
    for s in sc:
        print(f"  filing survives a broken engine @{s}x: {d[s].get('filing_survives_engine_failure')}  triggers: {d[s].get('file_report_triggers_ms')}")
    g = growth()
    grow = [(t, n) for t, ins, dele, n in g if ins and not dele and (n or 0) >= 100]
    print("  grow-only tables (written, never deleted by any function/job; live rows >= 100): " + ", ".join(f"{t}={n}" for t, n in sorted(grow, key=lambda x: -(x[1] or 0))[:10]))
    save("smart_growth.json", [{"table": t, "written": i, "deleted": dl, "live_rows": n} for t, i, dl, n in g])
    if sc:
        print("  engine tables @%dx: " % sc[-1] + ", ".join(f"{k}={v}" for k, v in list(d[sc[-1]]["smart_table_rows"].items())[:8]))


if __name__ == "__main__":
    main()
