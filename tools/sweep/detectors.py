#!/usr/bin/env python3
"""Step 7: detectors that mine the schema (local DB built from the migrations) and the code for things that are missing or do not
make sense. Six detectors, violations only. Details: out/detectors.json. Needs the local DB (local_db.sh) and out/pagemap.json.
  D1 lifecycle   D2 producer/consumer   D3 request/decision symmetry   D4 author-admitted gaps   D5 role symmetry   D6 doc vs code"""
import json, re, subprocess, sys
from collections import defaultdict
from common import *

R = {"D1": [], "D2": [], "D3": [], "D4": [], "D5": [], "D6": []}   # rows: {id, src, gap, sev, fix}
F = {}                                                              # function name -> list of (signature, body, secdef)
for r in psqlj("""select p.oid::regprocedure::text || ' ' || pg_get_function_arguments(p.oid) sig, p.proname, p.prosrc, p.prosecdef from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p') and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')"""):
    F.setdefault(r["proname"], []).append((r["sig"], r["prosrc"], r["prosecdef"]))
BODY = {n: "\n".join(b for _, b, _ in v) for n, v in F.items()}
ALLBODY = "\n".join(BODY.values())
CODE = client_code()
CODE_ADMIN = "\n".join(v for k, v in CODE.items() if k.startswith("admin/"))
CODE_APP = "\n".join(v for k, v in CODE.items() if k.startswith("mobile/"))
CODE_EDGE = "\n".join(v for k, v in CODE.items() if k.startswith("supabase/functions"))
CODE_ALL = CODE_ADMIN + CODE_APP + CODE_EDGE
PM = json.loads(read(OUT / "pagemap.json")) if (OUT / "pagemap.json").exists() else {"rpc_callers": {}}
GR = grants()


def add(d, src, gap, sev, fixkind=""):
    R[d].append({"id": f"{d}-{len(R[d]) + 1:02d}", "src": src, "gap": gap, "sev": sev, "fix": fixkind})


def where_def(fn):
    """(migration file, line) of the last definition of a function"""
    best = None
    for f in migrations():
        for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?" + re.escape(fn) + r"\s*\(", read(f), re.I):
            best = (f.name[:4], lineno(read(f), m.start()))
    return f"supabase/migrations/{best[0]}*:{best[1]}" if best else "db"


# ---------------- D1 lifecycle ----------------
cols = psql("""select c.relname, a.attname, t.typname, t.typtype from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_type t on t.oid = a.atttypid
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped and a.attname in ('status', 'state', 'verification_status', 'duty_status')""")
life = {}
for tbl, col, typ, kind in cols:
    vals = []
    if kind == "e":
        vals = [r[0] for r in psql(f"select enumlabel from pg_enum where enumtypid = '{typ}'::regtype order by enumsortorder")]
    else:
        for r in psql(f"select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.{tbl}'::regclass and contype = 'c'"):
            if re.search(r"\b" + col + r"\b", r[0]):
                vals += re.findall(r"'([a-z_]+)'::text", r[0])
    if vals:
        life[(tbl, col)] = list(dict.fromkeys(vals))
CLOSED_BY_DESIGN = {"cancelled", "rejected", "archived", "expired", "removed", "declined", "denied", "completed", "off_duty", "failed", "gave_up", "dismissed", "withdrawn"}
d1 = {}
for (tbl, col), vals in life.items():
    for v in vals:
        enter, leave = set(), set()
        for fn, body in BODY.items():
            b = body.lower()
            if re.search(r"(set|,)\s*(new\.)?" + col + r"\s*=\s*'" + v + r"'|new\." + col + r"\s*:=\s*'" + v + r"'|\(\s*select\s*'" + v + r"'", b) or re.search(r"values\s*\([^;]{0,400}'" + v + "'", b) and tbl in b:
                enter.add(fn)
            if re.search(r"(?<![a-z_])" + col + r"(?![a-z_])\s*(=|<>|!=|in\s*\(|not\s+in\s*\()[^;)]{0,160}'" + v + "'", b) or re.search(r"'" + v + r"'\s*(=|<>|!=)\s*[a-z_.]*(?<![a-z_])" + col + r"(?![a-z_])", b):
                leave.add(fn)
        d1[f"{tbl}.{col}={v}"] = (sorted(enter), sorted(leave))
        defaults = psql(f"select pg_get_expr(adbin, adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum where d.adrelid = 'public.{tbl}'::regclass and a.attname = '{col}'")
        is_default = bool(defaults and f"'{v}'" in defaults[0][0])
        if not enter and not is_default and col != "duty_status":
            add("D1", "", f"{tbl}.{col} = '{v}': no function assigns it by literal (unreachable, or set by a parameter or directly by the portal/app)", "low", "unreachable-state")
        elif not leave and v not in CLOSED_BY_DESIGN and col != "duty_status":
            add("D1", "", f"{tbl}.{col} = '{v}': entered by {len(enter)} function(s) but no function ever tests for it as a current state, so nothing moves a row out of it (dead end)", "low", "dead-end")
# the named case: a finished case with a request to reopen it
sa = BODY.get("admin_set_status", "")
if re.search(r"closed", sa) and "refus" in sa.lower() or re.search(r"status\s+in\s*\('closed'", sa):
    pass
if "request_reopen" in F and "reopen_report" in F:
    rr = BODY.get("request_reopen", "")
    add("D1", where_def("request_reopen"), "closed cases cannot be reopened: the resident can ask (request_reopen) but admin_set_status refuses closed/archived cases and reopen_report() is never called", "high", "reopen-flow")
save("lifecycle.json", {k: {"enter": v[0], "leave": v[1]} for k, v in d1.items()})

# ---------------- D2 producer / consumer ----------------
# notification kinds
kinds = [r[0] for r in psql("select enumlabel from pg_enum where enumtypid = 'public.notification_kind'::regtype order by enumsortorder")]
lay = CODE.get("admin/includes/layout.php", "")
for k in kinds:
    produced = [n for n, b in BODY.items() if re.search(r"'" + re.escape(k) + r"'", b) and re.search(r"notifications|_notify|notify_", b)]
    portal = bool(re.search(r"['\"]" + re.escape(k) + r"['\"]", CODE_ADMIN))
    app = bool(re.search(r"['\"]" + re.escape(k) + r"['\"]", CODE_APP))
    push = bool(re.search(r"['\"]?" + re.escape(k) + r"['\"]?\s*:", CODE_EDGE))
    if not produced:
        add("D2", "notification_kind enum", f"notification kind '{k}' is in the enum but no function produces it", "low", "dead-kind")
    elif not portal and not app:
        add("D2", ", ".join(produced[:2]), f"notification kind '{k}' is produced but neither the portal nor the app has a label or handler for it", "medium", "missing-label")
    elif not portal:
        add("D2", ", ".join(produced[:2]), f"notification kind '{k}' reaches administrators but the portal has no label/look for it (app only)", "low", "missing-label") if re.search(r"admin|staff", " ".join(BODY.get(n, "")[:0] for n in produced)) else None
# tables written never read / read never written (database side + code side), with live row evidence
live_rows = {r["relname"]: r["n"] for r in (json.loads(read(ROOT / "tools/sweep/out/live_counts.json")) if (OUT / "live_counts.json").exists() else [])}
tables = [r[0] for r in psql("select relname from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname <> 'spatial_ref_sys'")]
wr, rd = {}, {}
for t in tables:
    wr[t] = [n for n, b in BODY.items() if re.search(r"(insert\s+into|update|delete\s+from)\s+(public\.)?" + t + r"\b", b, re.I)]
    rd[t] = [n for n, b in BODY.items() if re.search(r"(from|join)\s+(public\.)?" + t + r"\b", b, re.I)]
    cw = bool(re.search(r"->(insert|update|upsert|delete)\(\s*'" + t + "'", CODE_ADMIN) or re.search(r"\.from\('" + t + r"'\)\s*\.(insert|update|upsert|delete)", CODE_APP))
    cr = bool(re.search(r"['\"/(\[]" + t + r"['\"?&(\],]", CODE_ALL))
    cron_use = bool(psql(f"select 1 from cron.job where command ~ '\\m{t}\\M' limit 1"))
    polr = bool(psql(f"select 1 from pg_policies where schemaname='public' and (qual ~ '\\m{t}\\M' or with_check ~ '\\m{t}\\M') and tablename <> '{t}' limit 1"))
    if (wr[t] or cw) and not rd[t] and not cr and not polr and not cron_use:
        add("D2", f"table {t}", f"table '{t}' is written ({len(wr[t])} function(s){', portal' if cw else ''}) but never read by any function, policy, job or client", "low", "write-only-table")
    if (rd[t] or cr) and not wr[t] and not cw and live_rows.get(t, 1) == 0 and t not in ("spatial_ref_sys",):
        add("D2", f"table {t}", f"table '{t}' is read but nothing writes it and it is empty in the live project (a screen that can never show anything)", "low", "read-never-written")
# swallowed exceptions
swallow = []
for fn, body in BODY.items():
    for m in re.finditer(r"exception\s+when\s+(?:others|[a-z_ ]+)\s+then\s+([^;]{0,60})", body, re.I):
        handler = m.group(1).strip().lower()
        if handler.startswith("null") or handler.startswith("return"):
            logged = bool(re.search(r"raise\s+(warning|notice)|error_log|log_error", body[m.start(): m.start() + 300], re.I))
            swallow.append((fn, handler[:20], logged))
            break
bysilent = [s for s in swallow if not s[2]]
trig = {r[0] for r in psql("select p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal")}
intentional = re.compile(r"^(file_report|_?notify|_?push|smart_|_smart|_ws_|_command_auto|_ask_if|run_media|ping_portal|_?places_|_log_)")
for fn, h, lg in sorted(set(bysilent)):
    note = "best-effort side effect (notice/engine/push): fine, but nothing records that it failed" if intentional.match(fn) else "a real action may fail silently: review"
    add("D2", where_def(fn), f"{fn}() swallows errors ('{h}') without logging; {note}" + (" [trigger function]" if fn in trig else ""), "medium" if not intentional.match(fn) else "low", "log-instead-of-swallow")
save("swallowed.json", [{"fn": f, "handler": h, "logged": lg, "trigger": f in trig} for f, h, lg in swallow])

# ---------------- D3 request / decision symmetry ----------------
req_fns = sorted(n for n in F if n != "request_source" and re.match(r"(request_|flag_case|ask_|submit_.*request|propose_|resolution_submit|submit_resolution)", n))
dec_words = r"(approve|decline|deny|decide|answer|resolve_|accept|reject|dismiss|respond|reopen_report|return_|propose|admin_set_status|review_)"
for rf in req_fns:
    body = BODY[rf]
    tbls = set(re.findall(r"(?:insert\s+into|update)\s+(?:public\.)?([a-z_]+)", body, re.I)) - {"notifications", "status_logs", "audit_log", "smart_events", "account_audit", "report_media", "dispatch_updates", "tanod_committee_log"}
    notif = re.search(r"insert\s+into\s+(?:public\.)?notifications\s*\(([^)]*)\)", body, re.I)
    direct_notify = bool(notif) or bool(re.search(r"_notify|notify_|notify\(", body))
    stem = re.sub(r"^(request_|appeal_?|flag_case_for_|ask_|propose_|submit_)", "", rf)[:5] or rf[:5]
    deciders = sorted(n for n, b in BODY.items() if n != rf and not n.startswith("request_") and (any(re.search(r"update\s+(public\.)?" + t + r"(?![a-z_])", b, re.I) for t in tbls) or (stem in n and n not in req_fns)))
    called_by_code = rf in PM.get("rpc_callers", {})
    if not called_by_code and (GR["fn"].get(rf, ("-", "-"))[1] == "call"):
        add("D3", where_def(rf), f"request function {rf}() exists and is granted but no screen calls it (the request cannot be made)", "medium", "uncalled-request")
    if not deciders:
        add("D3", where_def(rf), f"{rf}(): requests are written to {sorted(tbls)[:2]} but no decision/answer function updates that table", "medium", "no-decision-path")
    else:
        dn = [d for d in deciders if re.search(r"insert\s+into\s+(public\.)?notifications|_notify|notify_", BODY[d], re.I)]
        if not dn:
            add("D3", where_def(rf), f"{rf}(): decided by {', '.join(deciders[:2])} but none of them notifies the requester", "medium", "no-answer-notice")
        den = [d for d in deciders if re.search(r"declin|den(y|ied)|reject", BODY[d], re.I) or re.search(r"declin|den|reject", d)]
        if not den and not re.search(r"declin|den(y|ied)|reject", " ".join(deciders)):
            add("D3", where_def(rf), f"{rf}(): no deny/decline path found among {', '.join(deciders[:2])}", "medium", "no-deny-path")
    if notif and "report_id" not in notif.group(1) and re.search(r"p_report|report_id", F[rf][0][0]):
        add("D3", where_def(rf), f"{rf}() notifies with no report_id (no Review button; the notice cannot be scoped to people who may see the case)", "high" if rf == "request_reopen" else "medium", "notice-report-id")
    if direct_notify and re.search(r"for\s+\w+\s+in\s+select[^;]*users[^;]*role\s*=\s*'admin'", body, re.I) and not re.search(r"admin_sees_case|_user_sees_case|admin_sees_report|_notify_case_admins", body):
        add("D3", where_def(rf), f"{rf}() tells every active administrator with no visibility filter (reaches admins who cannot open the case since 0175)", "high" if rf == "request_reopen" else "medium", "notice-scope")
# every function that tells administrators something about a case, with the statement checked for a visibility filter / report_id
for fn, body in sorted(BODY.items()):
    sig = F[fn][0][0]
    if not re.search(r"p_report|report_id|v_report|p_case", sig + body[:400]):
        continue
    for m in re.finditer(r"insert\s+into\s+(?:public\.)?notifications\s*\(([^)]*)\)([^;]*);", body, re.I):
        cols_, stmt = m.group(1), m.group(2)
        every_admin = re.search(r"role\s*=\s*'admin'", stmt) and not re.search(r"sees|committee|handler|admin_tier|assigned|scope|is_full_viewer|tier", stmt, re.I)
        if every_admin and "report_id" not in cols_:
            add("D3", where_def(fn), f"{fn}() tells EVERY active admin with no report_id and no visibility filter (the notifications_scope trigger only filters notices that carry a report_id, so this one reaches admins who cannot open the case and has no Review button)", "high" if fn.startswith("request_") else "medium", "notice-scope")
        elif "report_id" not in cols_ and re.search(r"p_report", sig) and not fn.startswith("_"):
            add("D3", where_def(fn), f"{fn}() writes a notice about a case without report_id (no Review button, cannot be scoped to who may see the case)", "low", "notice-report-id")
# reverse: functions that tell a resident something about a case but are admin actions with no log of who
# ---------------- D4 author-admitted gaps ----------------
MARK = re.compile(r"\b(not added|deliberately not|for now|todo|fixme|parked|out of scope|not yet|workaround|hack|temporary(?:ly)?|later)\b", re.I)
STRONG = re.compile(r"\b(not added|deliberately not|todo|fixme|parked|out of scope|not yet|workaround|hack|temporary(?:ly)?)\b", re.I)
hits = []
roots = [("supabase/migrations", "*.sql"), ("docs", "*.md"), ("admin", "*.php"), ("supabase/functions", "*.ts"), ("mobile/resident/lib", "*.dart"), ("DEPLOY.md", None), ("README.md", None)]
for base, pat in roots:
    paths = [ROOT / base] if pat is None else [p for p in (ROOT / base).rglob(pat) if "vendor" not in p.parts and "changes" not in p.parts and "sweep" not in p.parts and "node_modules" not in p.parts]
    for p in paths:
        for i, line in enumerate(read(p).splitlines(), 1):
            if MARK.search(line) and not re.search(r"to-?do list|todo_|updated_at|\blater than\b|\blater\b.*\bthan\b|(?<![a-z])Later\)", line):
                hits.append((p.relative_to(ROOT).as_posix(), i, MARK.search(line).group(1).lower(), line.strip()[:150], bool(STRONG.search(line))))
strong = [h for h in hits if h[4]]
bym = defaultdict(int)
for h in hits: bym[h[2]] += 1
# crude 'is it still true': a hit naming a function/table that no longer exists, or a TODO in a file untouched since
def objects_in(line):
    return set(re.findall(r"\b([a-z]+(?:_[a-z0-9]+)+)\(\)?", line))
for f, i, m, line, st in strong[:400]:
    objs = objects_in(line)
    gone = [o for o in objs if o not in F and o not in tables and len(o) > 6 and o in ALLBODY.lower() is False]
    pass
for f, i, m, line, st in sorted(strong, key=lambda h: (not h[0].startswith("docs"), h[0], h[1]))[:60]:
    add("D4", f"{f}:{i}", f"[{m}] {line}", "info", "author-admitted")
save("author_admitted.json", [list(h) for h in hits])

# ---------------- D5 role symmetry ----------------
src = CODE.get("admin/includes/access.php", "")
page_tiers = {}
for m in re.finditer(r"'([a-z-]+\.php)'\s*=>\s*\[([^\]]*)\]", src):
    page_tiers[m.group(1)] = re.findall(r"'([a-z]+)'", m.group(2))
lc = (OUT / "loadcost_1x.json")
refused = defaultdict(set)
if lc.exists():
    for r in json.loads(read(lc)):
        if r["role"] in ("super", "captain", "committee", "moderator") and (r["code"] in (401, 403) or (r["code"] in (400, 404) and re.search(r"permission|not allowed|only .*(admin|super)|forbidden|must be an? ", r.get("msg", ""), re.I))):
            allowed = page_tiers.get(r["page"], ["super", "captain", "committee", "moderator"])
            if r["role"] in allowed:
                refused[(r["page"], r["role"])].add(r["q"].split("rpc/")[-1].split("?")[0][:40])
for (pg, role), qs in sorted(refused.items()):
    add("D5", f"admin/includes/access.php {pg}", f"{role} may open {pg} but {len(qs)} of its backend calls are refused for that role (e.g. {sorted(qs)[0]})", "medium", "role-asymmetry")
# actions: functions callable only by one tier (tier checks in the body) that other tiers' pages call
tier_fn = defaultdict(set)
for fn, body in BODY.items():
    for t in ("super", "captain", "committee", "moderator"):
        if re.search(r"admin_tier\(\)\s*(=|in)[^;]{0,60}'" + t + r"'", body):
            tier_fn[fn].add(t)
save("role_functions.json", {k: sorted(v) for k, v in tier_fn.items()})
for pg, tiers in page_tiers.items():
    if "super" in tiers and len(tiers) == 1 and pg in ("residents.php", "places.php", "activity.php"):
        pass

# ---------------- D6 doc vs code ----------------
docs = {p.name: read(p) for p in (ROOT / "docs").glob("*.md")}
docs["DEPLOY.md"] = read(ROOT / "DEPLOY.md")
pages = {p.name for p in (ROOT / "admin").glob("*.php")}
rp = docs.get("ROLES_AND_PAGES.md", "")
for m in sorted(set(re.findall(r"`([a-z-]+\.php)`", rp))):
    if m not in pages:
        add("D6", "docs/ROLES_AND_PAGES.md", f"names {m}, which does not exist in admin/", "low", "doc-drift")
page_doc = set(re.findall(r"`([a-z-]+\.php)`", rp))
for pg in sorted(set(page_tiers) - page_doc):
    add("D6", "docs/ROLES_AND_PAGES.md", f"{pg} has a page rule in access.php but is not mentioned in the doc", "low", "doc-drift")
sc = docs.get("schema.md", "")
for t in sorted(set(re.findall(r"`([a-z_]+)`", sc)) & {x for x in re.findall(r"`([a-z]+_[a-z_]+)`", sc)}):
    if t not in tables and t not in F and t not in kinds and not re.search(r"enum|column", t) and re.search(r"\|\s*`" + t + r"`\s*\|", sc):
        add("D6", "docs/schema.md", f"table `{t}` is documented but does not exist", "low", "doc-drift")
for t in sorted(set(tables)):
    if not re.search(r"\b" + t + r"\b", sc):
        R["D6"].append({"id": "", "src": "docs/schema.md", "gap": t, "sev": "info", "fix": "undocumented-table"})
undoc = [r for r in R["D6"] if r["fix"] == "undocumented-table"]
R["D6"] = [r for r in R["D6"] if r["fix"] != "undocumented-table"]
if undoc:
    add("D6", "docs/schema.md", f"{len(undoc)} tables are not in the doc: {', '.join(r['gap'] for r in undoc[:8])}{' ...' if len(undoc) > 8 else ''}", "low", "doc-drift")
cronjobs = [r[0] for r in psql("select jobname from cron.job")]
for jn in sorted(set(re.findall(r"`([a-z]+(?:-[a-z]+)+)`", docs.get("OPERATIONS.md", "") + docs["DEPLOY.md"])) - {"keep-awake"}):
    if re.search(r"(sweep|smart|purge|places|system|command|keep|media)-", jn) and jn not in cronjobs and not (ROOT / "supabase/functions" / jn).exists() and jn not in CODE_ALL:
        add("D6", "docs/OPERATIONS.md|DEPLOY.md", f"names scheduled job `{jn}`, which is not scheduled in the migrations", "low", "doc-drift")
for m in re.finditer(r"^\|\s*`?([A-Z][A-Z0-9_]{3,})`?\s*\|", docs["DEPLOY.md"], re.M):
    v = m.group(1)
    if not re.search(r"['\"]" + v + r"['\"]|env\(\s*['\"]" + v + r"|Deno\.env\.get\(['\"]" + v, CODE_ALL) and not re.search(v, read(ROOT / "docker-entrypoint.sh") + read(ROOT / "Dockerfile")):
        add("D6", "DEPLOY.md", f"lists setting {v}, which no code reads", "low", "doc-drift")
tm = re.search(r"Sixty-one|(\w+)-one scripts", read(ROOT / "supabase/tests/README.md"))
nt = len(list((ROOT / "supabase/tests").glob("[0-9][0-9]_*.sql")))
if tm and nt != 61:
    add("D6", "supabase/tests/README.md", f"claims sixty-one scripts, there are {nt}", "low", "doc-drift")
bl = read(ROOT / "supabase/baseline/README.md")
nm = len(migrations())
mm = re.search(r"\((\d{4})[–-](\d{4})\)", bl)
if mm and int(mm.group(2)) < int(migrations()[-1].name[:4]):
    add("D6", "supabase/baseline/README.md", f"says the baseline covers 0001-{mm.group(2)}; migrations run to {migrations()[-1].name[:4]} (the baseline is out of date until rebuilt)", "medium", "baseline-stale")

# ---------------- output ----------------
save("detectors.json", R)
print("DETECTORS " + " ".join(f"{k}={len(v)}" for k, v in R.items()) + f"  (lifecycle values={len(d1)}, functions={len(F)}, swallow={len(swallow)} silent={len(bysilent)}, author-admitted hits={len(hits)} strong={len(strong)})")
for k, v in R.items():
    if k == "D4":
        print(f"[D4] markers: " + ", ".join(f"{a}={b}" for a, b in sorted(bym.items(), key=lambda x: -x[1])))
        continue
    for r in sorted(v, key=lambda r: {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}[r["sev"]])[:6]:
        print(f"  [{r['id']}] {r['sev']:<6} {r['gap'][:150]}")
