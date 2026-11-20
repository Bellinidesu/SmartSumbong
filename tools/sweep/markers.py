#!/usr/bin/env python3
"""Round 2 / (4): auto-judge the author-admitted gap markers ('not added', 'deliberately not', 'not yet', 'parked', 'out of scope', 'todo', 'workaround', 'hack',
'temporary', 'later') against the CURRENT schema. Reads out/author_admitted.json (detectors.py). Verdicts: STILL TRUE (named object absent / design claim checks out),
NO LONGER TRUE (named object exists / claim fails), NOISE (a UI string or demo data, not a gap), NEEDS A HUMAN. Details: out/markers.json."""
import json, re
from collections import Counter
from common import *

hits = json.loads(read(OUT / "author_admitted.json"))
F = {r["proname"]: r for r in psqlj("select proname, prosecdef from pg_proc where pronamespace = 'public'::regnamespace")}
T = {r[0] for r in psql("select relname from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r','v')")}
COLS = {r[0] for r in psql("select distinct column_name from information_schema.columns where table_schema = 'public'")}
PUB = {r[0] for r in psql("select tablename from pg_publication_tables where pubname = 'supabase_realtime'")}
STOP = set("this that there their which would should where while these those about after before being under other every without within when then than from with have".split())
NOISE = re.compile(r"then '|'[^']*not yet[^']*'|_t\(|\bt\('|\btr\(|context\.tr|demo_data|tanod_strings|i18n\.dart|<small>|<span>|e\(t\(|'Not yet'|navNotYet|nagliliyab|Kumaliwa|parked outside|cars are now parked|\|\s*(Not yet named)")
fn_def_cache = {}


def nearest_fn(path, line):
    if not path.endswith(".sql"): return None
    if path not in fn_def_cache:
        fn_def_cache[path] = [(i + 1, m.group(1)) for i, l in enumerate(read(ROOT / path).splitlines()) if (m := re.search(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_0-9]+)", l, re.I))]
    cands = [(abs(ln - line), n) for ln, n in fn_def_cache[path] if ln >= line - 2]
    return min(cands)[1] if cands else None


out, cnt = [], Counter()
for path, line, marker, text, strong in hits:
    v, why = "NEEDS A HUMAN", ""
    low = text.lower()
    if NOISE.search(text) or (path.endswith((".dart", ".php")) and not re.search(r"^\s*(//|\*|/\*|#)", text) and not text.lstrip().startswith(("*", "//"))):
        v, why = "NOISE", "a UI string or data, not a gap"
    elif marker == "later" and not re.search(r"later (pass|migration|round|step|version|release|date)|until later|parked|decide later|build later|come back", low):
        v, why = "NOISE", "'later' in ordinary wording"
    elif re.search(r"not security definer", low):
        fn = nearest_fn(path, line)
        if fn in F: v, why = ("STILL TRUE", f"{fn} is not security definer") if not F[fn]["prosecdef"] else ("NO LONGER TRUE", f"{fn} is security definer now")
    elif re.search(r"(not|never) in the supabase_realtime|not .*realtime publication", low):
        tb = re.findall(r"public\.([a-z_]+)", text)
        if tb: v, why = ("STILL TRUE", f"{tb[0]} is not published") if tb[0] not in PUB else ("NO LONGER TRUE", f"{tb[0]} is published")
    elif marker in ("not added", "not yet", "todo", "parked", "out of scope", "workaround", "hack", "temporary") or marker == "later" or marker == "deliberately not":
        # objects named in the sentence, else the nouns before the marker
        objs = [o for o in re.findall(r"`?([a-z]+(?:_[a-z0-9]+)+)`?\(?\)?", text) if len(o) > 5]
        known = [o for o in objs if o in F or o in T or o in COLS]
        unknown = [o for o in objs if o not in F and o not in T and o not in COLS]
        head = re.split(r"not added|deliberately not|not yet|out of scope|parked|workaround|temporary|todo", low)[0]
        nouns = [w for w in re.findall(r"[a-z]{5,}", head) if w not in STOP]
        match = sorted({n for w in nouns[-3:] for n in list(F) + list(T) if w in n and not n.startswith("_")})[:4]
        if marker in ("not added", "out of scope") and match and path.endswith(".sql"):
            v, why = "NO LONGER TRUE", "related objects exist now: " + ", ".join(match)
        elif unknown and not known and marker in ("not added", "not yet", "todo", "parked", "out of scope"):
            v, why = "STILL TRUE", "named object absent: " + ", ".join(unknown[:3])
        elif known and marker in ("not added", "not yet", "todo", "out of scope"):
            v, why = "NO LONGER TRUE", "named object exists: " + ", ".join(known[:3])
        elif marker == "deliberately not":
            v, why = "NEEDS A HUMAN", "a design decision; no object to check"
    cnt[v] += 1
    out.append({"file": path, "line": line, "marker": marker, "verdict": v, "why": why, "text": text[:140]})
save("markers.json", out)
print(f"MARKERS {len(hits)} hits: " + ", ".join(f"{k} {n}" for k, n in cnt.most_common()))
for o in out:
    if o["verdict"] in ("NO LONGER TRUE", "STILL TRUE") and o["marker"] in ("not added", "out of scope", "todo", "not yet", "parked"):
        print(f"  {o['verdict']:<15}{o['file'][-44:]}:{o['line']} [{o['marker']}] {o['why'][:80]} | {o['text'][:70]}")
