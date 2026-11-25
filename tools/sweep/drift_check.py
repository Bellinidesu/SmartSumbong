"""Drift guard (round 3, 25 Nov 2026): is the LIVE project still what the repository says it is? READ-ONLY.

Why: on 23-24 Nov new residents could not register or sign in. Live auth.users had lost its two triggers (on_auth_user_created ->
handle_new_auth_user, auth_users_confirm_synthetic -> confirm_synthetic_auth_email), most likely in the 7 Nov Mumbai -> Singapore
move: `supabase db dump` leaves out Supabase's managed schemas (auth, storage), so a trigger a migration put ON auth.users does not
travel with a dump. Nothing in public had changed, so every public-schema check stayed green. This script checks the objects that
can drift silently, item by item, against supabase/drift_manifest.txt (built from the migrations) and the repo's own files.

    python tools/sweep/drift_check.py            check live (read-only; ~15 s; exit 1 when anything FAILs)
    python tools/sweep/drift_check.py -v         also list every differing item (names only)
    python tools/sweep/drift_check.py --local DB the SQL checks against a local database (proof that a lost trigger FAILs)
    python tools/sweep/drift_check.py --write    rebuild supabase/drift_manifest.txt from the local migrations database
                                                 (bash tools/sweep/local_db.sh up first) + a read-only snapshot of live's
                                                 Dashboard-only auth settings. Do this after adding a migration.

Read-only by construction: every SQL runs inside `begin read only ... rollback`; the CLI calls are listings (`functions list`,
`secrets list` NAMES only, `config diff`, documented read-only). Prints names, counts and hashes, never a secret value or a row.
"""
import json, os, re, sys
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, psql, live_ro, cli_json, read  # noqa: E402

MANIFEST = ROOT / "supabase" / "drift_manifest.txt"
NORM = r"regexp_replace(%s, '\s+', ' ', 'g')"   # CRLF checkouts and PG16 vs PG17 layout differ only in whitespace
CORE = f"""
select kind, key, val from (
  select 'auth_trigger' kind, t.tgname::text key, p.proname || ' enabled=' || t.tgenabled::text || ' ' || md5({NORM % 'pg_get_triggerdef(t.oid)'}) val
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal
  union all select 'cron', jobname::text, schedule || ' active=' || active::text || ' ' || md5({NORM % 'command'}) from cron.job
  union all select 'pub', schemaname || '.' || tablename, '' from pg_publication_tables where pubname = 'supabase_realtime'
  union all select 'ext', extname::text, '' from pg_extension
  union all select 'fn', p.oid::regprocedure::text, md5({NORM % 'pg_get_functiondef(p.oid)'}) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all select 'policy', tablename || '.' || policyname, md5(cmd::text || permissive::text || array_to_string(roles, ',') || '|'
      || coalesce({NORM % 'qual'}, '') || '|' || coalesce({NORM % 'with_check'}, '')) from pg_policies where schemaname = 'public'
  union all select 'trigger', c.relname || '.' || t.tgname, md5({NORM % 'pg_get_triggerdef(t.oid)'})
    from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
  union all select 'table', c.relname::text, md5(string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' '
      || a.attnotnull::text || ' ' || coalesce({NORM % 'pg_get_expr(ad.adbin, ad.adrelid)'}, ''), ',' order by a.attnum))
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
     and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') group by c.relname
) x"""
LIVE_ONLY = """
select kind, key, val from (
  select 'bucket' kind, id::text key, 'public=' || public::text || ' size=' || coalesce(file_size_limit::text, '-')
         || ' mime=' || coalesce(array_to_string(allowed_mime_types, ','), '-') val from storage.buckets
  union all select 'storage_policy', tablename || '.' || policyname, cmd || ' ' || array_to_string(roles, ',')
    from pg_policies where schemaname = 'storage'
  union all select 'vault', name, '' from vault.secrets
  union all select 'webhook', c.relname || '.' || t.tgname, '' from pg_trigger t join pg_class c on c.oid = t.tgrelid
   join pg_proc p on p.oid = t.tgfoid where p.pronamespace = 'supabase_functions'::regnamespace and not t.tgisinternal
) x"""
# Objects the migrations use that a plain local PostgreSQL only stubs (so they cannot be read from the local database).
STUBBED_EXT = ["pg_cron", "pg_net", "supabase_vault"]
# Made by hand in the Dashboard, on purpose (config.toml, send-dispatch-push): must exist on live; its body holds a key, never hashed.
WEBHOOKS = ["notifications.dispatch_push"]
# Function secrets that are optional by design (the code runs without them).
OPTIONAL_SECRETS = {"SMTP_FROM_NAME", "SEMAPHORE_API_KEY", "SEMAPHORE_SENDER_NAME"}
# Auth settings whose remote value the CLI masks; their presence is checked, never their value.
MASKED = {"auth.email.smtp.user", "auth.email.smtp.admin_email", "auth.email.smtp.pass"}


def rows_to_set(rows):
    return {(r["kind"], r["key"], r["val"]) for r in rows}


def repo_edge():
    """{slug: verify_jwt} from supabase/functions/* and config.toml (true is Supabase's default)."""
    cfg = read(ROOT / "supabase" / "config.toml")
    out = {}
    for d in sorted((ROOT / "supabase" / "functions").iterdir()):
        if d.is_dir() and not d.name.startswith("_"):
            m = re.search(r"\[functions\.%s\][^\[]*?verify_jwt\s*=\s*(true|false)" % re.escape(d.name), cfg)
            out[d.name] = (m.group(1) == "true") if m else True
    return out


def repo_secrets():
    names = set()
    for f in (ROOT / "supabase" / "functions").rglob("*.ts"):
        if ".test." in f.name or "_test" in f.parts:
            continue
        names |= set(re.findall(r"""\b(?:get|env)\(\s*["']([A-Z][A-Z0-9_]{2,})["']""", read(f)))
    return names


def auth_snapshot():
    """Non-secret Auth/pooler settings live holds beyond config.toml, from the read-only `supabase config diff`."""
    d = cli_json("config", "diff", "--output-format", "json")
    snap, declared = {}, []
    for c in d.get("changes", []):
        p = ".".join(map(str, c["path"]))
        rv = c.get("remote")
        rv = rv[0] if isinstance(rv, list) and len(rv) == 1 else rv
        if p in MASKED:
            snap[p] = "set" if rv else "EMPTY"
        elif c.get("declared"):
            declared.append(p)
        else:
            snap[p] = json.dumps(rv, sort_keys=True)
    return snap, declared


def write():
    lines = sorted("\t".join(t) for t in rows_to_set(psql_rows(CORE)))
    bodies = psql("select string_agg(pg_get_functiondef(p.oid), ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace "
                  "and p.prokind in ('f', 'p') and p.prosrc like '%decrypted_secrets%'", raw=True)
    vault = sorted(set(re.findall(r"name\s*=\s*'([a-z0-9_]+)'", bodies)))
    snap, _ = auth_snapshot()
    extra = [f"ext\t{e}\t" for e in STUBBED_EXT] + [f"webhook\t{w}\t" for w in WEBHOOKS] + [f"vault\t{v}\t" for v in vault]
    extra += [f"edge\t{k}\tverify_jwt={str(v).lower()}" for k, v in repo_edge().items()]
    extra += [f"secret\t{s}\t{'optional' if s in OPTIONAL_SECRETS else 'required'}" for s in sorted(repo_secrets() | OPTIONAL_SECRETS)]
    extra += [f"auth\t{k}\t{v}" for k, v in sorted(snap.items())]
    last = sorted(p.name for p in (ROOT / "supabase" / "migrations").glob("*.sql"))[-1]
    head = [f"# drift_manifest.txt: what live must hold outside what grants.txt already covers. Generated by tools/sweep/drift_check.py --write",
            f"# from the migrations up to {last} (local database) + the repo's functions/config.toml + live's Dashboard-only auth settings",
            f"# ({datetime.now(timezone.utc):%Y-%m-%d}). Names and md5 hashes of object definitions only. Never edit by hand.",
            f"# built-from\t{last}"]
    MANIFEST.write_text("\n".join(head + sorted(set(lines + extra))) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {MANIFEST.relative_to(ROOT).as_posix()}: {len(lines) + len(extra)} lines (built from {last})")


def psql_rows(sql, db="postgres"):
    return [{"kind": k, "key": a, "val": b} for k, a, b in psql(sql, db=db)]


def check(verbose, local_db=None):
    """local_db: run only the SQL checks against a LOCAL database instead (the negative test: a copy with the triggers dropped)."""
    man = [l.split("\t") for l in read(MANIFEST).splitlines() if l and not l.startswith("#")]
    built = re.search(r"# built-from\t(\S+)", read(MANIFEST)).group(1)
    last = sorted(p.name for p in (ROOT / "supabase" / "migrations").glob("*.sql"))[-1]
    exp = {}
    for k, key, val in man:
        exp.setdefault(k, {})[key] = val
    live = {}
    for r in (psql_rows(CORE, local_db) if local_db else live_ro(CORE) + live_ro(LIVE_ONLY)):
        live.setdefault(r["kind"], {})[r["key"]] = r["val"]
    res = []

    def report(name, ok, summary, items=()):
        res.append(("PASS" if ok is True else "FAIL" if ok is False else "INFO", name, summary, list(items)))

    def exact(kind, name, ignore_live=()):
        e, l = exp.get(kind, {}), {k: v for k, v in live.get(kind, {}).items() if k not in ignore_live}
        missing = sorted(set(e) - set(l)); extra = sorted(set(l) - set(e)); diff = sorted(k for k in set(e) & set(l) if e[k] != l[k])
        bad = [f"missing {x}" for x in missing] + [f"extra {x}" for x in extra] + [f"differs {x}" for x in diff]
        report(name, not bad, f"{len(l)} live / {len(e)} repo" + (f": {len(missing)} missing, {len(extra)} extra, {len(diff)} differ" if bad else ""), bad)

    exact("auth_trigger", "auth.users triggers (sign-up, synthetic-email confirm)")
    exact("cron", "pg_cron jobs (name, schedule, active, command hash)")
    exact("pub", "realtime publication tables")
    exact("fn", "public functions (definition hash)")
    exact("policy", "public RLS policies (definition hash)")
    exact("trigger", "public triggers (definition hash)", ignore_live=WEBHOOKS)
    exact("table", "public tables and views (columns hash)")
    if local_db:
        return finish(res, verbose, f"LOCAL database {local_db} (SQL checks only)")
    miss = sorted(set(exp.get("ext", {})) - set(live.get("ext", {})))
    report("extensions the migrations use", not miss, f"{len(exp.get('ext', {}))} needed, {len(miss)} missing; live has "
           f"{len(set(live.get('ext', {})) - set(exp.get('ext', {})))} more (Supabase's own)", [f"missing {m}" for m in miss])
    miss = sorted(set(exp.get("webhook", {})) - set(live.get("webhook", {})))
    report("Dashboard database webhooks", not miss, f"{len(live.get('webhook', {}))} live / {len(exp.get('webhook', {}))} expected",
           [f"missing {m}" for m in miss] + [f"extra {x}" for x in sorted(set(live.get("webhook", {})) - set(exp.get("webhook", {})))])
    b, sp = live.get("bucket", {}), live.get("storage_policy", {})
    report("storage buckets + storage.objects policies (repo: none; media is on Cloudinary)", not b and not sp,
           f"{len(b)} buckets, {len(sp)} storage policies", [f"bucket {k} {v}" for k, v in b.items()] + [f"policy {k} {v}" for k, v in sp.items()])
    miss = sorted(set(exp.get("vault", {})) - set(live.get("vault", {})))
    report("Vault secret names", not miss, f"{len(exp.get('vault', {}))} needed, {len(miss)} missing, {len(set(live.get('vault', {})) - set(exp.get('vault', {})))} unused",
           [f"missing {m}" for m in miss] + [f"unused {x}" for x in sorted(set(live.get("vault", {})) - set(exp.get("vault", {})))])
    # grants: the same check the nightly backup job runs (supabase/tools/grants.sh), through the read-only CLI
    gsql = "\n".join(l for l in read(ROOT / "supabase" / "tools" / "grants.sql").splitlines() if not l.lstrip().startswith("--"))
    lg = {r["line"] for r in live_ro(gsql)}
    fg = {l for l in read(ROOT / "supabase" / "grants.txt").splitlines() if l}
    report("grants (anon/authenticated per object) vs supabase/grants.txt", lg == fg, f"{len(lg)} live / {len(fg)} on file",
           [f"file only: {x}" for x in sorted(fg - lg)] + [f"live only: {x}" for x in sorted(lg - fg)])
    # Edge Functions + verify_jwt
    fl = {f["slug"]: f for f in cli_json("functions", "list", "-o", "json")}
    bad = []
    for slug, v in exp.get("edge", {}).items():
        want = v == "verify_jwt=true"
        if slug not in fl: bad.append(f"missing {slug}")
        elif fl[slug].get("verify_jwt") != want: bad.append(f"{slug} verify_jwt live={fl[slug].get('verify_jwt')} repo={want}")
        elif fl[slug].get("status") != "ACTIVE": bad.append(f"{slug} status {fl[slug].get('status')}")
    bad += [f"extra {s}" for s in sorted(set(fl) - set(exp.get("edge", {})))]
    report("Edge Functions + verify_jwt", not bad, f"{len(fl)} live / {len(exp.get('edge', {}))} repo", bad)
    # function secret NAMES (the value field of the listing is never read)
    names = {s["name"] for s in cli_json("secrets", "list", "-o", "json")}
    req = {k for k, v in exp.get("secret", {}).items() if v == "required"}
    opt = {k for k, v in exp.get("secret", {}).items() if v == "optional"}
    report("function secret names (required by the code)", req <= names, f"{len(req & names)}/{len(req)} required set",
           [f"missing {m}" for m in sorted(req - names)])
    if opt - names:
        report("optional function secrets not set", None, ", ".join(sorted(opt - names)))
    # Auth config: declared blocks must match config.toml, Dashboard-only settings must match the snapshot
    snap, declared = auth_snapshot()
    bad = [f"config.toml differs: {p}" for p in declared]
    bad += [f"{k}: {'set' if k in MASKED else snap[k]} (manifest {exp.get('auth', {}).get(k)})" for k in sorted(snap) if exp.get("auth", {}).get(k) != snap[k]]
    bad += [f"no longer differs from defaults: {k}" for k in sorted(set(exp.get("auth", {})) - set(snap) - MASKED)]   # a masked key
    # with no change line means SMTP_USER is set in this terminal and equals live: that is a match
    report("auth config (smtp host = config.toml, smtp user set, Dashboard-only settings)", not bad,
           f"smtp user {snap.get('auth.email.smtp.user', 'as config.toml')}; {len(snap)} settings compared", bad)
    if built != last:
        report("manifest age", None, f"built from {built}, repo has {last}: rebuild with --write (differences below may be the new migration)")

    return finish(res, verbose, "live")


def finish(res, verbose, what):
    print(f"DRIFT CHECK {what} vs repo, read-only, {datetime.now(timezone.utc):%Y-%m-%d %H:%M} UTC")
    for st, name, summary, items in res:
        print(f"{st:4}  {name}: {summary}")
        for x in items[: (100 if verbose else 4)]:
            print(f"        - {x}")
        if len(items) > 4 and not verbose:
            print(f"        ... {len(items) - 4} more (-v)")
    nf = sum(1 for r in res if r[0] == "FAIL")
    print(f"RESULT: {sum(1 for r in res if r[0] == 'PASS')} PASS, {nf} FAIL, {sum(1 for r in res if r[0] == 'INFO')} INFO")
    return 1 if nf else 0


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    else:
        sys.exit(check("-v" in sys.argv, sys.argv[sys.argv.index("--local") + 1] if "--local" in sys.argv else None))
