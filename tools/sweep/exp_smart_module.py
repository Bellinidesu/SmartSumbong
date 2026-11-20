#!/usr/bin/env python3
"""Timing and equivalence of draft 0190 (smart_module() on the visible-case set) at 1x / 50x / 250x. Throwaway copy `sweep_exp` of the local full-build database;
every measurement is a rolled-back transaction (draft applied inside it), run as the real rung (jwt claim, security-definer function). Also proves, at each size and for
every seeded rung (super, captain, 3 Kagawads, 6 staff), that the new body returns the same document as the old one (symmetric difference 0).
usage: SWEEP_PORT=... python exp_smart_module.py   (database `postgres` seeded at 20,000 cases by tools/sweep/sql/seed.sql)"""
import re, subprocess, time
from common import *

DB = "sweep_exp"
DRAFT = (ROOT / "supabase/drafts/0190_smart_module_set_based.sql")
UNDO = (ROOT / "supabase/drafts/0190_undo.sql")
WHO = {"Kagawad": "Sweep, Rung 4", "staff": "Sweep, Rung 12", "super": "Sweep, Rung 1", "captain": "Sweep, Rung 3"}
ALL = [f"Sweep, Rung {i}" for i in (1, 3, 4, 5, 6, 12, 13, 14, 15, 16, 17)]


def draft_up():
    t = read(DRAFT)
    return "\n".join(l for l in t.splitlines() if not l.startswith("--"))   # the executable part only


def old_fn():
    return read(UNDO).replace("public.smart_module()", "public._smart_module_old()")


def uid(name):
    return psql(f"select id from public.users where full_name = '{name}'", db=DB)[0][0]


def timed(who, new):
    sql = (f"begin; set local statement_timeout = '120s'; {draft_up() if new else 'select 1'}; select set_config('request.jwt.claim.sub', '{uid(WHO[who])}', true); "
           f"explain (analyze, timing off, summary on) select public.smart_module(); rollback;")
    out = psql(sql, db=DB, raw=True)
    m = re.search(r"Execution Time: ([0-9.]+) ms", out)
    return round(float(m.group(1))) if m else None


NORM = """create function pg_temp.norm(j jsonb) returns jsonb language sql as $n$
  select case when jsonb_typeof(j) = 'array' then coalesce((select jsonb_agg(case when jsonb_typeof(e) = 'object' and e ? 'tracking_ids'
         then (e - 'tracking_ids') || jsonb_build_object('tracking_ids', (select coalesce(jsonb_agg(t order by t), '[]') from jsonb_array_elements_text(e->'tracking_ids') t)) else e end order by ord)
         from jsonb_array_elements(j) with ordinality x(e, ord)), '[]') else j end $n$"""


DQ = """create function pg_temp.dq(j jsonb) returns jsonb language sql as $q$
  select coalesce((select jsonb_agg(e->'days_quiet' order by (e->>'days_quiet')::numeric) from jsonb_array_elements(j) e), '[]') $q$"""


def same(name):
    """[] when the old and the new body return the same document (a pattern's tracking ids compared as sets, and the 8 quietest cases by their quiet days: ties at the cut are broken arbitrarily by both bodies), else the differing keys"""
    sql = (f"begin; {old_fn()}; {draft_up()}; {NORM}; {DQ}; select set_config('request.jwt.claim.sub', '{uid(name)}', true); "
           f"select 'DIFF:' || coalesce(string_agg(o.k, ','), '') from jsonb_each(public._smart_module_old() - 'at') o(k, v) join jsonb_each(public.smart_module() - 'at') n(k, v) on n.k = o.k "
           f"where (case when o.k = 'quiet' then pg_temp.dq(o.v) else pg_temp.norm(o.v) end) is distinct from (case when o.k = 'quiet' then pg_temp.dq(n.v) else pg_temp.norm(n.v) end); rollback;")
    out = [l.strip() for l in psql(sql, db=DB, raw=True).splitlines() if l.startswith("DIFF:")]
    return [k for k in out[0][5:].split(",") if k] if out else ["?"]


def main():
    P = [f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-X", "-q", "-d", "postgres", "-c"]
    subprocess.run(P + ["drop database if exists sweep_exp"]); subprocess.run(P + ["create database sweep_exp template postgres"], check=True)
    res, eq = {}, {}
    for label, keep in (("250x (20,000 cases)", 20000), ("50x (4,000)", 4000), ("1x (82)", 82)):
        if keep < 20000:
            psql("set session_replication_role = replica; delete from public.reports where id not in (select id from public.reports order by created_at desc limit %d); analyze" % keep, db=DB)
            psql("select public._smart_snapshot_refresh(true)", db=DB)
        n = int(psql("select count(*) from public.reports", db=DB)[0][0])
        open_n = int(psql("select count(*) from public.reports where deleted_at is null and referred_to is null and status not in ('resolved','closed','archived','rejected','cancelled')", db=DB)[0][0])
        for who in WHO:
            res[(label, who, "before")] = timed(who, False); res[(label, who, "after")] = timed(who, True)
        eq[label] = {nm: d for nm in ALL if (d := same(nm))}
        print(f"-- {label}: {n} cases ({open_n} open): " + "  ".join(f"{w} {res[(label, w, 'before')]}->{res[(label, w, 'after')]} ms" for w in WHO)
              + f"  | same document for {len(ALL) - len(eq[label])}/{len(ALL)} rungs" + (f" (DIFFERS: {eq[label]})" if eq[label] else ""), flush=True)
    save("exp_smart_module.json", {"timings": [{"size": k[0], "who": k[1], "when": k[2], "ms": v} for k, v in res.items()], "differs": eq})


if __name__ == "__main__":
    main()
