#!/usr/bin/env python3
"""Round 2 / (2): DYNAMIC PROBERS on the small throwaway database `sweep_probe` (probe_db.sh). Facts instead of text heuristics.
`python probe.py run [fn ...]`   drive every API-callable function as every actor (resident owner, other resident, tanod, staff x2, Kagawad x2, captain,
                                 super, signed-out) against pristine fixtures in each case state (x2 variants: unhandled / handled-and-assigned), one subtransaction
                                 per probe, rolled back. Records result, the real state change, and every notification created (who, report_id, can they see the case).
`python probe.py report`         the lifecycle matrix, role x action matrix, notice reach and their findings (out/probe_*.json; compact print).
`python probe.py inject`         (d) failure injection.
Result of a call is: ok | denied (42501 or a 'only/not allowed' message) | invalid (the arguments or the state were refused after the role gate: 'reached') | fixture-error."""
import itertools, json, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from common import *

DB = "sweep_probe"
STATES = ["pending_review", "validated", "assigned", "in_progress", "offline_investigation", "in_progress+submitted", "resolved", "closed", "archived", "rejected", "cancelled"]
ACTORS = ["res1", "res2", "tan1", "tan2", "stf1", "stf2", "kag1", "kag2", "cap", "sup", "anon"]
SKIP = {"smart_replay", "smart_rollback", "smart_save_rules", "admin_reset_password", "reset_admin_password", "delete_my_account", "request_account_deletion"}
TEXTISH = r"reason|remark|note|message|body|details|text|label|agency|official|instructions|subject|description|p_name|full_name"


def sql_file(path):
    r = subprocess.run([f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", DB, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", str(path)], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise RuntimeError(r.stderr[:400])


def funcs():
    rows = psqlj("select p.proname, p.proargnames names, (select array_agg(format_type(t, null)) from unnest(p.proargtypes) t) types, p.pronargdefaults nd, p.prosrc body, p.prorettype::regtype::text ret, "
                 "pg_get_function_arguments(p.oid) args from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname not like '\_%' "
                 "and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))", db=DB)
    out = {}
    for r in rows:
        if r["proname"] in out or r["ret"] == "trigger" or r["proname"] in SKIP:
            continue
        out[r["proname"]] = r
    return out


def enum_candidates(param, body, typ):
    if typ == "boolean": return ["true", "false"]
    lits = []
    for m in re.finditer(re.escape(param) + r"(?![a-z_0-9])", body):
        seg = body[m.end(): m.end() + 260]
        lits += re.findall(r"'([a-z][a-z_ ]{1,24})'", seg)
    seen = []
    for x in lits:
        if x not in seen and x not in ("pg", "public"): seen.append(x)
    return seen[:7]


def arg_values(fn, r):
    """list of call templates (named notation, tokens like {report}) for one function"""
    names = r["names"] or []; types = r["types"] or []
    n_req = len(names) - (r["nd"] or 0)
    per = []
    for i, (nm, ty) in enumerate(zip(names, types)):
        if i >= n_req and not re.search(r"decision|status|level|step|accept|approve|fixed|resolved|public|^p_on$|^p_to$|office|official|committee|reason|remark|note", nm):
            continue                              # defaulted and not decisive: leave to the default
        vals = []
        if ty == "uuid":
            tok = {"p_dispatch": "dispatch", "p_concern": "concern"}.get(nm)
            if nm == "p_request":
                tok = {"approve_escalation": "esc", "deny_escalation": "esc", "submit_additional_details": "detail", "endorse_retirement": "retire", "finalize_retirement": "retire", "decide_profile_request": "profile"}.get(fn, "esc")
            elif nm in ("p_to", "p_tanod"):
                tok = "stf1" if fn in ("assign_case",) else ("tan2" if "reroute" in fn else "tan1")
            elif nm in ("p_user", "p_resident", "p_subject"):
                tok = "res1"
            elif nm.startswith(("p_report", "p_case")) or tok is None:
                tok = tok or "report"
            vals = [f"'{{{tok}}}'::uuid"]
        elif ty == "uuid[]":
            vals = ["array['{res1}'::uuid]"]
        elif ty in ("text", "character varying"):
            en = enum_candidates(nm, r["body"], ty) if re.search(r"decision|status|level|step|office|official|committee|^p_to$|kind|scope|mode|action|period", nm) else []
            if nm == "p_to" and fn in ("forward_case", "flag_case_for_forward"): en = ["environment"]
            if en: vals = [f"'{x}'" for x in en]
            elif re.search(TEXTISH, nm): vals = ["'Probe reason text for the sweep'"]
            else: vals = ["'probe'"]
        elif ty == "boolean": vals = ["true", "false"]
        elif ty in ("jsonb", "json"): vals = ["'[]'::jsonb"] if re.search(r"media|concerns|items|ids", nm) else ["'{}'::jsonb"]
        elif ty.startswith("timestamp"): vals = ["now() + interval '3 days'"]
        elif ty in ("integer", "bigint", "smallint"): vals = ["1"]
        elif ty == "double precision": vals = ["14.51944"] if "lat" in nm else ["121.01219"]
        elif ty == "complaint_category": vals = ["'peace_order_nuisance'::public.complaint_category"]
        elif ty == "date": vals = ["current_date"]
        else: vals = ["null"]
        per.append((nm, vals))
    combos = list(itertools.islice(itertools.product(*[v for _, v in per]), 6)) if per else [()]
    tm = []
    for c in combos:
        tm.append(f"select public.{fn}(" + ", ".join(f"{per[i][0]} => {v}" for i, v in enumerate(c)) + ")")
    return tm


def has_target(r):
    return bool(re.search(r"p_report|p_dispatch|p_request|p_concern|p_case", " ".join(r["names"] or [])))


def block(fn, r):
    tm = arg_values(fn, r)
    rep = has_target(r)
    states = STATES if rep else ["in_progress"]
    variants = [0, 1, 2] if rep else [1]
    q = lambda xs: "array[" + ",".join("'" + x + "'" for x in xs) + "]"
    tarr = "array[" + ",".join("$t$" + t + "$t$" for t in tm) + "]::text[]"
    return f"""do $p$
declare fn text := '{fn}'; tmpls text[] := {tarr}; states text[] := {q(states)}; variants int[] := array{variants}; actors text[] := {q(ACTORS)};
  out jsonb := '[]'; ctx jsonb; sql text; res text; st text; v int; a text; ti int; k text; before uuid[]; to_status text; side text; notifs jsonb; rid uuid;
begin
  foreach st in array states loop foreach v in array variants loop foreach a in array actors loop for ti in 1..array_length(tmpls, 1) loop
    begin
      ctx := sweep.mk_ctx(st, v, {'false' if fn.startswith(('request_', 'flag_case', 'ask_')) else 'true'}); rid := (ctx->>'report')::uuid;
      before := array(select id from public.notifications);
      sql := tmpls[ti];
      for k in select jsonb_object_keys(ctx) loop sql := replace(sql, '{{' || k || '}}', coalesce(ctx->>k, '00000000-0000-0000-0000-000000000000')); end loop;
      for k in select name from sweep.actors loop sql := replace(sql, '{{' || k || '}}', sweep.a(k)::text); end loop;
      if a = 'anon' then
        perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', 'anon', true); set local role anon;
      else
        perform set_config('request.jwt.claim.sub', sweep.a(a)::text, true); perform set_config('request.jwt.claim.role', 'authenticated', true); set local role authenticated;
      end if;
      begin execute sql; res := 'ok';
      exception when others then res := sqlstate || ':' || left(sqlerrm, 100); end;
      reset role;
      select status::text into to_status from public.reports where id = rid;
      side := coalesce((select string_agg(d.state::text, ',' order by d.created_at) from public.dispatches d where d.report_id = rid), '-') || '|' ||
              coalesce((select status from public.escalation_requests where report_id = rid limit 1), '-') || '|' ||
              coalesce((select status::text from public.retirement_requests where tanod_id = sweep.a('tan1') limit 1), '-') || '|' ||
              coalesce((select status from public.profile_requests where user_id = sweep.a('res1') limit 1), '-') || '|' ||
              coalesce((select case when responded_at is not null then 'answered' else 'open' end from public.detail_requests where report_id = rid limit 1), '-') || '|' ||
              coalesce((select status from public.report_concerns where report_id = rid limit 1), '-') || '|' ||
              coalesce((select case when handler_id is null then 'nohandler' else 'handled' end || '/' || case when assigned_to is null then 'unassigned' else 'assigned' end from public.reports where id = rid), '-');
      notifs := coalesce((select jsonb_agg(jsonb_build_object('to', coalesce((select name from sweep.actors where id = n.user_id), 'other'), 'kind', n.kind, 'rid', n.report_id is not null,
                  'sees', case when (select u.role::text from public.users u where u.id = n.user_id) = 'admin' then
                            (case when (select u.admin_tier from public.users u where u.id = n.user_id) in ('super', 'captain') then true else public._user_sees_case(n.user_id, rid, rr.category, rr.handler_id) end)
                          else (n.user_id = rr.resident_id or exists (select 1 from public.dispatches dd where dd.report_id = rid and dd.tanod_id = n.user_id)) end))
                  from public.notifications n cross join (select category, handler_id, resident_id from public.reports where id = rid) rr where n.id <> all(before) and (n.report_id is null or n.report_id = rid)), '[]'::jsonb);
      out := out || jsonb_build_array(jsonb_build_object('s', st, 'v', v, 'a', a, 't', ti, 'r', res, 'to', to_status, 'side', side, 'n', notifs));
      raise exception 'sweep' using errcode = 'SW001';
    exception when others then
      if sqlstate <> 'SW001' then out := out || jsonb_build_array(jsonb_build_object('s', st, 'v', v, 'a', a, 't', ti, 'r', 'FIXTURE:' || sqlstate || ':' || left(sqlerrm, 80))); end if;
    end;
  end loop; end loop; end loop; end loop;
  insert into sweep.results values (fn, 'matrix', out);
end $p$;
"""


def run_one(fn, r):
    f = OUT / f"probe_sql_{fn}.sql"
    f.write_text(block(fn, r), encoding="utf-8")
    t0 = time.time()
    try:
        sql_file(f)
        return fn, round(time.time() - t0, 1), None
    except Exception as e:
        return fn, round(time.time() - t0, 1), str(e)[:200]
    finally:
        try: f.unlink()
        except Exception: pass


def cmd_run(only):
    sql_file(ROOT / "tools/sweep/sql/probe_setup.sql")
    fs = funcs()
    todo = [f for f in sorted(fs) if not only or f in only]
    if not only: psql("delete from sweep.results where kind = 'matrix'", db=DB)
    psql("delete from sweep.results where kind = 'matrix' and fn = any(array[" + ",".join("'" + f + "'" for f in todo) + "])", db=DB)
    errs = []
    t0 = time.time()
    with ThreadPoolExecutor(4) as ex:
        for fn, s, e in ex.map(lambda f: run_one(f, fs[f]), todo):
            if e: errs.append((fn, e))
    print(f"PROBE ran {len(todo)} functions in {round(time.time() - t0)}s; {len(errs)} blocks failed to run" + ("".join(f"\n  {a}: {b[:120]}" for a, b in errs[:8])))


def classify(res):
    if res == "ok": return "ok"
    if res.startswith("FIXTURE"): return "fixture-error"
    code, msg = (res.split(":", 1) + [""])[:2]
    if code == "42501" or re.search(r"^only (an? )?(admin|administrator|super|resident who|tanod|the (handler|resident|owner|kagawad|chairman|assigned|admin|committee)|a (kagawad|councilor|staff|tanod|super))|not allowed|permission denied|not your|outside your|cannot see|no access|administrators only|must be an? (admin|super)|this case (is outside|has no|belongs)|you (can|may)(not|'t)|only the ", msg, re.I): return "denied"
    return "invalid"


def load():
    rows = psqlj("select fn, data from sweep.results where kind = 'matrix'", db=DB)
    return {r["fn"]: r["data"] for r in rows}


def cmd_report():
    fs = funcs(); M = {k: v for k, v in load().items() if k in fs}
    # ---- (a) lifecycle: real from->to per (fn, actor)
    trans = {}      # (from, to) -> {(fn, actor)}
    reach = {}
    for fn, rows in M.items():
        for x in rows:
            if x.get("r") == "ok" or classify(x.get("r", "")) == "ok":
                if x.get("to") and x["to"] != x["s"].split("+")[0]:
                    trans.setdefault((x["s"].split("+")[0], x["to"]), set()).add((fn, x["a"]))
    states = [s for s in STATES if "+" not in s]
    ent = {s: set() for s in states}; leave = {s: set() for s in states}
    for (a, b), w in trans.items():
        ent[b] |= {(f, ac) for f, ac in w}; leave[a] |= {(f, ac) for f, ac in w}
    find = []
    for s in states:
        enters = sorted({f for f, _ in ent[s]}); leaves = sorted({f for f, _ in leave[s]})
        who_in = sorted({a for _, a in ent[s]}); who_out = sorted({a for _, a in leave[s]})
        if s != "pending_review" and not enters: find.append(f"report_status '{s}' is UNREACHABLE: no function by any role moved a case into it")
        if not leaves: find.append(f"report_status '{s}' is a DEAD END: no function by any role moved a case out of it")
        elif len(set(who_out)) == 1: find.append(f"report_status '{s}' can only be left by one actor ({who_out[0]})")
        if enters and len(set(who_in)) == 1: find.append(f"report_status '{s}' can only be entered by one actor ({who_in[0]})")
    mat = {f"{a}->{b}": sorted({f"{f}/{ac}" for f, ac in w})[:6] for (a, b), w in sorted(trans.items())}
    # side-effect state machines: dispatch / escalation / retirement / profile / detail / concern
    sidefx = {"dispatch": {}, "escalation": {}, "retirement": {}, "profile": {}, "detail": {}, "concern": {}}
    base = {}
    for fn, rows in M.items():
        for x in rows:
            if x.get("r") != "ok" or "side" not in x: continue
            d, e, rt, p, de, c, h = x["side"].split("|")
            key = (fn, x["s"], x["v"])
            for nm, val in (("dispatch", d), ("escalation", e), ("retirement", rt), ("profile", p), ("detail", de), ("concern", c)):
                sidefx[nm].setdefault(val, set()).add(f"{fn}/{x['a']}")
    save("probe_lifecycle.json", {"report_status_matrix": mat, "findings": find, "other_state_values_reached_by": {k: {v: sorted(w)[:4] for v, w in d.items()} for k, d in sidefx.items()}})
    # the requests: is there an answer path
    reqs = {"reopen": ("request_reopen", ["reopen_report", "admin_set_status"]), "appeal": ("request_appeal", ["appeal_report"]), "retirement": ("request_retirement", ["endorse_retirement", "finalize_retirement"]),
            "forward": ("flag_case_for_forward", ["forward_case", "dismiss_forward_flag"]), "more details": ("request_additional_details", ["submit_additional_details"]),
            "ocr rescan": ("request_ocr_rescan", []), "escalation": ("request_escalation", ["approve_escalation", "deny_escalation"]), "profile change": ("request_profile_change", ["decide_profile_request"])}
    reqrows = []
    for nm, (rf, decs) in reqs.items():
        okr = sorted({x["a"] for x in M.get(rf, []) if x.get("r") == "ok"})
        dec_ok = {d: sorted({x["a"] for x in M.get(d, []) if x.get("r") == "ok"}) for d in decs}
        notif = {d: sorted({n["to"] for x in M.get(d, []) if x.get("r") == "ok" for n in x.get("n", [])}) for d in decs}
        reqrows.append({"request": nm, "fn": rf, "can_request": okr, "decided_by": dec_ok, "decision_notifies": notif})
        if not okr: find.append(f"request '{nm}' ({rf}): no actor could make the request in any fixture state")
        elif decs and not any(dec_ok.values()): find.append(f"request '{nm}': {', '.join(okr)} can ask, but NO decision function succeeded for any role in any state (no working decision path)")
        elif decs and not any(notif.values()): find.append(f"request '{nm}': decided by {', '.join(d for d, v in dec_ok.items() if v)} but the requester is never notified")
        elif not decs: find.append(f"request '{nm}': no decision function exists")
    # ---- (b) role x action
    RA = {}
    for fn, rows in M.items():
        by = {}
        for x in rows:
            c = classify(x.get("r", "")); by.setdefault(x["a"], set()).add(c)
        RA[fn] = {a: ("ok" if "ok" in c else ("denied" if c == {"denied"} else "invalid" if "invalid" in c else "/".join(sorted(c)))) for a, c in by.items()}
    save("probe_roles.json", RA)
    anon_ok = sorted(fn for fn, m in RA.items() if m.get("anon") == "ok")
    res_ok_admin = sorted(fn for fn, m in RA.items() if m.get("res1") == "ok" and m.get("res2") == "ok" and re.search(r"admin|assign|dispatch|take_over|forward|review", fn))
    # who may do what: tier sets
    tiers = {fn: tuple(a for a in ACTORS if m.get(a) == "ok") for fn, m in RA.items()}
    never = sorted(fn for fn, t in tiers.items() if not t)
    onlysup = sorted(fn for fn, t in tiers.items() if t and set(t) <= {"sup"})
    save("probe_who.json", {fn: list(t) for fn, t in tiers.items()})
    # page vs access.php
    pm = json.loads(read(OUT / "pagemap.json"))["pages"]
    acc = read(ROOT / "admin/includes/access.php"); pt = {}
    for m in re.finditer(r"'([a-z-]+\.php)'\s*=>\s*\[([^\]]*)\]", acc): pt[m.group(1)] = re.findall(r"'([a-z]+)'", m.group(2))
    tier_actor = {"super": "sup", "captain": "cap", "committee": "kag1", "moderator": "stf1"}
    refused, nopage = [], []
    for pg, info in pm.items():
        tiers_ok = pt.get(pg, list(tier_actor))
        for t in tiers_ok:
            if t not in tier_actor: continue
            for r_ in info["rpc"]:
                m = RA.get(r_)
                if m and t != "captain" and m.get(tier_actor[t]) == "denied" and not r_.startswith(("smart_", "_")):
                    refused.append(f"{pg}: {t} may open it but {r_}() is denied to that role in every state")
    pages_by_tier = {t: set() for t in tier_actor}
    for pg, info in pm.items():
        for t in pt.get(pg, list(tier_actor)):
            if t in pages_by_tier: pages_by_tier[t] |= set(info["rpc"])
    callers = json.loads(read(OUT / "pagemap.json"))["rpc_callers"]
    for fn, t in tiers.items():
        for a, tn in (("kag1", "committee"), ("stf1", "moderator"), ("cap", "captain")):
            if a in t and fn not in pages_by_tier[tn] and not any(x.startswith("mobile") for x in callers.get(fn, [])) and callers.get(fn) and fn.startswith(("admin_", "approve", "assign", "take", "forward", "refer", "escalate", "hand_")):
                nopage.append(f"{fn}: allowed for {tn} but none of that role's pages call it")
    # doc claims (ROLES_AND_PAGES.md) as expectations
    claims = [("staff do not assign (doc 'Assigns: No')", "assign_case", "stf1", "denied"), ("staff never take over (doc 'Takes over from: Nobody')", "take_over_case", "stf1", "denied"),
              ("a Kagawad takes over only from their own staff: stf2's Kagawad kag2 cannot take over", "take_over_case", "kag2", "denied"), ("staff hold the 5 decisions: approve_escalation", "approve_escalation", "stf1", "ok"),
              ("staff hold: deny_escalation", "deny_escalation", "stf1", "ok"), ("staff hold: escalate_in_barangay", "escalate_in_barangay", "stf1", "ok"), ("staff hold: hand_to_higher_official", "hand_to_higher_official", "stf1", "ok"),
              ("staff hold: refer_report", "refer_report", "stf1", "ok"), ("a Kagawad assigns", "assign_case", "kag1", "ok"), ("super admin assigns", "assign_case", "sup", "ok"),
              ("captain is view-only (changes nothing): admin_set_status", "admin_set_status", "cap", "denied"), ("captain is view-only: assign_case", "assign_case", "cap", "denied"),
              ("tanod uses the app only: review_report", "review_report", "tan1", "denied"), ("resident cannot review", "review_report", "res1", "denied"),
              ("staff cannot forward, only flag (0152)", "forward_case", "stf1", "denied"), ("staff flag a case for forwarding", "flag_case_for_forward", "stf1", "ok")]
    contra = []
    for text, fn, a, exp in claims:
        got = RA.get(fn, {}).get(a)
        if got is None: contra.append(f"doc claim '{text}' could not be tested ({fn} not probed)")
        elif exp == "ok" and got == "invalid": contra.append(f"(not proven) doc says '{text}': {fn} as {a} reached validation but a precondition of the fixture blocked it")
        elif (exp == "ok" and got != "ok") or (exp == "denied" and got == "ok"):
            contra.append(f"doc says '{text}' but probe: {fn} as {a} = {got}")
    # ---- (c) notice reach
    reachrows, leaks = [], {}
    for fn, rows in M.items():
        seen = {}
        for x in rows:
            if x.get("r") != "ok": continue
            for n in x.get("n", []):
                k = (fn, n["kind"], n["to"])
                d = seen.setdefault(k, {"rid": n["rid"], "sees": set(), "cnt": 0}); d["cnt"] += 1; d["sees"].add(n["sees"]); d["rid"] = d["rid"] and n["rid"]
        for (f, kind, to), d in seen.items():
            reachrows.append({"fn": f, "kind": kind, "to": to, "report_id_set": d["rid"], "recipient_can_see_case": sorted(map(str, d["sees"]))})
            if not d["rid"] and f in ("request_reopen", "request_appeal"): leaks.setdefault(f, set()).add(to)
            if has_target(fs[f]) and False in d["sees"]: leaks.setdefault(f, set()).add(to)
    norid = sorted({(r["fn"], r["kind"]) for r in reachrows if not r["report_id_set"] and r["to"] in ("kag1", "kag2", "stf1", "stf2", "cap", "sup") and re.search(r"report|case|dispatch|appeal|reopen|escalat|assign|forward|resolution", r["fn"])})
    cant = sorted({(r["fn"], r["to"]) for r in reachrows if has_target(fs[r["fn"]]) and "False" in r["recipient_can_see_case"]})
    save("probe_notices.json", {"reach": reachrows, "no_report_id_to_admins": norid, "recipient_cannot_see": cant})
    # ---- print
    print(f"PROBE report: functions probed {len(M)}, probes {sum(len(v) for v in M.values())}; results ok={sum(1 for v in M.values() for x in v if classify(x.get('r','')) == 'ok')}")
    print("(a) LIFECYCLE report_status matrix (from->to : fn/actor):")
    for k, v in mat.items(): print(f"   {k:<38} {', '.join(v[:3])}")
    for f_ in find: print("   FINDING:", f_[:230])
    print(f"(b) ROLES: signed-out callers can run {len(anon_ok)} functions: {', '.join(anon_ok[:12])}")
    print(f"    {len(never)} API functions no actor could run successfully in any fixture (reached only errors): {', '.join(never[:14])}{' ...' if len(never) > 14 else ''}")
    print(f"    {len(onlysup)} only the super admin could run: {', '.join(onlysup[:12])}{' ...' if len(onlysup) > 12 else ''}")
    for x in sorted(set(refused))[:8]: print("    page opens, action refused:", x)
    for x in sorted(set(nopage))[:8]: print("    action allowed, no page:", x)
    for x in contra: print("    DOC vs CODE:", x[:200])
    print(f"(c) NOTICES: {len(reachrows)} (function, kind, recipient) reaches; admin notices with no report_id: {len(norid)}; recipient cannot see the case: {len(cant)}")
    for fn, kind in norid[:10]: print(f"    no report_id (no Review button, cannot be scoped): {fn} -> kind {kind}")
    for fn, to in cant[:10]: print(f"    LEAK/DEAD: {fn} notified {to} who cannot see the case")
    save("probe_findings.json", {"lifecycle": find, "refused": sorted(set(refused)), "nopage": sorted(set(nopage)), "doc_contradictions": contra, "norid": norid, "cant_see": cant, "never": never, "onlysup": onlysup, "anon_ok": anon_ok, "requests": reqrows})


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "report"
    if c == "run": cmd_run(set(sys.argv[2:]))
    elif c == "inject":
        import inject; inject.main()
    else: cmd_report()
