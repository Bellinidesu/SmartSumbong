#!/usr/bin/env python3
"""Runs the dynamic prober (probe.py: every API function x 11 actors x 11 case states x 3 handling variants, ~37k probes) on sweep_probe BEFORE and AFTER a draft and
compares, per probe, the outcome class, the resulting case status, the other state changes and every notice (recipient, kind, report_id set, can they open the case).
Ids are not compared (they differ per run). usage: SWEEP_PORT=.. python probe_compare_0191.py <draft.sql>"""
import json, subprocess, sys
from common import *
import probe

draft = sys.argv[1]
snap = {}
for label in ("before", "after"):
    if label == "after":
        r = subprocess.run([f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", probe.DB, "-X", "-q", "-1", "-v", "ON_ERROR_STOP=1", "-f", draft], capture_output=True, text=True)
        if r.returncode: raise SystemExit(r.stderr[-300:])
    probe.cmd_run(set())
    fs = probe.funcs()
    M = {k: v for k, v in probe.load().items() if k in fs}
    snap[label] = {(fn, x["s"], x["v"], x["a"], x["t"]): (probe.classify(x.get("r", "")), x.get("to"), x.get("side"), tuple(sorted((n["to"], n["kind"], n["rid"], str(n["sees"])) for n in x.get("n", []))))
                   for fn, rows in M.items() for x in rows}
    print(label, "probes", len(snap[label]), flush=True)
diff = [(k, snap["before"][k], snap["after"].get(k)) for k in snap["before"] if snap["before"][k] != snap["after"].get(k)]
print(f"PROBE COMPARE: {len(snap['before'])} probes before, {len(snap['after'])} after; differences: {len(diff)}")
for k, a, b in diff[:12]: print("  ", k, "\n     before", a, "\n     after ", b)
save("probe_compare_0191.json", {"probes": len(snap["before"]), "differences": [[list(k), a, b] for k, a, b in diff][:200]})
sys.exit(1 if diff else 0)
