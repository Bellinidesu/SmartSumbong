#!/usr/bin/env python3
"""Step 2b: LOAD COST on the throwaway local database. Replays every backend request the portal pages make (out/page_requests.json,
from capture_pages.py) plus a short catalogue of the phone app's reads, through a local PostgREST, as the real role of each rung
(JWT, so row level security runs), at 1x (82 cases) and 250x (20,000 cases). Prints the 15 slowest (page, role, query) and the
pages over budget (200 ms of database time). Details: out/loadcost.json.
usage: python loadcost.py [--scales 1,250] [--budget 200]   (needs local_db.sh up; PostgREST at PGRST_BIN)"""
import base64, hashlib, hmac, json, os, re, subprocess, sys, time, urllib.request, urllib.error
from collections import defaultdict
from pathlib import Path
from common import ROOT, OUT, PGBIN, PORT, psql, save, read

PGRST = os.environ.get("PGRST_BIN", "C:/Users/acele/pgtmp/pgrst/artifacts/postgrest-windows-x64/postgrest.exe")
SECRET = "sweep-throwaway-secret-0123456789abcdef0123456789"
RPORT = 3011
BASE = f"http://127.0.0.1:{RPORT}"
SCALES = {1: (82, 8), 250: (20000, 2000)}


def jwt(sub):
    b = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=")
    h = b(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()); p = b(json.dumps({"role": "authenticated", "sub": sub, "exp": int(time.time()) + 86400}).encode())
    return (h + b"." + p + b"." + b(hmac.new(SECRET.encode(), h + b"." + p, hashlib.sha256).digest())).decode()


def start_postgrest():
    conf = OUT / "postgrest.conf"
    conf.write_text(f'db-uri = "postgres://authenticator@127.0.0.1:{PORT}/postgres"\ndb-schemas = "public"\ndb-anon-role = "anon"\n'
                    f'jwt-secret = "{SECRET}"\nserver-host = "127.0.0.1"\nserver-port = {RPORT}\ndb-plan-enabled = true\ndb-pool = 10\n')
    env = dict(os.environ, PATH=PGBIN + os.pathsep + os.environ.get("PATH", ""))   # postgrest needs libpq next to PostgreSQL
    p = subprocess.Popen([PGRST, str(conf)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    for _ in range(60):
        try:
            urllib.request.urlopen(urllib.request.Request(BASE + "/committees?limit=1", headers={"Authorization": "Bearer " + jwt("00000000-0000-0000-0000-000000000000")}), timeout=3)
            return p
        except Exception:
            time.sleep(0.5)
    p.terminate(); raise SystemExit("PostgREST did not start")


def users():
    q = lambda n: psql(f"select id from public.users where full_name = '{n}'")[0][0]
    return {"super": q("Sweep, Rung 1"), "captain": q("Sweep, Rung 3"), "committee": q("Sweep, Rung 4"), "moderator": q("Sweep, Rung 12"),
            "tanod": q("Sweep, Rung 25"), "resident": q("Sweep, Resident 1")}


def call(method, path, token, body=None, prefer="", plan=False, timeout=60):
    h = {"Authorization": "Bearer " + token, "Content-Type": "application/json", "Accept": "application/json"}
    if prefer: h["Prefer"] = prefer
    if plan: h["Accept"] = 'application/vnd.pgrst.plan+json; options=analyze'
    t0 = time.perf_counter()
    try:
        r = urllib.request.urlopen(urllib.request.Request(BASE + path.replace("/rest/v1", "", 1), data=body.encode() if body else None, headers=h, method=method), timeout=timeout)
        data = r.read(); code = r.status
    except urllib.error.HTTPError as e:
        data = e.read(); code = e.code
    except Exception as e:
        return 0, (time.perf_counter() - t0) * 1000, str(e)[:80]
    return code, (time.perf_counter() - t0) * 1000, data


def scans(node, out):
    if isinstance(node, dict):
        if node.get("Node Type") == "Seq Scan":
            out.append((node.get("Relation Name"), int(node.get("Actual Rows", 0) * node.get("Actual Loops", 1) + node.get("Rows Removed by Filter", 0) * node.get("Actual Loops", 1))))
        for v in node.values(): scans(v, out)
    elif isinstance(node, list):
        for v in node: scans(v, out)


def app_catalogue(me, case):
    return {"resident": [("resident-app", "GET", f"/rest/v1/reports?select=*&resident_id=eq.{me['resident']}&order=created_at.desc&limit=50", ""),
                         ("resident-app", "GET", f"/rest/v1/notifications?select=*&user_id=eq.{me['resident']}&order=created_at.desc&limit=50", ""),
                         ("resident-app", "GET", f"/rest/v1/status_logs?select=*&report_id=eq.{case}&order=created_at.asc", ""),
                         ("resident-app", "GET", "/rest/v1/reports?select=id,category,status,latitude,longitude&is_public=eq.true&limit=500", ""),
                         ("resident-app", "GET", f"/rest/v1/users?select=*&id=eq.{me['resident']}", "")],
            "tanod": [("tanod-app", "GET", f"/rest/v1/dispatches?select=*,reports(*)&tanod_id=eq.{me['tanod']}&order=created_at.desc&limit=50", ""),
                      ("tanod-app", "GET", f"/rest/v1/notifications?select=*&user_id=eq.{me['tanod']}&order=created_at.desc&limit=50", ""),
                      ("tanod-app", "GET", "/rest/v1/reports?select=*&status=in.(in_progress,validated)&order=created_at.desc&limit=50", "")]}


def measure(scale, budget):
    me = users()
    cases = {t: psql("select id from public.reports where status = 'in_progress' and handler_id is not null " + ("and committee = 'peace_order' " if t in ("committee", "moderator") else "") + "limit 6")
             for t in me}
    cap = json.loads(read(OUT / "page_requests.json")); fake = cap.pop("_fake")
    rows = []
    for tier in ("super", "captain", "committee", "moderator"):
        tok = jwt(me[tier]); real = [c[0] for c in cases[tier]] or [cases["super"][0][0]]
        mp = {fid: real[i % len(real)] for i, fid in enumerate(fake["reports"])}; mp[fake["admin"]] = me[tier]
        for page, reqs in cap.get(tier, {}).items():
            for m, u, pref, body in reqs:
                if u.startswith("/functions/"): continue
                for k, v in mp.items(): u = u.replace(k, v); body = body.replace(k, v)
                rows.append((page, tier, m, u, pref, body, tok))
    for role, qs in app_catalogue(me, cases["super"][0][0]).items():
        for pg, m, u, pref in qs: rows.append((pg, role, m, u, pref, "", jwt(me[role])))
    # one replay per distinct (role, request); the answer counts for every page that makes it. A time budget keeps the run bounded.
    uniq = {}
    for page, tier, m, u, pref, body, tok in rows:
        uniq.setdefault((tier, m, u, body), [pref, tok, []])[2].append(page)
    deadline = time.time() + float(os.environ.get("SWEEP_REPLAY_BUDGET_S", "540")); skipped = 0
    res = []
    for (tier, m, u, body), (pref, tok, pgs) in uniq.items():
        if time.time() > deadline:
            skipped += 1; continue
        code, ms, data = call(m, u, tok, body or None, pref, timeout=30)
        exe, seq = None, []
        if m == "GET" and code == 200 and ms > 8:
            c2, ms2, d2 = call("GET", u, tok, prefer=pref, plan=True, timeout=30)
            if c2 == 200:
                try:
                    pl = json.loads(d2)[0]; exe = round(pl.get("Execution Time", 0), 1); scans(pl.get("Plan"), seq)
                except Exception: pass
        for page in pgs:
            res.append({"page": page, "role": tier, "method": m, "q": re.sub(r"\s+", " ", u)[:170], "code": code, "msg": (data[:140].decode("utf-8", "replace") if code >= 400 and isinstance(data, bytes) else ""), "wall_ms": round(ms, 1), "db_ms": exe if exe is not None else round(ms, 1), "seq": [x for x in seq if x[1] > 2000][:3]})
    if skipped: print(f"  replay budget reached at {scale}x: {skipped} of {len(uniq)} distinct requests not replayed")
    save(f"loadcost_{scale}x.json", res)
    return res


def main():
    if "--summary" in sys.argv:
        return summary(None, float(sys.argv[sys.argv.index("--budget") + 1]) if "--budget" in sys.argv else 200.0)
    scales = [int(x) for x in (sys.argv[sys.argv.index("--scales") + 1] if "--scales" in sys.argv else "1,250").split(",")]
    budget = float(sys.argv[sys.argv.index("--budget") + 1]) if "--budget" in sys.argv else 200
    p = start_postgrest(); out = {}
    try:
        for sc in scales:
            n, r = SCALES[sc]
            t0 = time.time()
            subprocess.run([os.path.join(PGBIN, "psql" + (".exe" if os.name == "nt" else "")), "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-X", "-q", "-v", f"n_cases={n}", "-v", f"n_res={r}",
                            "-f", str(ROOT / "tools/sweep/sql/seed.sql")], capture_output=True, check=True)
            seed_s = round(time.time() - t0)
            time.sleep(1); call("GET", "/rest/v1/users?limit=1", jwt(users()["super"]))      # warm the schema cache
            subprocess.run(["curl", "-s", "-X", "POST", "http://127.0.0.1:%d/" % RPORT], capture_output=True)
            out[sc] = measure(sc, budget)
            try:
                import smart; smart.measure(sc)
            except Exception as e:
                print("smart.measure failed:", str(e)[:200])
            print(f"scale {sc}x: seeded in {seed_s}s, {len(out[sc])} requests replayed")
    finally:
        p.terminate()
    summary(out, budget)


def summary(out=None, budget=200.0):
    if out is None:
        out = {int(f.stem.split("_")[1][:-1]): json.load(open(f)) for f in OUT.glob("loadcost_*x.json")}
    agg = defaultdict(lambda: {"n": 0, "sum": 0.0, "max": 0.0, "slow": ""})
    for sc, rows in out.items():
        for r in rows:
            a = agg[(sc, r["page"], r["role"])]; a["n"] += 1; a["sum"] += r["db_ms"]
            if r["db_ms"] >= a["max"]: a["max"] = r["db_ms"]; a["slow"] = r["q"]
    big = max(out)
    top = sorted([(r["db_ms"], r) for r in out[big]], key=lambda x: -x[0])[:15]
    small = {(r["page"], r["role"], r["q"]): r["db_ms"] for r in out.get(1, [])}
    print(f"TOP 15 slowest queries (db ms at {big}x / at 1x):")
    for ms, r in top:
        print(f"  {ms:8.1f} / {small.get((r['page'], r['role'], r['q']), '-')!s:>6}  {r['page']:<24}{r['role']:<10}{r['q'][:90]}" + (f"  SEQ{r['seq']}" if r["seq"] else ""))
    over = sorted([(a["sum"], k) for k, a in agg.items() if k[0] == big and a["sum"] > budget], reverse=True)
    pg = [f"{k[1]}/{k[2]} {s:.0f}ms({agg[k]['n']} req)" for s, k in over]
    print(f"PAGES over {budget:.0f} ms of db time at {big}x: {len(over)} of {sum(1 for k in agg if k[0] == big)}: " + "; ".join(pg[:12]))
    chatty = sorted([(a["n"], k) for k, a in agg.items() if k[0] == big and a["n"] >= 25], reverse=True)
    print(f"N+1 / chatty pages (>=25 requests): " + "; ".join(f"{k[1]}/{k[2]}={n}" for n, k in chatty[:10]))
    seqs = defaultdict(int)
    for r in out[big]:
        for t, n in r["seq"]: seqs[t] += 1
    print("seq scans over 2,000 rows at %dx (table: queries): " % big + ", ".join(f"{t}:{n}" for t, n in sorted(seqs.items(), key=lambda x: -x[1])[:8]))
    save("loadcost.json", {"top": [r for _, r in top], "pages_over_budget": [{"page": k[1], "role": k[2], "ms": round(s)} for s, k in over], "chatty": [{"page": k[1], "role": k[2], "n": n} for n, k in chatty]})




if __name__ == "__main__":
    main()
