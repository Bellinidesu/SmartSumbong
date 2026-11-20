#!/usr/bin/env python3
"""Round 2 / (1): strict caller cross-check. For EVERY function in supabase/grants.txt that signed-in (or signed-out) callers may run, list every caller:
clients (admin php/js, mobile dart, edge functions), other functions' bodies (comments stripped), triggers, policies, views, column defaults, cron jobs.
Classes: ORPHAN (no caller of any kind, only tests/comments mention it), DB-ONLY (callable by the API but only other database code calls it),
CLIENT (a client calls it), POLICY/TRIGGER/CRON. Also the reverse: calls to functions that do not exist, grants.txt entries with no function.
Details: out/callgraph.json. Needs the local database."""
import json, re
from collections import defaultdict
from common import *

G = grants()
F = {}
for r in psqlj("select p.proname, p.oid::regprocedure::text sig, pg_get_function_arguments(p.oid) args, p.prosrc, p.prosecdef, p.prorettype::regtype::text ret from pg_proc p "
               "where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p') and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')"):
    F.setdefault(r["proname"], []).append(r)


def strip(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql


BODY = {n: "\n".join(strip(x["prosrc"]) for x in v) for n, v in F.items()}
trig = defaultdict(list)
for r in psqlj("select p.proname, t.tgrelid::regclass::text tbl, t.tgname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal"):
    trig[r["proname"]].append(f"{r['tbl']}.{r['tgname']}")
pol = "\n".join((r["q"] or "") + " " + (r["w"] or "") for r in psqlj("select coalesce(qual,'') q, coalesce(with_check,'') w from pg_policies where schemaname = 'public'"))
views = "\n".join(r["d"] for r in psqlj("select pg_get_viewdef(c.oid) d from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('v','m')"))
defaults = "\n".join(r["d"] for r in psqlj("select pg_get_expr(adbin, adrelid) d from pg_attrdef"))
checks = "\n".join(r["d"] for r in psqlj("select pg_get_constraintdef(oid) d from pg_constraint where connamespace = 'public'::regnamespace"))
cron = "\n".join(r[0] for r in psql("select command from cron.job"))
CODE = client_code()
clients = defaultdict(set)      # called as rpc
strrefs = defaultdict(set)      # appears as a quoted string only (wrappers, maps): weaker evidence
for path, t in CODE.items():
    if ".test." in path:
        continue
    for m in re.finditer(r"rpc\(\s*['\"]([a-z_0-9]+)['\"]|/rpc/([a-z_0-9]+)|['\"]rpc/([a-z_0-9]+)['\"]", t):
        n = m.group(1) or m.group(2) or m.group(3)
        if n in F:
            clients[n].add(path)
    for m in re.finditer(r"['\"]([a-z][a-z_0-9]{3,})['\"]", t):
        if m.group(1) in F:
            strrefs[m.group(1)].add(path)
tests = "\n".join(read(f) for f in (ROOT / "supabase/tests").rglob("*.sql"))
rows = {}
for n, vs in sorted(F.items()):
    an, au = G["fn"].get(n, ("?", "?"))
    api = "call" in (an, au)
    db_callers = sorted(g for g, b in BODY.items() if g != n and re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"\s*\(", b))
    inline = []
    if re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"\s*\(", pol): inline.append("policy")
    if re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"\s*\(", views): inline.append("view")
    if re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"\s*\(", defaults + checks): inline.append("default/check")
    if re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"\s*\(", cron): inline.append("cron")
    if n in trig: inline.append("trigger " + ",".join(trig[n][:2]))
    cl = sorted(clients.get(n, []))
    body = BODY[n]
    gate = []
    for k, pat in (("super", r"admin_tier\(\)\s*(=|in)[^;]{0,50}'super'|is_super"), ("admin", r"is_admin\(\)|role\s*=\s*'admin'|_is_admin"), ("tanod", r"role\s*=\s*'tanod'|is_tanod"),
                   ("owner", r"auth\.uid\(\)\s*(=|is distinct from)|resident_id\s*=\s*auth\.uid"), ("service", r"service_role")):
        if re.search(pat, body): gate.append(k)
    sr = sorted(p for p in strrefs.get(n, []) if p not in cl)
    if cl: cls = "CLIENT"
    elif sr: cls = "CLIENT?(string ref only)"
    elif inline: cls = "POLICY/TRIGGER/CRON"
    elif db_callers: cls = "DB-ONLY"
    else: cls = "ORPHAN"
    rows[n] = {"api_callable": api, "grants": f"anon={an} authenticated={au}", "class": cls, "clients": cl[:4], "string_refs": sr[:3], "db_callers": db_callers[:6], "inline": inline,
               "gates": gate, "tested": bool(re.search(r"(?<![a-z_0-9])" + re.escape(n) + r"(?![a-z_0-9])", tests)), "returns": vs[0]["ret"]}
# reverse
missing_in_db = defaultdict(set)
for n, b in BODY.items():
    for m in re.finditer(r"public\.([a-z_][a-z_0-9]*)\s*\(", b):
        c = m.group(1)
        pre = b[max(0, m.start() - 14): m.start()].lower()
        if c not in F and not re.search(r"(into|from|join|update|table|on|exists)\s*$", pre) and not c.startswith(("st_", "geography", "geometry")):
            missing_in_db[c].add(n)
stale_grants = sorted(k for k in G["fn"] if k not in F)
not_in_grants = sorted(k for k in F if k not in G["fn"])
client_missing = sorted(c for path, t in CODE.items() for c in set(re.findall(r"rpc\(\s*['\"]([a-z_0-9]+)['\"]", t)) if c not in F and ".test." not in path and c != "fn")
api = {n: r for n, r in rows.items() if r["api_callable"]}
cnt = defaultdict(int)
for r in api.values(): cnt[r["class"]] += 1
save("callgraph.json", {"counts": dict(cnt), "functions": rows, "called_but_missing_in_db": {k: sorted(v) for k, v in missing_in_db.items()}, "stale_grants": stale_grants,
                        "functions_not_in_grants_txt": not_in_grants, "client_calls_missing": sorted(set(client_missing))})
print(f"CALLGRAPH functions={len(F)} api_callable={len(api)} " + " ".join(f"{k}={v}" for k, v in sorted(cnt.items())) + f" | missing_in_db={len(missing_in_db)} stale_grants={len(stale_grants)} not_in_grants={len(not_in_grants)} client_calls_missing={len(set(client_missing))}")
orph = sorted(n for n, r in api.items() if r["class"] == "ORPHAN")
print(f"ORPHAN api-callable functions with no caller of any kind ({len(orph)}):")
for n in orph:
    r = api[n]
    print(f"  {n}  [{r['grants']}] callable by: {'anon+' if r['grants'].startswith('anon=call') else ''}signed-in{(' gated:' + '/'.join(r['gates'])) if r['gates'] else ' (no role gate found)'}  tested={r['tested']}")
dbo = sorted(n for n, r in api.items() if r["class"] == "DB-ONLY")
print(f"DB-ONLY ({len(dbo)}; API-callable but only other functions call them): " + ", ".join(dbo[:25]) + (" ..." if len(dbo) > 25 else ""))
if missing_in_db: print("CALLED IN SQL BUT NOT DEFINED: " + "; ".join(f"{k} <- {sorted(v)[0]}" for k, v in sorted(missing_in_db.items())[:8]))
if stale_grants: print("grants.txt entries with no function: " + ", ".join(stale_grants[:8]))
if not_in_grants: print(f"functions missing from grants.txt ({len(not_in_grants)}): " + ", ".join(not_in_grants[:8]))
if client_missing: print("client calls to missing functions: " + ", ".join(sorted(set(client_missing))))
