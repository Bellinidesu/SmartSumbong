#!/usr/bin/env python3
"""Step 4: standards checks, compact. (a) live portal HTTP headers/cookies (GET only), (b) Edge Functions vs config.toml, (c) migrations
hygiene and numbering gaps, (d) pgTAP coverage map, (e) secrets scan (file:line only, never values). Details: out/standards.json.
usage: python standards.py [--no-net]"""
import json, re, subprocess, sys, urllib.request, urllib.error
from collections import defaultdict
from common import *

URL = "https://smartsumbong-ph.onrender.com"
V = []   # (id, severity, text)
res = {}


def v(sev, text):
    V.append((sev, text))


# ---- (a) HTTP
def http():
    paths = ["/admin/login.php", "/admin/ping.php", "/admin/dashboard.php", "/"]
    seen = {}
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k): return None
    op = urllib.request.build_opener(NoRedirect)
    for p in paths:
        try:
            r = op.open(urllib.request.Request(URL + p, headers={"User-Agent": "sweep-check/1"}), timeout=25)
            h, code = r.headers, r.status
        except urllib.error.HTTPError as e:
            h, code = e.headers, e.code
        except Exception as e:
            seen[p] = {"error": str(e)[:80]}; continue
        seen[p] = {"code": code, "h": {k.lower(): val for k, val in h.items()}, "cookies": h.get_all("Set-Cookie") or []}
    res["http"] = {p: {"code": d.get("code"), "headers": d.get("h"), "cookies": d.get("cookies")} for p, d in seen.items() if "error" not in d}
    page = seen.get("/admin/login.php") or {}
    if "h" not in page:
        res["http_note"] = "live portal unreachable from this machine: " + str(page.get("error")); return
    h = page["h"]
    need = {"strict-transport-security": "HSTS", "content-security-policy": "CSP", "x-content-type-options": "X-Content-Type-Options", "referrer-policy": "Referrer-Policy",
            "permissions-policy": "Permissions-Policy"}
    for k, nm in need.items():
        if k not in h: v("medium" if k in ("strict-transport-security", "content-security-policy") else "low", f"login page has no {nm} header")
    if "x-frame-options" not in h and "frame-ancestors" not in h.get("content-security-policy", ""): v("medium", "login page can be framed (no X-Frame-Options or frame-ancestors)")
    csp = h.get("content-security-policy", "")
    for bad in ("unsafe-inline", "unsafe-eval"):
        if re.search(r"script-src[^;]*'" + bad + "'", csp): v("high", f"CSP script-src allows '{bad}'")
    if re.search(r"(^|;)\s*script-src[^;]*\*", csp): v("high", "CSP script-src has a wildcard")
    if "default-src" not in csp and "script-src" not in csp and csp: v("medium", "CSP sets neither default-src nor script-src")
    for d_ in ("frame-ancestors", "base-uri", "form-action"):
        if csp and d_ not in csp: v("low", f"login page CSP has no {d_} (default-src does not cover it)")
    for hd in ("server", "x-powered-by"):
        if hd in h and re.search(r"\d+\.\d+", h[hd]): v("low", f"{hd} header leaks a version: {h[hd]}")
    for p, d in seen.items():
        for c in d.get("cookies", []):
            name = c.split("=")[0]
            miss = [f for f, pat in (("Secure", r"secure"), ("HttpOnly", r"httponly"), ("SameSite", r"samesite=(lax|strict)")) if not re.search(pat, c, re.I)]
            if miss: v("medium", f"cookie {name} on {p} lacks {'/'.join(miss)}")
    for p in ("/admin/login.php", "/admin/dashboard.php"):
        d = seen.get(p, {})
        if "h" in d and d.get("code") in (200, 302):
            cc = d["h"].get("cache-control", "")
            if not re.search(r"no-store|private|no-cache", cc): v("medium", f"{p} (sign-in / signed-in page) has caching headers '{cc or 'none'}'")


# ---- (b) edge functions
def edge():
    cfg = read(ROOT / "supabase/config.toml")
    out = {}
    for d in sorted((ROOT / "supabase/functions").iterdir()):
        if not d.is_dir() or d.name.startswith("_"): continue
        code = "\n".join(read(f) for f in d.rglob("*.ts") if ".test." not in f.name)
        m = re.search(r"\[functions\." + re.escape(d.name) + r"\][^\[]*?verify_jwt\s*=\s*(true|false)", cfg, re.S)
        jwt = m.group(1) if m else "default(true)"
        cors = re.findall(r"Access-Control-Allow-Origin['\"]?\s*[:,]\s*['\"]([^'\"]+)", code) or re.findall(r"corsHeaders|cors\(", code) and ["shared"]
        shared = read(ROOT / "supabase/functions/_shared/cors.ts") if (ROOT / "supabase/functions/_shared/cors.ts").exists() else ""
        star = "'*'" in (code + shared) and "Allow-Origin" in (code + shared) and re.search(r"Allow-Origin['\"]?\s*[:,]\s*['\"]\*", code + shared)
        rate = bool(re.search(r"rate|too many|429|attempt|limit", code, re.I))
        leak = re.findall(r"(?:error|message)\s*:\s*(?:e|err|error)(?:\.message|\.stack)?|String\((?:e|err|error)\)|\$\{(?:e|err)\.message\}", code)
        auth_in_code = bool(re.search(r"Authorization|getUser|SERVICE_ROLE|x-.*secret|CRON_SECRET|timingSafe", code))
        out[d.name] = {"verify_jwt": jwt, "cors_star": bool(star), "rate_limit_mentions": rate, "error_leak_sites": len(leak), "checks_caller_in_code": auth_in_code}
        if jwt == "false" and not auth_in_code: v("high", f"edge function {d.name}: verify_jwt=false and no caller check found in code")
        if jwt == "false" and not rate and d.name in ("password-otp", "sign-upload"): v("medium", f"edge function {d.name}: public (verify_jwt=false) and no rate-limit text in code (the database may limit)")
        if leak: v("low", f"edge function {d.name}: {len(leak)} place(s) return an exception message to the caller")
        if star and jwt == "false": v("low", f"edge function {d.name}: CORS allows any origin on a public function")
    res["edge"] = out


# ---- (c) migrations
def migs():
    nums = [int(f.name[:4]) for f in migrations()]
    gaps = [n for n in range(1, max(nums) + 1) if n not in nums]
    why = {}
    for g in gaps:
        r = subprocess.run(["git", "log", "--all", "--oneline", "-n", "3", "--", f"supabase/migrations/{g:04d}_*"], cwd=ROOT, capture_output=True, text=True).stdout.strip().splitlines()
        why[g] = r[0][:90] if r else "never in git history (number skipped or file renamed)"
    dupes = [n for n in set(nums) if nums.count(n) > 1]
    nonidem = defaultdict(list)
    undo = 0
    for f in migrations():
        t = read(f); low = t.lower()
        if re.search(r"\b(undo|rollback|down:|to revert|reverse)\b", low): undo += 1
        n = f.name[:4]
        for pat, nm in ((r"create\s+table\s+(?!if\s+not\s+exists)(?!public\.[a-z_]+_x\b)", "create table"), (r"create\s+(unique\s+)?index\s+(?!if\s+not\s+exists)(?!concurrently\s+if)", "create index"),
                        (r"add\s+column\s+(?!if\s+not\s+exists)", "add column"), (r"create\s+type\s+", "create type")):
            if re.search(pat, low) and not re.search(r"do\s+\$\$|if\s+not\s+exists\s*\(", low[:0]):
                nonidem[nm].append(n)
        for m in re.finditer(r"create\s+policy\s+\"?([a-z_0-9 ]+)\"?\s+on\s+(?:public\.)?([a-z_]+)", low):
            if not re.search(r"drop\s+policy\s+if\s+exists\s+\"?" + re.escape(m.group(1).strip()), low): nonidem["create policy w/o drop-if-exists"].append(n); break
    res["migrations"] = {"count": len(nums), "gaps": why, "duplicates": dupes, "with_undo_note": undo, "non_idempotent_by_kind": {k: len(set(v_)) for k, v_ in nonidem.items()}}
    v("info", f"migrations: {len(nums)} files, gaps {gaps} ({'; '.join(f'{g}: {w}' for g, w in why.items())})")
    if dupes: v("medium", f"duplicate migration numbers: {dupes}")
    v("low", f"migrations: {undo} of {len(nums)} carry an undo/rollback note; idempotence gaps: " + ", ".join(f"{k} in {len(set(x))}" for k, x in nonidem.items()))


# ---- (d) pgTAP coverage
def coverage():
    tests = "\n".join(read(f) for f in (ROOT / "supabase/tests").glob("[0-9][0-9]_*.sql")) + "\n" + "\n".join(read(f) for f in (ROOT / "supabase/tests").rglob("*.sql") if "local" not in f.parts)
    G = grants()
    fns = [r["proname"] for r in psqlj("select distinct proname from pg_proc p where pronamespace = 'public'::regnamespace and prokind in ('f','p') and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')")]
    untested_api = sorted(n for n in fns if (G["fn"].get(n, ("-", "-"))[1] == "call" or G["fn"].get(n, ("-", "-"))[0] == "call") and not n.startswith("_") and not re.search(r"(?<![a-z_])" + re.escape(n) + r"(?![a-z_0-9])", tests))
    untested_all = sorted(n for n in fns if not re.search(r"(?<![a-z_])" + re.escape(n) + r"(?![a-z_0-9])", tests) and n not in untested_api)
    pols = psql("select tablename, policyname from pg_policies where schemaname = 'public'")
    pol_tables = sorted({t for t, _ in pols})
    untested_tables = [t for t in pol_tables if not re.search(r"(?<![a-z_])" + t + r"(?![a-z_0-9])", tests)]
    n_policies = len(pols)
    res["pgtap"] = {"functions": len(fns), "api_callable_untested": untested_api, "internal_untested": len(untested_all), "tables_with_policies": len(pol_tables), "policies": n_policies, "tables_with_policies_never_named_in_a_test": untested_tables}
    save("untested_functions.json", {"api_callable": untested_api, "internal": untested_all, "tables": untested_tables})
    if untested_api: v("medium", f"{len(untested_api)} API-callable functions are never named in any test: {', '.join(untested_api[:10])}{' ...' if len(untested_api) > 10 else ''}")
    if untested_tables: v("low", f"{len(untested_tables)} tables with row level security policies are never named in a test: {', '.join(untested_tables[:10])}")


# ---- (e) secrets scan
PATS = [(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}", "JWT-shaped token"), (r"sb_secret_[A-Za-z0-9_-]{10,}", "Supabase secret key"),
        (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key block"), (r"AKIA[0-9A-Z]{16}", "AWS key id"), (r"postgres(?:ql)?://[^:\s/]+:[^@\s]{6,}@", "database URL with a password"),
        (r"(?i)(api[_-]?secret|service[_-]?role[_-]?key|smtp_pass|client_secret|auth_token)['\"]?\s*[:=]\s*['\"][A-Za-z0-9/+_=-]{16,}['\"]", "secret-looking assignment"),
        (r"cloudinary://\d+:[A-Za-z0-9_-]+@", "Cloudinary URL with secret"), (r"ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}", "GitHub token"), (r"xox[baprs]-[A-Za-z0-9-]{10,}", "Slack token")]


def secrets():
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    hits = []
    for f in files:
        if re.search(r"\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|apk|ttf|woff2?|mp4|svg|lock|json\.gz)$", f) or "vendor/" in f or "package-lock" in f or ".test." in f: continue
        try: t = read(ROOT / f)
        except Exception: continue
        if len(t) > 3_000_000: continue
        for pat, nm in PATS:
            for m in re.finditer(pat, t):
                line = t[:m.start()].count("\n") + 1
                ctx = t[max(0, m.start() - 60): m.end() + 20].lower()
                if re.search(r"fake|example|placeholder|test|dummy|xxxx|your[_-]|\.\.\.|<[a-z_]+>|sample|never_shown|replace\(|startsWith|includes\(", ctx): continue
                hits.append(f"{f}:{line} ({nm})")
    res["secrets_scan"] = {"files": len(files), "hits": hits[:40]}
    for h in hits[:10]: v("high", "possible secret " + h)
    env_tracked = [f for f in files if re.search(r"(^|/)\.env($|\.)", f) and not f.endswith(".example")]
    for f in env_tracked: v("critical", f"{f} is tracked in git")
    v("info", f"secrets scan: {len(files)} tracked files, {len(hits)} possible hits (file:line only)")


def main():
    net = "--no-net" not in sys.argv
    for name, fn in (("http", http if net else lambda: None), ("edge", edge), ("migrations", migs), ("pgtap", coverage), ("secrets", secrets)):
        try: fn()
        except Exception as e: v("info", f"{name} check could not run: {str(e)[:120]}")
    save("standards.json", {"results": res, "violations": V})
    cnt = defaultdict(int)
    for s, _ in V: cnt[s] += 1
    print("STANDARDS " + " ".join(f"{k}={n}" for k, n in sorted(cnt.items())))
    for s, t in sorted(V, key=lambda x: ["critical", "high", "medium", "low", "info"].index(x[0])): print(f"  {s:<8}{t[:200]}")


if __name__ == "__main__":
    main()
