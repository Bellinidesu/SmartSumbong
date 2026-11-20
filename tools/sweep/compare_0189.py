#!/usr/bin/env python3
"""Summary of loadcost.py --compare (K-04 / 0189): per scale, database time of every (page, role) before and after 0189, the slowest pages left,
and whether every replayed GET answered the same rows (order-free digest). Reads out/loadcost_<s>x_old|_new.json; writes out/compare_0189.json."""
import json
from collections import defaultdict
from common import OUT, save

BUDGET = 200.0


def load(sc, tag):
    f = OUT / f"loadcost_{sc}x_{tag}.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else None


def main():
    out = {}
    for sc in (1, 50, 250):
        o, n = load(sc, "old"), load(sc, "new")
        if not o or not n: continue
        agg = lambda rows: (lambda d: [d[(r["page"], r["role"])].append(r["db_ms"]) for r in rows] and d)(defaultdict(list))
        ao, an = agg(o), agg(n)
        pages = {k: (round(sum(ao.get(k, [0]))), round(sum(an.get(k, [0]))), len(an.get(k, []))) for k in set(ao) | set(an)}
        # same answers: one entry per distinct (role, query)
        ho = {(r["role"], r["q"]): r.get("h") for r in o}; hn = {(r["role"], r["q"]): r.get("h") for r in n}
        both = [k for k in ho if ho[k] and hn.get(k)]
        same = sum(ho[k] == hn[k] for k in both); differ = [k for k in both if ho[k] != hn[k]]
        to = lambda rows: sum(1 for r in rows if r["db_ms"] >= 29000 or r["code"] == 0)
        over = sorted([(v[1], k) for k, v in pages.items() if v[1] > BUDGET], reverse=True)
        slow_q = sorted({(r["role"], r["q"]): r["db_ms"] for r in n}.items(), key=lambda x: -x[1])[:12]
        out[sc] = {"pages": {f"{k[0]} | {k[1]}": v for k, v in sorted(pages.items(), key=lambda x: -x[1][0])},
                   "answers_compared": len(both), "answers_same": same, "answers_differ": [f"{a} {b}" for a, b in differ][:30],
                   "timeouts_old": to(o), "timeouts_new": to(n), "pages_over_budget_new": [f"{k[0]}/{k[1]} {v} ms" for v, k in over],
                   "slowest_new": [f"{ms} {r} {q[:120]}" for (r, q), ms in slow_q]}
        print(f"== {sc}x: {len(pages)} (page, role) pairs; GET answers compared {len(both)}, same {same}, differ {len(differ)}; replay timeouts old {to(o)} -> new {to(n)}")
        print(f"   pages over {BUDGET:.0f} ms of db time after 0189: {len(over)}: " + "; ".join(f"{k[0]}/{k[1]} {v}" for v, k in over[:10]))
        top = sorted(pages.items(), key=lambda x: -x[1][0])[:12]
        for (pg, role), (a, b, nreq) in top:
            print(f"   {pg:<26} {role:<10} {a:>9} -> {b:>6} ms ({nreq} req)")
        for d in differ[:5]: print("   DIFFERENT ANSWER:", d)
    save("compare_0189.json", out)


if __name__ == "__main__":
    main()
