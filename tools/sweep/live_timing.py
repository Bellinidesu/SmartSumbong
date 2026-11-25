"""Real round trips from this PC to the live database in Singapore, and the main SMART/page queries timed AS EACH TEST ROLE at
today's live size (round 3, 25 Nov 2026). READ-ONLY: one psql session inside `begin read only ... rollback`, the role switched
with `set local role authenticated` + the JWT claims (the same read-only impersonation as live_snapshot.sh). No ANALYZE.

    python tools/sweep/live_timing.py [--repeat 5]
      env: PG17 (PostgreSQL 17 bin with psql), SWEEP_ACTORS_FILE (a file with ACTORS="label:uuid ..." of the TEST accounts;
           default the archive's live_snapshot.sh: the ids are not kept in this public repo)

Connects with the Supabase CLI's own temporary login (read from its `db dump --dry-run` script, never printed).
Each query runs N times; prints the median client-observed time and an estimate of the database's own time: the fastest run
minus the fastest `select 1` (robust to the ~200-250 ms network stalls seen from this PC, which hit random single queries).
"""
import os, re, statistics, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, read, save  # noqa: E402

BIN = os.environ.get("PG17", "C:/Users/acele/pgtmp/pg17/pgsql/bin")
N = int(sys.argv[sys.argv.index("--repeat") + 1]) if "--repeat" in sys.argv else 5
ACTORS = re.search(r'ACTORS="([^"]+)"', read(os.environ.get("SWEEP_ACTORS_FILE", "C:/Users/acele/SmartSumbong-archive/tools/live_snapshot.sh"))).group(1).split()
ADMIN = {"super", "captain", "committee", "moderator"}
QUERIES = {   # label -> (who may run it, sql)   the slowest page reads of the sweep's capture + the SMART engine entry points
    "select 1 (round trip)": ("all", "select 1"),
    "smart_queue()": ("admin", "select count(*) from public.smart_queue()"),
    "smart_module()": ("admin", "select length(public.smart_module()::text)"),
    "cases.php list (reports visible)": ("all", "select count(*) from (select id, status, category, created_at from public.reports where deleted_at is null order by created_at desc limit 50) x"),
    "cases.php committee tab counts": ("admin", "select count(*) from public.reports r where r.deleted_at is null and public.case_committee(r) = 'peace_order'"),
    "notifications (own, newest 30)": ("all", "select count(*) from (select id from public.notifications order by created_at desc limit 30) x"),
    "users visible": ("all", "select count(*) from public.users"),
    "dispatches visible": ("all", "select count(*) from public.dispatches"),
}


def cli_env():
    s = subprocess.run(["supabase", "db", "dump", "--linked", "--dry-run"], capture_output=True, text=True, encoding="utf-8", cwd=ROOT).stdout
    env = dict(os.environ)
    for k, v in re.findall(r'^export (PG[A-Z]+)="?([^"\n]*)"?$', s, re.M):
        env[k] = v
    if "PGPASSWORD" not in env:
        sys.exit("could not read the CLI's temporary login")
    return env


def main():
    env = cli_env()
    lines = ["\\timing on", "begin read only;"]
    plan = []
    for a in [x for x in ACTORS if x.split(":")[0] in ADMIN | {"resident", "tanod"}]:
        who, uid = a.split(":")
        lines += ["reset role;", "set local role authenticated;",
                  f"select set_config('request.jwt.claims', '{{\"sub\":\"{uid}\",\"role\":\"authenticated\"}}', true);"]
        for label, (scope, sql) in QUERIES.items():
            if scope == "admin" and who not in ADMIN:
                continue
            for _ in range(N):
                lines.append(f"\\echo @@ {who}|{label}")
                lines.append(sql + ";")
            plan.append((who, label))
    lines.append("rollback;")
    script = "\n".join(lines) + "\n"
    t0 = time.time()
    r = subprocess.run([os.path.join(BIN, "psql"), "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"], input=script, capture_output=True,
                       text=True, encoding="utf-8", env=env)
    wall = time.time() - t0
    if r.returncode:
        sys.exit("live timing failed: " + r.stderr[:300])
    cur, res = None, {}
    for l in r.stdout.splitlines():
        if l.startswith("@@ "):
            cur = l[3:]
        elif cur and re.fullmatch(r"[\d.]+", l):
        elif l.startswith("Time: ") and cur:
            res.setdefault(cur, []).append(float(re.match(r"Time: ([\d.]+) ms", l).group(1))); cur = None
    rtts = [v for k, vs in res.items() if k.endswith("|select 1 (round trip)") for v in vs]
    rtt, rtt_min = statistics.median(rtts), min(rtts)
    print(f"LIVE TIMING (read-only, {N}x each, median; host {env.get('PGHOST', '?').split('.')[0]}...; whole session {wall:.1f} s incl. connect)")
    print(f"  round trip select 1: median {rtt:.1f} ms (all roles: min {min(v for k, vs in res.items() if k.endswith('round trip)') for v in vs):.1f}, "
          f"max {max(v for k, vs in res.items() if k.endswith('round trip)') for v in vs):.1f})")
    out = {"rtt_median_ms": rtt, "rtt_min_ms": rtt_min, "repeat": N, "rows": []}
    labels = [l for l in QUERIES if l != "select 1 (round trip)"]
    print("  query (ms: median client / DB est. = fastest run - fastest round trip)" + "  ".join(f"{a.split(':')[0]:>9}" for a in ACTORS if a.split(':')[0] in ADMIN | {'resident', 'tanod'}))
    for label in labels:
        cells = []
        for a in ACTORS:
            who = a.split(":")[0]
            if who not in ADMIN | {"resident", "tanod"}:
                continue
            v = res.get(f"{who}|{label}")
            if v:
                m, d = statistics.median(v), max(min(v) - rtt_min, 0); cells.append(f"{m:5.0f}/{d:5.1f}")
                out["rows"].append({"who": who, "q": label, "client_median_ms": m, "client_min_ms": min(v), "db_est_ms": d})
            else:
                cells.append(f"{'-':>9}")
        print(f"  {label:58}" + "  ".join(f"{c:>9}" for c in cells))
    save("live_timing.json", out)


if __name__ == "__main__":
    main()
