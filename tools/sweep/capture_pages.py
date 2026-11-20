#!/usr/bin/env python3
"""Step 2a: record every backend request each portal page makes, per rung, by running the real PHP pages against the
tests' fake Supabase (tests/browser/fake) with a logger in front. Nothing live is touched. Writes out/page_requests.json:
{tier: {page: [[method, path_with_query, prefer, body_head], ...]}}. Needs php on PATH and python. ~1-2 min."""
import json, os, shutil, subprocess, sys, tempfile, threading, time, urllib.request
from pathlib import Path
from common import ROOT, save

FAKE = ROOT / "tests" / "browser" / "fake"
sys.path.insert(0, str(FAKE))
import fake_sb as F  # noqa: E402

LOG, CUR = [], {"mark": None}
orig = F.H.route


def route(self, m):
    u = self.path
    if u.startswith("/__mark/"):
        CUR["mark"] = u.split("/__mark/")[1]
        return self.send(200, {})
    if u.startswith(("/rest/v1/", "/functions/v1/")):
        import io
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        self.rfile = io.BytesIO(body.encode())
        LOG.append((CUR["mark"], m, u, self.headers.get("Prefer") or "", body))
    return orig(self, m)


F.H.route = route
PAGES = [p.name for p in sorted((ROOT / "admin").glob("*.php")) if p.name not in ("login.php", "logout.php", "ping.php", "error.php", "token.php", "forgot-password.php", "reset-password.php", "request-access.php", "view-as.php", "view-mode.php")]
TIERS = [("super", ""), ("captain", ""), ("committee", "peace_order"), ("moderator", "peace_order")]


def main():
    from http.server import ThreadingHTTPServer
    srv = ThreadingHTTPServer(("127.0.0.1", 54399), F.H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    site = Path(tempfile.mkdtemp(prefix="sweep-site-"))
    shutil.copytree(ROOT / "admin", site / "admin")
    shutil.copy(ROOT / "tests" / "browser" / "router.php", site / "router.php")
    (site / ".env").write_text("FEATURE_CACHE_TTL=0\nGLANCE_OFFLINE=1\nSUPABASE_URL=http://127.0.0.1:54399\nNOMINATIM_URL=http://127.0.0.1:54399/nominatim\n"
                               "SUPABASE_PUBLISHABLE_KEY=fake\nCLOUDINARY_CLOUD_NAME=fake\nCLOUDINARY_UPLOAD_PRESET=fake\n")
    port = "8017"
    php = subprocess.Popen(["php", "-S", "127.0.0.1:" + port, "-t", ".", "router.php"], cwd=site, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/admin/ping.php", timeout=2)
                break
            except Exception:
                time.sleep(1)
        # a case id to open case.php with
        cid = F.REPORTS[0]["id"]
        for tier, com in TIERS:
            for pg in PAGES:
                CUR["mark"] = f"{tier}|{pg}"
                q = f"?id={cid}" if pg in ("case.php", "complaint-print.php", "certificate.php") else ""
                req = urllib.request.Request(f"http://127.0.0.1:{port}/admin/{pg}{q}", headers={"Cookie": f"ss_tier={tier}; ss_committee={com}"})
                try:
                    urllib.request.urlopen(req, timeout=30).read()
                except Exception:
                    pass
        out = {}
        for mark, m, u, pref, body in LOG:
            if not mark:
                continue
            tier, pg = mark.split("|")
            out.setdefault(tier, {}).setdefault(pg, [])
            if [m, u] not in [x[:2] for x in out[tier][pg]]:
                out[tier][pg].append([m, u, pref, body[:2000]])
        out["_fake"] = {"reports": [r["id"] for r in F.REPORTS], "admin": F.ADMIN["id"]}
        save("page_requests.json", out)
        n = sum(len(v) for k, t in out.items() if k != "_fake" for v in t.values())
        print(f"CAPTURE tiers={len(out) - 1} pages={len(PAGES)} distinct_requests={n}")
    finally:
        php.terminate()
        srv.shutdown()


if __name__ == "__main__":
    main()
