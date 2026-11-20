#!/usr/bin/env python3
"""Step 1: page / press / backend-object map (static). Prints violations only; details in out/pagemap.json."""
import re
from collections import defaultdict
from common import *

G = grants()
tables = set(G["table"]) | set(G["view"])
fn_defined = set()
for f in migrations():
    t = read(f)
    for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_0-9]+)\s*\(", t, re.I):
        fn_defined.add(m.group(1))
    for m in re.finditer(r"drop\s+function\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_0-9]+)", t, re.I):
        # dropped, unless the same file re-creates it afterwards
        if not re.search(r"create\s+(or\s+replace\s+)?function\s+(public\.)?" + m.group(1) + r"\s*\(", t[m.end():], re.I):
            fn_defined.discard(m.group(1))
    for m in re.finditer(r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_0-9]+)", t, re.I):
        tables.add(m.group(1))
    for m in re.finditer(r"drop\s+table\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_0-9]+)", t, re.I):
        tables.discard(m.group(1))

files = {p.relative_to(ROOT / "admin").as_posix(): read(p) for p in php_files()}
RPC = re.compile(r"->rpc\(\s*'([a-z_0-9]+)'")
RPCS2 = re.compile(r"'rpc/([a-z_0-9]+)'")
FN = re.compile(r"/functions/v1/([a-z-]+)|->(?:edge|invoke|functionCall)\(\s*'([a-z-]+)'")
W = re.compile(r"->(update|insert|delete|upsert)\(\s*'([a-z_0-9]+)'")
R = re.compile(r"->select\(\s*'([a-z_0-9]+)'")
TBL = re.compile(r"\[\s*'([a-z_0-9]+)'\s*,\s*\[")
INC = re.compile(r"require(?:_once)?\s+__DIR__\s*\.\s*'/([^']+)'")
POST = re.compile(r"REQUEST_METHOD'\]\s*(?:===|==|!==)\s*'POST'|\$_POST\b")
FORM = re.compile(r"<form\b[^>]*method=[\"']post", re.I)


def objs(text):
    o = {"rpc": set(), "read": set(), "write": [], "edge": set()}
    for m in list(RPC.finditer(text)) + list(RPCS2.finditer(text)):
        o["rpc"].add(m.group(1))
    for m in W.finditer(text):
        o["write"].append((m.group(1), m.group(2), lineno(text, m.start())))
    for m in R.finditer(text):
        o["read"].add(m.group(1))
    for m in TBL.finditer(text):
        if m.group(1) in tables:
            o["read"].add(m.group(1))
    for m in FN.finditer(text):
        o["edge"].add(m.group(1) or m.group(2))
    return o


direct = {k: objs(v) for k, v in files.items()}


def resolve(src, inc):
    return os.path.normpath((Path(src).parent / inc).as_posix()).replace("\\", "/")


graph = {k: [resolve(k, i) for i in INC.findall(v)] for k, v in files.items()}


def closure(k, seen=None):
    seen = seen if seen is not None else set()
    for c in graph.get(k, []):
        if c in files and c not in seen:
            seen.add(c)
            closure(c, seen)
    return seen


pages = [k for k in files if "/" not in k]
res, viol = {}, defaultdict(list)
for p in pages:
    parts = {p} | closure(p)
    agg = {"rpc": set(), "read": set(), "write": [], "edge": set()}
    for q in parts:
        o = direct[q]
        agg["rpc"] |= o["rpc"]; agg["read"] |= o["read"]; agg["edge"] |= o["edge"]
        agg["write"] += [(op, t, q, ln) for op, t, ln in o["write"]]
    alltext = "\n".join(files[q] for q in parts)
    pr = {"post_handler": bool(POST.search(alltext)), "forms": len(FORM.findall(alltext)),
          "hx": len(re.findall(r"hx-(?:post|get)=", alltext)), "fetch": len(re.findall(r"\bfetch\(", alltext)),
          "csrf": "csrf_check" in alltext}
    res[p] = {"rpc": sorted(agg["rpc"]), "read": sorted(agg["read"]), "write": [list(w) for w in agg["write"]],
              "edge": sorted(agg["edge"]), "presses": pr, "includes": len(parts) - 1}
    if pr["post_handler"] and POST.search(files[p]) and not pr["csrf"] and p not in ("login.php", "forgot-password.php", "reset-password.php", "request-access.php"):
        viol["no_csrf_post_handler"].append(p)

seen_w = set()
for p, r in res.items():
    for op, t, q, ln in r["write"]:
        k = (q, ln)
        if k in seen_w:
            continue
        seen_w.add(k)
        a = G["table"].get(t)
        viol["direct_table_write"].append(f"{q}:{ln} {op} {t} (authenticated={a[1] if a else '?'})")

calls = defaultdict(set)
for path, t in client_code().items():
    if ".test." in path:
        continue
    for m in re.finditer(r"""(?:rpc\(\s*['"]|/rpc/|'rpc/)([a-z_0-9]+)""", t):
        if m.group(1) != "fn":
            calls[m.group(1)].add(path)
for r in sorted(calls):
    if r not in fn_defined:
        viol["rpc_called_but_missing"].append(f"{r} <- {sorted(calls[r])[0]}")
    elif r in G["fn"] and G["fn"][r][1] != "call" and G["fn"][r][0] != "call" and not all(x.startswith("supabase/functions") for x in calls[r]):
        viol["rpc_called_but_not_granted"].append(f"{r} <- {sorted(calls[r])[0]}")
    elif r not in G["fn"]:
        viol["rpc_called_not_in_grants_txt"].append(r)

db_text = "\n".join(read(f) for f in migrations())
dead_rpc, internal = [], []
for fn, (an, au) in sorted(G["fn"].items()):
    if (au == "call" or an == "call") and not fn.startswith("_") and fn not in calls:
        # callable from the API but no client calls it; skip those other DB code calls (cron, triggers, other functions)
        inner = len(re.findall(r"\b" + re.escape(fn) + r"\s*\(", db_text))
        (dead_rpc if inner <= 2 else internal).append(fn)
viol["api_callable_rpc_never_called_anywhere"] = dead_rpc
viol["api_callable_rpc_only_used_inside_db"] = internal

blob = "\n".join(client_code().values())
dead_tables = []
for t in sorted(tables):
    if t == "spatial_ref_sys":
        continue
    if not re.search(r"['\"/(\[]" + re.escape(t) + r"['\"?&(\],]", blob):
        dead_tables.append(t)
viol["tables_no_client_code (rpc-only is fine; see detectors)"] = dead_tables

js_fetch = defaultdict(set)
for jf in (ROOT / "admin" / "assets" / "js").glob("*.js"):
    for m in re.finditer(r"fetch\(\s*[`'\"]([^`'\"?]*\.php)", read(jf)):
        js_fetch[jf.name].add(m.group(1))

summary = {"pages": len(pages), "include_files": len(files) - len(pages),
           "pages_with_post": sum(r["presses"]["post_handler"] for r in res.values()),
           "form_posts": sum(r["presses"]["forms"] for r in res.values()), "htmx": sum(r["presses"]["hx"] for r in res.values()),
           "fetch": sum(r["presses"]["fetch"] for r in res.values()), "rpcs_called": len(calls),
           "tables": len(tables), "functions": len(fn_defined)}
save("pagemap.json", {"summary": summary, "pages": res, "violations": viol,
                      "rpc_callers": {k: sorted(v) for k, v in calls.items()}, "js_fetch": {k: sorted(v) for k, v in js_fetch.items()}})
print("PAGEMAP " + " ".join(f"{k}={v}" for k, v in summary.items()))
for k, v in viol.items():
    print(f"[{k}] {len(v)}" + ((": " + "; ".join(v[:5]) + (" ..." if len(v) > 5 else "")) if v else ""))
