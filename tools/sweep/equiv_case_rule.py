#!/usr/bin/env python3
"""K-04 / 0189 EQUIVALENCE PROOF on a throwaway copy. For every person x every row of every table whose read policy uses the case rule, the rows
that person reads (row level security on, as the API's own role) under TODAY's policies, after supabase/drafts/0189_case_rule_at_scale.sql, and
after supabase/drafts/0189_undo.sql must be the same set (symmetric difference 0). Also compares, per (person, case), _my_scoped_case_ids()
with the old per-case function (admin_scoped() and admin_sees_report(id)), and that the undo restores every policy's text and drops the helpers.
usage: python equiv_case_rule.py fixture            exhaustive fixture (sql/equiv_fixture.sql) on a copy of the pristine database (k04_base)
       python equiv_case_rule.py scale [DB]         the seeded 250x copy (DB, default sweep_eq250): every Sweep rung + 30 residents
Needs local_db.sh up (SWEEP_PORT) and a pristine template database k04_base. Output: out/equiv_<mode>.json + a compact table."""
import json, subprocess, sys, time
from common import *

TABLES = ["reports", "case_forwards", "case_handler_log", "detail_requests", "dispatch_media", "dispatch_updates", "dispatches", "escalation_requests",
          "feedback", "look_shares", "notifications", "report_concerns", "report_evidence", "report_media", "report_messages", "report_triage",
          "resolution_checks", "sla_extensions", "smart_events", "smart_overrides", "status_logs", "users"]
DRAFT = ROOT / "supabase" / "drafts" / "0189_case_rule_at_scale.sql"
UNDO = ROOT / "supabase" / "drafts" / "0189_undo.sql"
HELPERS = ["_my_committee", "_my_categories", "_my_concern_case_ids", "_my_handled_case_ids", "_my_scoped_case_ids", "_my_scoped_dispatch_ids", "_my_scoped_resident_ids"]


def sh(args, check=True):
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    if check and r.returncode:
        raise RuntimeError((r.stderr or r.stdout)[-800:])
    return r.stdout


def P(db):
    return [f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", db]


def run_file(db, path):
    return sh(P(db) + ["-f", str(path)])


def snapshot(db, label):
    """every actor x every table: the md5 of each row they read, kept in eq.snap (row level security on, role authenticated)."""
    psql(f"delete from eq.snap where label = '{label}'", db=db)
    arr = "array[" + ",".join(f"'{t}'" for t in TABLES) + "]"
    sql = f"""do $s$ declare a record; t text; begin
  for a in select * from eq.actors order by name loop
    foreach t in array {arr} loop
      perform set_config('request.jwt.claim.sub', a.id::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', a.id, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      execute format('insert into eq.snap select %L, %L, %L, md5(x::text) from public.%I x', '{label}', a.name, t, t);
      execute 'reset role';
    end loop;
    -- the case set itself, per person: the old per-case function vs the new set helper (when it exists)
    execute format('insert into eq.snap select %L, %L, ''fn:old_case_rule'', r.id::text from public.reports r where public.admin_scoped() and public.admin_sees_report(r.id)', '{label}', a.name)
      using a.id;
  end loop; end $s$;"""
    # admin_scoped()/admin_sees_report() read auth.uid(), so the fn row is written per actor with the claim set (done inside the loop above via set_config)
    t0 = time.time(); psql(sql, db=db)
    if psql("select count(*) from pg_proc where proname = '_my_scoped_case_ids'", db=db)[0][0] != "0":
        psql(f"""do $s$ declare a record; begin for a in select * from eq.actors loop
          perform set_config('request.jwt.claim.sub', a.id::text, true);
          execute 'set local role authenticated';
          insert into eq.snap select '{label}', a.name, 'fn:new_case_set', x::text from (select distinct x from public._my_scoped_case_ids() x) s;
          execute 'reset role';
        end loop; end $s$;""", db=db)
    return round(time.time() - t0, 1)


def diff(db, a, b, tbl_filter="tbl not like 'fn:%'"):
    rows = psql(f"""with x as (select actor, tbl, k, count(*) n from eq.snap where label = '{a}' and {tbl_filter} group by 1,2,3),
                         y as (select actor, tbl, k, count(*) n from eq.snap where label = '{b}' and {tbl_filter} group by 1,2,3)
                    select coalesce(x.tbl, y.tbl), count(*) filter (where x.k is null or y.k is null or x.n <> y.n), coalesce(sum(x.n), 0)
                      from x full join y using (actor, tbl, k) group by 1 order by 1""", db=db)
    return {r[0]: (int(r[1]), int(r[2])) for r in rows}


def policy_text(db):
    return psql("select tablename || '.' || policyname, md5(coalesce(qual, '') || '|' || coalesce(with_check, '')) from pg_policies where schemaname = 'public' order by 1", db=db)


BROKEN = {   # deliberate mistakes of the kind a rewrite can make; pgTAP 67 must catch every one
    "waiting cases shown to a Kagawad": ("and not coalesce(awaiting_placement, false)\n        and ((handler_id", "and ((handler_id"),
    "a declined case counts as handled": ("l.action in ('take', 'take_over', 'accept')", "l.action in ('take', 'take_over', 'accept', 'decline')"),
    "a forwarded-away case kept by category": ("or (r.committee is null and r.category = any", "or (r.category = any"),
    "the case set forgets concerns": ("  union all\n  select c.id from public._my_concern_case_ids() c(id)\n", ""),
    "the case set forgets earlier hands": ("  union all\n  select h.id from public._my_handled_case_ids() h(id)\n", ""),
}


def broken():
    """pgTAP 67 on 0189 with one deliberate mistake at a time: each must FAIL; on the real 0189 it must pass."""
    text = read(DRAFT); res = {}
    for name, (a, b) in list(BROKEN.items()) + [("0189 as drafted", ("", ""))]:
        if a and a not in text: raise SystemExit(f"broken variant '{name}' no longer matches the draft")
        f = OUT / "0189_variant.sql"; f.write_text(text.replace(a, b, 1) if a else text, encoding="utf-8")
        sh(P("postgres") + ["-c", "drop database if exists sweep_broken", "-c", "create database sweep_broken template k04_base"])
        sh(P("sweep_broken") + ["-1", "-f", str(f)])
        r = subprocess.run(P("sweep_broken") + ["-f", str(ROOT / "supabase/tests/67_case_rule_equivalence.sql")], capture_output=True, text=True, encoding="utf-8")
        lines = [l for l in r.stderr.splitlines() if l.startswith(("ok", "FAIL"))]
        res[name] = {"ok": sum(l.startswith("ok") for l in lines), "fail": [l[:160] for l in lines if l.startswith("FAIL")]}
        print(f"  {name:<44} ok {res[name]['ok']}  FAIL {len(res[name]['fail'])}  {res[name]['fail'][0][:110] if res[name]['fail'] else ''}", flush=True)
    save("equiv_broken.json", res)
    good = res["0189 as drafted"]["ok"] == 3 and not res["0189 as drafted"]["fail"] and all(v["fail"] for k, v in res.items() if k != "0189 as drafted")
    print("RESULT:", "every broken variant fails, 0189 passes" if good else "NOT PROVEN"); sys.exit(0 if good else 1)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "fixture"
    if mode == "broken":
        return broken()
    db = "sweep_equiv" if mode == "fixture" else (sys.argv[2] if len(sys.argv) > 2 else "sweep_eq250")
    if mode == "fixture" and "--resume" not in sys.argv:
        sh(P("postgres") + ["-c", f"drop database if exists {db}", "-c", f"create database {db} template k04_base"])
        t0 = time.time(); print(run_file(db, ROOT / "tools/sweep/sql/equiv_fixture.sql").strip().splitlines()[-1:], f"fixture {round(time.time() - t0)}s", flush=True)
    elif mode == "scale":
        sh(P(db) + ["-c", "create schema if not exists eq; create table if not exists eq.actors (name text primary key, id uuid not null); create table if not exists eq.snap (label text, actor text, tbl text, k text); grant usage on schema eq to authenticated; grant select, insert on eq.snap to authenticated; grant select on eq.actors to authenticated; truncate eq.actors; "
                    "insert into eq.actors select full_name, id from public.users where full_name like 'Sweep, Rung %' or full_name in (select 'Sweep, Resident ' || g from generate_series(1, 30) g); "
                    "insert into eq.actors values ('ghost', '00000000-0000-4000-8000-00000000e0e0')"])
    before_pol = policy_text("k04_base")   # the pristine copy (= live, checked by gen_0189_undo.py --check-live)
    out = {"mode": mode, "db": db, "seconds": {}}
    # "resume": the old and new snapshots exist and the undo has been applied (a run cut off during the last snapshot)
    steps = [("old", None), ("new", DRAFT), ("undo", UNDO)] if "--resume" not in sys.argv else ([("undo", None)] if "--report" not in sys.argv else [])
    for label, f in steps:
        if f: run_file(db, f)
        out["seconds"][label] = snapshot(db, label); print(f"{label} snapshot", out["seconds"][label], "s", flush=True)
    after_pol = policy_text(db)
    left = (psql("select 'left:' || coalesce(string_agg(proname, ','), '') from pg_proc where pronamespace = 'public'::regnamespace and proname = any(array[" + ",".join(f"'{h}'" for h in HELPERS) + "])", db=db))[0][0][5:]
    n_actors = int(psql("select count(*) from eq.actors", db=db)[0][0])
    rows_per_tbl = {t: int(psql(f"select count(*) from public.{t}", db=db)[0][0]) for t in TABLES}
    d_new, d_undo = diff(db, "old", "new"), diff(db, "old", "undo")
    fn = psql("""with o as (select actor, k from eq.snap where label = 'old' and tbl = 'fn:old_case_rule'), n as (select actor, k from eq.snap where label = 'new' and tbl = 'fn:new_case_set')
                 select count(*) filter (where o.k is null or n.k is null), count(*) filter (where o.k is not null) from o full join n using (actor, k)""", db=db)[0]
    out.update(actors=n_actors, rows=rows_per_tbl, pairs={t: n_actors * rows_per_tbl[t] for t in TABLES},
               visible_old={t: d_new.get(t, (0, 0))[1] for t in TABLES}, diff_new={t: d_new.get(t, (0, 0))[0] for t in TABLES},
               diff_undo={t: d_undo.get(t, (0, 0))[0] for t in TABLES}, fn_case_set_diff=int(fn[0]), fn_case_set_visible=int(fn[1]),
               policies_restored=before_pol == after_pol, helpers_left_after_undo=left)
    per_actor = psql("select actor, tbl, count(*) from eq.snap where label = 'old' and tbl not like 'fn:%' group by 1, 2 order by 1, 2", db=db)
    out["visible_by_actor"] = {}
    for a, t, n in per_actor:
        out["visible_by_actor"].setdefault(a, {})[t] = int(n)
    save(f"equiv_{mode}.json", out)
    print(f"EQUIVALENCE ({mode}, {db}): {n_actors} people x {sum(rows_per_tbl.values())} rows in {len(TABLES)} tables = {sum(out['pairs'].values()):,} (person, row) pairs")
    print(f"  {'table':<22}{'rows':>8}{'visible(old)':>14}{'diff new':>10}{'diff undo':>10}")
    for t in TABLES:
        print(f"  {t:<22}{rows_per_tbl[t]:>8}{out['visible_old'][t]:>14}{out['diff_new'][t]:>10}{out['diff_undo'][t]:>10}")
    print(f"  case set per person: _my_scoped_case_ids() vs admin_scoped() and admin_sees_report(): {out['fn_case_set_visible']} visible pairs, {out['fn_case_set_diff']} differences")
    print(f"  undo restores every policy text: {out['policies_restored']}; helpers left after undo: {left or 'none'}")
    bad = sum(out["diff_new"].values()) + sum(out["diff_undo"].values()) + out["fn_case_set_diff"] + (0 if out["policies_restored"] and not left else 1)
    print("RESULT:", "IDENTICAL" if bad == 0 else f"DIFFERENT ({bad})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
