#!/usr/bin/env python3
"""0191 timing, repeated: at 250x, three alternating rounds of before/after (draft applied, measured, undone) so one noisy run cannot hide or fake a regression.
Prints, for the Kagawad and staff, the median of three per query, before vs after, and the totals. Uses the seeded sweep_t191 from time_0191.py (reseeds it)."""
import json, os, statistics, subprocess, sys
from common import *
import equiv_case_rule as E
import time_0191 as T

E.sh(E.P("postgres") + ["-c", f"drop database if exists {T.DB}", "-c", f"create database {T.DB} template k04_base"])
E.sh(E.P(T.DB) + ["-v", "n_cases=20000", "-v", "n_res=2000", "-f", str(ROOT / "tools/sweep/sql/seed.sql")])
f = OUT / "time_0189.json"
if f.exists(): f.unlink()
for i in (1, 2, 3):
    T.measure(f"before{i}"); E.run_file(T.DB, T.DRAFT); T.measure(f"after{i}"); E.run_file(T.DB, T.UNDO)
d = json.loads(f.read_text(encoding="utf-8")); b = [d[f"20000 cases | before{i}"] for i in (1, 2, 3)]; a = [d[f"20000 cases | after{i}"] for i in (1, 2, 3)]
rows, tb, ta = [], 0, 0
for k in b[0]:
    mb = statistics.median(x[k] for x in b if isinstance(x[k], (int, float))); ma = statistics.median(x[k] for x in a if isinstance(x[k], (int, float)))
    tb += mb; ta += ma; rows.append((ma - mb, k, mb, ma))
rows.sort(reverse=True)
print(f"TIMING 250x, median of 3 alternating rounds, every query x every role: {tb:,.0f} -> {ta:,.0f} ms ({(ta / tb - 1) * 100:+.1f}%)")
print("  slowest changes: " + "; ".join(f"{k} {mb:.1f}->{ma:.1f}" for d_, k, mb, ma in rows[:4]))
print("  fastest changes: " + "; ".join(f"{k} {mb:.1f}->{ma:.1f}" for d_, k, mb, ma in rows[-3:]))
save("time_0191_repeat.json", [{"q": k, "before": mb, "after": ma} for d_, k, mb, ma in rows])
