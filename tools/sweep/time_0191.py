#!/usr/bin/env python3
"""0191 timing: the case-rule queries of every page (time_0189.py's BULK and POINT sets, as the real role, row level security on) BEFORE (0190 as on main) and
AFTER the draft, at 250x, 50x and 1x, on a seeded throwaway copy. Each size: measure, apply the draft, measure, apply the undo. Prints the worst regression.
usage: SWEEP_PORT=.. python time_0191.py"""
import json, os, subprocess, sys
from common import *
import equiv_case_rule as E

DB = "sweep_t191"
DRAFT = ROOT / "supabase/drafts/0191_case_rule_consistency.sql"; UNDO = ROOT / "supabase/drafts/0191_undo.sql"


def measure(tag):
    env = dict(os.environ, SWEEP_DB=DB)
    r = subprocess.run([sys.executable, str(ROOT / "tools/sweep/time_0189.py"), tag], env=env, capture_output=True, text=True, encoding="utf-8")
    if r.returncode: raise SystemExit(r.stderr[-400:])


def main():
    E.sh(E.P("postgres") + ["-c", f"drop database if exists {DB}", "-c", f"create database {DB} template k04_base"])
    E.sh(E.P(DB) + ["-v", "n_cases=20000", "-v", "n_res=2000", "-f", str(ROOT / "tools/sweep/sql/seed.sql")])
    f = OUT / "time_0189.json"
    if f.exists(): f.unlink()
    for keep in (20000, 4000, 82):
        if keep < 20000:
            psql("set session_replication_role = replica; delete from public.reports where id not in (select id from public.reports order by created_at desc limit %d); analyze" % keep, db=DB)
        n = int(psql("select count(*) from public.reports", db=DB)[0][0])
        measure("before"); E.run_file(DB, DRAFT); measure("after"); E.run_file(DB, UNDO)
        print(f"measured {n} cases", flush=True)
    allr = json.loads(f.read_text(encoding="utf-8")); out = []
    for size in sorted({k.split(" | ")[0] for k in allr}, key=lambda s: int(s.split()[0])):
        b, a = allr[f"{size} | before"], allr[f"{size} | after"]
        worst = []
        for k in b:
            x, y = b[k], a[k]
            if isinstance(x, (int, float)) and isinstance(y, (int, float)): worst.append((y - x, y / max(x, 0.5), k, x, y))
        worst.sort(reverse=True)
        tot_b = sum(v for v in b.values() if isinstance(v, (int, float))); tot_a = sum(v for v in a.values() if isinstance(v, (int, float)))
        out.append({"size": size, "total_before_ms": round(tot_b), "total_after_ms": round(tot_a), "worst_regression": [f"{k}: {x} -> {y} ms" for d, r, k, x, y in worst[:3]]})
        print(f"  {size:<18} all queries, all roles: {tot_b:,.0f} -> {tot_a:,.0f} ms; worst slower: " + "; ".join(f"{k} {x}->{y}" for d, r, k, x, y in worst[:2]))
    save("time_0191.json", out)


if __name__ == "__main__":
    main()
