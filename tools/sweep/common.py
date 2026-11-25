"""Shared helpers for the sweep tools. Stdlib only. Python 3.9+."""
import json, os, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "sweep" / "out"
OUT.mkdir(parents=True, exist_ok=True)
PGBIN = os.environ.get("PGBIN", "C:/Users/acele/pgtmp/pg/pgsql/bin")
PORT = os.environ.get("SWEEP_PORT", "55441")
EXE = ".exe" if os.path.exists(os.path.join(PGBIN, "psql.exe")) else ""


def psql(sql, db="postgres", user="postgres", raw=False, setup=""):
    """Run SQL on the throwaway local database; rows come back as lists of strings."""
    r = subprocess.run([os.path.join(PGBIN, "psql" + EXE), "-h", "127.0.0.1", "-p", PORT, "-U", user, "-d", db, "-X", "-At",
                        "-F", "\x1f", "-v", "ON_ERROR_STOP=1", "-c", setup + sql], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise RuntimeError(r.stderr.strip()[:500])
    return r.stdout if raw else [l.split("\x1f") for l in r.stdout.splitlines() if l != ""]


def psqlj(sql, **kw):
    """Rows as dicts (JSON through psql), safe for multi-line values such as function bodies."""
    out = psql("select coalesce(json_agg(t), '[]'::json) from (" + sql + ") t", raw=True, **kw)
    return json.loads(re.sub(r"\A(?:SET\n)+", "", out))   # a `setup` such as `set search_path` prints SET first


def live(sql):
    """READ-ONLY query on the live project through the linked CLI (SELECT / EXPLAIN only)."""
    if not re.match(r"\s*(select|with|explain|show)\b", sql, re.I) or re.search(r"\banalyze\b|;\s*\S", sql, re.I):
        raise RuntimeError("live() is read-only: one SELECT / EXPLAIN (never ANALYZE) per call")
    r = subprocess.run(["supabase", "db", "query", "--linked", sql], capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    m = re.search(r"\{.*\}", r.stdout, re.S)
    if not m:
        raise RuntimeError((r.stderr or r.stdout)[:300])
    return json.loads(m.group(0)).get("rows", [])


def live_ro(sql, setup=""):
    """READ-ONLY query on live inside `begin read only ... rollback` (the database itself refuses any write).
    `setup` may hold `set local ...` / `select set_config(...)` lines (read-only impersonation); `sql` is one SELECT/WITH."""
    if not re.match(r"\s*(select|with)\b", sql, re.I) or ";" in sql.rstrip().rstrip(";"):
        raise RuntimeError("live_ro() takes one SELECT / WITH")
    if re.search(r"\b(insert|update|delete|truncate|alter|drop|create|grant|revoke|copy|call|do)\b", setup, re.I):
        raise RuntimeError("live_ro() setup may only set settings")
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
        f.write("begin read only;\n" + setup + "\n" + sql.rstrip().rstrip(";") + ";\nrollback;\n")
    try:
        r = subprocess.run(["supabase", "db", "query", "--linked", "-f", f.name], capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    finally:
        os.unlink(f.name)
    m = re.search(r"\{.*\}", r.stdout, re.S)
    if not m:
        raise RuntimeError((r.stderr or r.stdout)[:300])
    d = json.loads(m.group(0))
    if d.get("_tag") == "Error" or "rows" not in d:
        raise RuntimeError(str(d.get("error", d))[:300])
    return d["rows"]


def cli_json(*args):
    """A read-only Supabase CLI listing as JSON (functions list, secrets list, config diff)."""
    r = subprocess.run(["supabase", *args], capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    m = re.search(r"[\[{].*[\]}]", r.stdout, re.S)
    if not m:
        raise RuntimeError(f"supabase {' '.join(args)}: " + (r.stderr or r.stdout)[:200])
    return json.loads(m.group(0))


def save(name, obj):
    (OUT / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False, default=str), encoding="utf-8")


def read(p):
    return Path(p).read_text(encoding="utf-8", errors="replace")


def grants():
    """supabase/grants.txt -> {'fn'|'table'|'view'|'seq': {name: (anon, authenticated)}}"""
    g = {"fn": {}, "table": {}, "view": {}, "seq": {}}
    for line in read(ROOT / "supabase" / "grants.txt").splitlines():
        m = re.match(r"(fn|table|view|seq) (\S+?)(\(.*\))? anon=(\S+) authenticated=(\S+)", line)
        if m:
            g[m.group(1)][m.group(2)] = (m.group(4), m.group(5))
    return g


def php_files():
    a = ROOT / "admin"
    return sorted(list(a.glob("*.php")) + list((a / "includes").glob("*.php")))


def lineno(text, pos):
    return text.count("\n", 0, pos) + 1


def migrations():
    return sorted((ROOT / "supabase" / "migrations").glob("*.sql"))


def client_code():
    """Every file that can call the backend: admin php/js, mobile dart, edge functions."""
    out = {}
    for base, exts in (("admin", (".php", ".js")), ("mobile", (".dart",)), ("supabase/functions", (".ts", ".js"))):
        for f in (ROOT / base).rglob("*"):
            if f.suffix in exts and not set(f.parts) & {"node_modules", ".dart_tool", "build", "vendor"} and "assets/vendor" not in f.as_posix():
                out[f.relative_to(ROOT).as_posix()] = read(f)
    return out
