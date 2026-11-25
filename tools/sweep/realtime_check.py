"""Realtime per role (round 3, 25 Nov 2026): can a subscriber receive a change to a row they may not read? Runs on a LOCAL copy of live
(the restore drill's database, `restore_drill.py --keep`), never on live.

How Supabase Realtime decides (realtime.apply_rls on live, read 25 Nov): for each change and each subscriber it sets `role` and
`request.jwt.claims` with set_config(..., true) in the same session, one subscriber after another, and runs a prepared
`select ... from <table> where <pk> = $1` under row level security: the subscriber gets the change only if that returns the row.
DELETE events skip the check and carry only the primary key (old_record is cut to the key when RLS is on).

This script replays exactly that for every row of every published table and every test role: in ONE session, cycling through the
roles (forwards and backwards, so state left by one subscriber would show up in the next), a per-row check; and compares it with
the set each role reads in a fresh session. Any difference = a subscriber would be told about a row they cannot read, or miss one.

    python tools/sweep/realtime_check.py     env: PG17, DRILL_PORT (55451), SWEEP_ACTORS_FILE (as live_timing.py)
"""
import os, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, read, save  # noqa: E402

BIN = os.environ.get("PG17", "C:/Users/acele/pgtmp/pg17/pgsql/bin")
PORT = os.environ.get("DRILL_PORT", "55451")
ACTORS = [a.split(":") for a in re.search(r'ACTORS="([^"]+)"', read(os.environ.get(
    "SWEEP_ACTORS_FILE", "C:/Users/acele/SmartSumbong-archive/tools/live_snapshot.sh"))).group(1).split()]
TABLES = [l.split("\t")[1].split(".")[1] for l in read(ROOT / "supabase" / "drift_manifest.txt").splitlines() if l.startswith("pub\t")]


def psql(sql):
    r = subprocess.run([os.path.join(BIN, "psql"), "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", "postgres", "-X", "-q", "-At",
                        "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise RuntimeError(r.stderr[:300])
    return r.stdout.strip()


def claims(uid):
    return f"""{{"sub":"{uid}","role":"authenticated"}}"""


def main():
    # 1. each role's visible ids, fresh session per role and table
    fresh = {}
    for who, uid in ACTORS:
        script = "begin;\nset local role authenticated;\n" + f"select 'claims', set_config('request.jwt.claims', '{claims(uid)}', true) is not null, 0;\n"
        for t in TABLES:
            script += f"select '{t}', md5(coalesce(string_agg(id::text, ',' order by id::text), '')), count(*) from public.{t};\n"
        script += "rollback;\n"
        r = subprocess.run([os.path.join(BIN, "psql"), "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", "postgres", "-X", "-q", "-At",
                            "-F", " ", "-v", "ON_ERROR_STOP=1"], input=script, capture_output=True, text=True, encoding="utf-8")
        if r.returncode:
            sys.exit(r.stderr[:300])
        for l in r.stdout.splitlines():
            t, h, n = l.split(" ")
            if t != "claims":
                fresh[(who, t)] = (h, int(n))
    # 2. the apply_rls replay: one session, roles switched per subscriber, a per-row check for every row (forwards, then backwards)
    sim_sql = """
create temp table rt_sim (pass int, who text, tbl text, h text, n int);
create or replace function pg_temp.rt_check(p_pass int, p_actors text[][], p_tables text[]) returns void language plpgsql as $f$
declare t text; a int; ids uuid[]; sample uuid[]; pk uuid; ok boolean; seen text[]; full_set text[]; h text; miss int;
begin
  foreach t in array p_tables loop
    execute format('select array_agg(id order by id) from public.%I', t) into ids;   -- every row, as the database owner
    -- per-row checks (one statement per row, as apply_rls): every row; above 2,000 rows a fixed sample of 2,000
    if coalesce(array_length(ids, 1), 0) > 2000 then
      select array_agg(x) into sample from unnest(ids) with ordinality u(x, i) where i % (array_length(ids, 1) / 2000) = 0;
    else sample := ids; end if;
    for a in 1 .. array_length(p_actors, 1) loop
      seen := '{}';
      perform set_config('role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', p_actors[a][2], 'role', 'authenticated')::text, true);
      foreach pk in array coalesce(sample, '{}') loop
        execute format('select exists (select 1 from public.%I where id = $1)', t) into ok using pk;
        if ok then seen := seen || pk::text; end if;
      end loop;
      -- every row in one statement, same role and claims: the full visible set
      execute format('select array_agg(x::text) from unnest($1) x where exists (select 1 from public.%I where id = x)', t) into full_set using ids;
      perform set_config('role', 'postgres', true);
      select count(*) into miss from unnest(sample) x where (x::text = any(seen)) <> (x::text = any(coalesce(full_set, '{}')));
      select md5(coalesce(string_agg(x, ',' order by x), '')) into h from unnest(coalesce(full_set, '{}')) x;
      insert into rt_sim values (p_pass, p_actors[a][1], t, h || ':' || miss || ':' || coalesce(array_length(sample, 1), 0), coalesce(array_length(full_set, 1), 0));
    end loop;
  end loop;
end $f$;
"""
    arr = lambda acts: "array[" + ",".join(f"array['{w}','{u}']" for w, u in acts) + "]"
    tabs = "array[" + ",".join(f"'{t}'" for t in TABLES) + "]"
    script = "begin;\n" + sim_sql + f"select pg_temp.rt_check(1, {arr(ACTORS)}, {tabs});\nselect pg_temp.rt_check(2, {arr(ACTORS[::-1])}, {tabs});\n" \
             "select pass, who, tbl, h, n from rt_sim;\nrollback;\n"
    r = subprocess.run([os.path.join(BIN, "psql"), "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", "postgres", "-X", "-q", "-At",
                        "-F", " ", "-v", "ON_ERROR_STOP=1"], input=script, capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        sys.exit(r.stderr[:300])
    diffs, pairs, rows = [], 0, 0
    checks = 0
    for l in r.stdout.splitlines():
        if len(l.split(" ")) != 5:
            continue   # the void rt_check() calls print empty lines
        p, who, t, hms, n = l.split(" ")
        h, miss, ns = hms.split(":")
        pairs += 1; checks += int(ns)
        if fresh.get((who, t)) != (h, int(n)):
            diffs.append(f"pass {p} {who} {t}: realtime check {n} rows vs fresh read {fresh.get((who, t), ('-', '-'))[1]}")
        if int(miss):
            diffs.append(f"pass {p} {who} {t}: {miss} rows where the one-statement-per-row check and the set disagree")
    total = {t: int(psql(f"select count(*) from public.{t}")) for t in TABLES}
    print(f"REALTIME per role on the restored copy: {len(TABLES)} published tables ({sum(total.values())} rows), {len(ACTORS)} test roles, "
          f"{pairs} (pass, role, table) sets; {checks} one-statement-per-row checks (status_logs: 2,000-row sample per role and pass, every row in the set check)")
    print(f"  per-row realtime check (one session, roles switched) vs fresh read per role: {len(diffs)} differences" + "".join(f"\n    {d}" for d in diffs[:10]))
    vis = {}
    for (who, t), (h, n) in fresh.items():
        vis.setdefault(who, []).append(f"{t}={n}")
    for who, v in vis.items():
        print(f"  {who:10} sees " + " ".join(v))
    save("realtime_check.json", {"tables": total, "diffs": diffs, "fresh": {f"{w}|{t}": v for (w, t), v in fresh.items()}})
    return 1 if diffs else 0


if __name__ == "__main__":
    sys.exit(main())
