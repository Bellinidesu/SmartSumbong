"""Restore drill on this PC (round 3, 25 Nov 2026): a FRESH read-only dump of live, restored into a throwaway PostgreSQL 17 +
PostGIS, and proved. The nightly job (tools/restore_drill.sh) proves only that every public table comes back with its rows;
this one also proves what a restore does NOT bring back (the 23-24 Nov sign-up outage), and that the documented post-restore
steps (docs/OPERATIONS.md, "Restore") close it.

    python tools/sweep/restore_drill.py [--keep] [--reuse-dump]
      env: PG17 (dir with PostgreSQL 17 bin, PostGIS installed; default C:/Users/acele/pgtmp/pg17/pgsql/bin),
           DRILL_DIR (dump + data folder OUTSIDE the repo; default C:/Users/acele/pgtmp/r3drill), DRILL_PORT (55451)

Live is only read: the dumps are the CLI's own `supabase db dump --linked` scripts (`--dry-run`), run with a PostgreSQL 17
pg_dump because the CLI's needs Docker. The dump holds personal data: it stays in DRILL_DIR (outside the repo) and is deleted
at the end unless --keep. Prints counts, names and timings only.
"""
import json, os, re, shutil, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, live_ro, read  # noqa: E402

BIN = os.environ.get("PG17", "C:/Users/acele/pgtmp/pg17/pgsql/bin")
DIR = Path(os.environ.get("DRILL_DIR", "C:/Users/acele/pgtmp/r3drill")); DUMP = DIR / "dump"; DATA = DIR / "data"
PORT = os.environ.get("DRILL_PORT", "55451")
EXE = ".exe" if os.name == "nt" else ""
T = {}


def step(name, t0):
    T[name] = round(time.time() - t0, 1)


def bash_path(p):
    p = str(p).replace("\\", "/")
    return re.sub(r"^([A-Za-z]):", lambda m: "/" + m.group(1).lower(), p)


def dump():
    """The three files of the nightly backup, made exactly as the CLI makes them (its own script and filters)."""
    DUMP.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PATH=os.pathsep.join([BIN, os.environ["PATH"]]))
    for name, args in (("roles", ["--role-only"]), ("schema", []), ("data", ["--data-only", "--use-copy"])):
        script = subprocess.run(["supabase", "db", "dump", "--linked", "--dry-run", *args], capture_output=True, text=True,
                                encoding="utf-8", cwd=ROOT).stdout
        script = script[script.index("#!/usr/bin/env bash"):] if "#!/usr/bin/env bash" in script else script
        script = script.replace("--quote-all-identifier ", "--quote-all-identifiers ")   # Windows getopt takes no abbreviations
        f = DUMP / f"{name}.sh"
        f.write_text(script, encoding="utf-8", newline="\n")
        with open(DUMP / f"{name}.sql", "w", encoding="utf-8", newline="\n") as out:
            r = subprocess.run(["bash", bash_path(f)], stdout=out, stderr=subprocess.PIPE, text=True, env=env)
        f.unlink()   # the script holds the CLI's temporary login password
        if r.returncode or (DUMP / f"{name}.sql").stat().st_size == 0:
            sys.exit(f"dump {name} failed: {r.stderr.strip()[:200]}")


def P(db="postgres"):
    return [os.path.join(BIN, "psql" + EXE), "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", db, "-X", "-q"]


def q(sql, db="postgres"):
    r = subprocess.run(P(db) + ["-At", "-F", "\x1f", "-c", sql], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise RuntimeError(r.stderr[:300])
    return [l.split("\x1f") for l in r.stdout.splitlines() if l]


def load(path, stop=False):
    r = subprocess.run(P() + ["-v", f"ON_ERROR_STOP={1 if stop else 0}", "-f", str(path)], capture_output=True, text=True, encoding="utf-8")
    errs = [l for l in r.stderr.splitlines() if "ERROR" in l]
    return errs


def target():
    """Throwaway PostgreSQL 17: Supabase's roles/auth/storage/vault stub (as the migration checks use), pg_cron recorded only."""
    subprocess.run([os.path.join(BIN, "pg_ctl" + EXE), "-D", str(DATA), "stop", "-m", "immediate"], capture_output=True)
    shutil.rmtree(DATA, ignore_errors=True)
    subprocess.run([os.path.join(BIN, "initdb" + EXE), "-D", str(DATA), "-A", "trust", "-U", "postgres", "-E", "UTF8"], check=True, capture_output=True)
    with open(DATA / "postgresql.conf", "a") as c:
        c.write(f"\nport={PORT}\nlisten_addresses='127.0.0.1'\nfsync=off\nsynchronous_commit=off\nmax_locks_per_transaction=4000\n")
    subprocess.run([os.path.join(BIN, "pg_ctl" + EXE), "-D", str(DATA), "-l", str(DATA / "log"), "-w", "start"], check=True, capture_output=True)
    q('alter database postgres set search_path = "$user", public, extensions')
    stub = re.sub(r"(?im)^create extension pg_cron;", "", read(ROOT / "supabase" / "tests" / "local" / "supabase_stub.sql"))
    (DIR / "stub.sql").write_text(stub, encoding="utf-8")
    assert not load(DIR / "stub.sql", stop=True)
    assert not load(ROOT / "tools" / "sweep" / "sql" / "cron_stub.sql", stop=True)
    q("create publication supabase_realtime")   # every Supabase project has it (empty); the dump comments its tables out


def copy_counts(path):
    want, cur, n = {}, None, 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if cur is None:
                m = re.match(r'COPY "?([a-z_]+)"?\."?([A-Za-z0-9_]+)"? ', line)
                if m: cur, n = f"{m.group(1)}.{m.group(2)}", 0
            elif line.rstrip("\n") == "\\.":
                want[cur] = want.get(cur, 0) + n; cur = None
            else:
                n += 1
    return want


def drift(label):
    env = dict(os.environ, SWEEP_PORT=PORT, PGBIN=BIN)
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "sweep" / "drift_check.py"), "--local", "postgres"], capture_output=True,
                       text=True, encoding="utf-8", env=env)
    lines = [l for l in r.stdout.splitlines() if l.startswith(("PASS", "FAIL", "RESULT")) or l.startswith("        - ")]
    print(f"  drift check on the restored copy, {label}:")
    for l in lines:
        if not l.startswith("PASS"):
            print("   ", l.strip()[:150])
    return r.returncode


def main():
    t0 = time.time(); DIR.mkdir(parents=True, exist_ok=True)
    if "--reuse-dump" not in sys.argv or not (DUMP / "data.sql").exists():
        t = time.time(); dump(); step("dump (3 files)", t)
    sizes = {f.name: round(f.stat().st_size / 1e6, 1) for f in DUMP.glob("*.sql")}
    live_counts = {r["t"]: int(r["n"]) for r in live_ro(
        "select 'public.' || relname t, (xpath('/row/n/text()', query_to_xml(format('select count(*) n from public.%I', relname), false, true, '')))[1]::text n "
        "from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'p') "
        "and not exists (select 1 from pg_depend d where d.objid = pg_class.oid and d.deptype = 'e')")}
    for t in ("auth.users", "auth.identities", "cron.job"):
        live_counts[t] = int(live_ro(f"select count(*)::int n from {t}")[0]["n"])
    t = time.time(); target(); step("target PostgreSQL 17 + stub", t)
    # the stub's auth.users / auth.identities are cut down: give them every column the dump has (as text), so their rows load
    data_head = ""
    with open(DUMP / "data.sql", encoding="utf-8", errors="replace") as f:
        data_head = "".join(l for l in f if l.startswith('COPY "auth".'))
    for tbl in ("users", "identities"):
        m = re.search(r'^COPY "auth"\."%s" \(([^)]*)\)' % tbl, data_head, re.M)
        have = {r[0] for r in q(f"select column_name from information_schema.columns where table_schema = 'auth' and table_name = '{tbl}'")}
        for col in (re.findall(r'"([^"]+)"', m.group(1)) if m else []):
            if col not in have:
                q(f'alter table auth.{tbl} add column "{col}" text')
    t = time.time()
    errs = {n: load(DUMP / f"{n}.sql") for n in ("roles", "schema", "data")}
    step("restore roles+schema+data", t)
    print(f"RESTORE DRILL (live dump {sizes} MB) into PostgreSQL 17.11 + PostGIS 3.7 on :{PORT}")
    for n, e in errs.items():
        kinds = {}
        for l in e:
            k = re.sub(r'"[^"]*"|\b[0-9a-f-]{8,}\b|\d+', "_", l.split("ERROR:", 1)[-1].strip())[:70]
            kinds[k] = kinds.get(k, 0) + 1
        print(f"  {n}.sql: {len(e)} statements did not apply" + ("".join(f"\n      {c}x {k}" for k, c in sorted(kinds.items(), key=lambda x: -x[1])[:5]) if e else ""))
    # 1. rows
    want = copy_counts(DUMP / "data.sql")
    bad, changed, tables = [], [], 0
    for tbl, n in sorted(want.items()):
        if not (tbl.startswith("public.") or tbl in live_counts):
            continue
        tables += 1
        try:
            got = int(q(f"select count(*) from {tbl.split('.')[0]}.\"{tbl.split('.')[1]}\"")[0][0])
        except Exception:
            got = None
        if got != n: bad.append(f"{tbl} dump={n} restored={got}")
        if tbl in live_counts and live_counts[tbl] != n: changed.append(f"{tbl} {n}->{live_counts[tbl]}")
    print(f"  rows: {tables - len(bad)}/{tables} tables (public + auth.users/identities + cron.job) restored with every dumped row"
          + (f"; NOT whole: {bad[:6]}" if bad else ""))
    print(f"  live vs dump (live is in use; rows written after the dump): {len(changed)} tables changed {changed[:5]}")
    # 2. structure as restored, BEFORE the post-restore steps: what a dump cannot carry
    t = time.time(); rc_before = drift("as restored (before the post-restore steps)"); step("drift check x2", t)
    # 3. the documented post-restore steps: 0193 (auth.users triggers) + the realtime tables
    pub = [l.split("\t")[1] for l in read(ROOT / "supabase" / "drift_manifest.txt").splitlines() if l.startswith("pub\t")]
    post = ["\\i '" + (ROOT / "supabase" / "drafts" / "0193_auth_triggers_idempotent.sql").as_posix() + "'"]
    post += [f"alter publication supabase_realtime add table {t};" for t in pub]
    (DIR / "post.sql").write_text("\n".join(post) + "\n", encoding="utf-8")
    perr = load(DIR / "post.sql", stop=True)
    print(f"  post-restore steps (0193 + {len(pub)} realtime tables): {'ok' if not perr else perr[:2]}")
    rc_after = drift("after the post-restore steps")
    # 4. grants as on file
    g = subprocess.run(["bash", bash_path(ROOT / "supabase" / "tools" / "grants.sh"), "check", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", "postgres"],
                       capture_output=True, text=True, env=dict(os.environ, PATH=os.pathsep.join([BIN, os.environ["PATH"]])))
    print("  grants:", (g.stdout.strip().splitlines() or [g.stderr.strip()[:120]])[-1][:140])
    # 5. the hash chain of every case
    t = time.time()
    r = q("select count(distinct r.id), count(v.*), count(*) filter (where not v.intact), count(distinct r.id) filter (where not v.intact) "
          "from public.reports r left join lateral public.verify_report_trail(r.id) v on true")[0]
    step("verify_report_trail all cases", t)
    print(f"  hash chain: {r[0]} cases, {r[1]} trail entries checked, {r[2]} broken entries in {r[3]} cases")
    # 6. the rolled-back checks of supabase/tests on the restored copy
    t = time.time(); ok = fail = 0; fails = []
    for f in sorted((ROOT / "supabase" / "tests").glob("[0-9][0-9]_*.sql")):
        out = subprocess.run(P() + ["-f", str(f)], capture_output=True, text=True, encoding="utf-8").stderr
        ok += len(re.findall(r"(?m)^ok ", out))
        fl = re.findall(r"FAIL ([^\n]{0,90})", out)
        if "SWEEP-ROLLBACK" not in out:
            fl.append("did not reach SWEEP-ROLLBACK: " + (re.findall(r"ERROR:\s*([^\n]{0,90})", out) or ["?"])[0])
        fail += len(fl); fails += [f"{f.name}: {x}" for x in fl]
    step("supabase/tests on the restored copy", t)
    print(f"  supabase/tests on the restored copy: {ok} ok, {fail} failing checks" + "".join(f"\n      {x}" for x in fails[:12]))
    step("TOTAL", t0)
    print("  timings (s):", json.dumps(T))
    json.dump({"timings": T, "errors": {k: len(v) for k, v in errs.items()}, "rows_bad": bad, "changed": changed, "chain": r,
               "tests_failing": fails, "drift_before": rc_before, "drift_after": rc_after}, open(ROOT / "tools" / "sweep" / "out" / "restore_drill.json", "w"), indent=1)
    if "--keep" not in sys.argv:
        subprocess.run([os.path.join(BIN, "pg_ctl" + EXE), "-D", str(DATA), "stop", "-m", "immediate"], capture_output=True)
        shutil.rmtree(DIR, ignore_errors=True)
        print("  throwaway database stopped; dump and data folder deleted")


if __name__ == "__main__":
    main()
