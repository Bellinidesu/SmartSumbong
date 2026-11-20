#!/usr/bin/env python3
"""Runs every rolled-back check in supabase/tests on two copies of the pristine database k04_base: as it is (main) and with a draft applied, and compares the
ok / FAIL lines file by file. usage: SWEEP_PORT=.. python pgtap_compare.py <draft.sql> [extra test files...]   Output: out/pgtap_compare.json + a compact table."""
import re, subprocess, sys
from common import *
import equiv_case_rule as E

draft = sys.argv[1]
extra = sys.argv[2:]
files = sorted((ROOT / "supabase" / "tests").glob("[0-9][0-9]_*.sql")) + [ROOT / x for x in extra]
res = {}
for label, apply in (("before", False), ("after", True)):
    db = f"sweep_tap_{label}"
    E.sh(E.P("postgres") + ["-c", f"drop database if exists {db}", "-c", f"create database {db} template k04_base"])
    if apply:
        E.sh(E.P(db) + ["-1", "-f", draft])
    for f in files:
        r = subprocess.run(E.P(db) + ["-f", str(f)], capture_output=True, text=True, encoding="utf-8")
        lines = [l for l in (r.stdout + r.stderr).splitlines() if re.match(r"^(ok|FAIL|BAD)", l)]
        res.setdefault(f.name, {})[label] = {"ok": sum(l.startswith("ok") for l in lines), "fail": [l[:140] for l in lines if not l.startswith("ok")]}
    print(label, "done", flush=True)
save("pgtap_compare.json", res)
diff = {n: v for n, v in res.items() if v["before"]["ok"] != v["after"]["ok"] or v["before"]["fail"] != v["after"]["fail"]}
tot = lambda k: sum(v[k]["ok"] for v in res.values())
print(f"PGTAP: {len(files)} scripts; ok before {tot('before')}, after {tot('after')}; FAIL before {sum(len(v['before']['fail']) for v in res.values())}, after {sum(len(v['after']['fail']) for v in res.values())}; scripts that differ: {len(diff)}")
for n, v in diff.items(): print(f"  {n}: before ok {v['before']['ok']} fail {len(v['before']['fail'])} | after ok {v['after']['ok']} fail {len(v['after']['fail'])}  {(v['after']['fail'] or [''])[0][:120]}")
