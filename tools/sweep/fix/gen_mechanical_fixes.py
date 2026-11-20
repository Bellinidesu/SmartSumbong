#!/usr/bin/env python3
"""Class A generator: DRAFT 0192 mechanical_fixes (never applied; supabase/drafts/). Reads out/callgraph.json (callgraph.py) and the CURRENT definitions from the local
database (a full build of main). Three parts:
 (a) C-03: revoke EXECUTE from the API on functions that only other database code calls, but ONLY where that is provably safe: every caller is SECURITY DEFINER (so it runs as
     the owner and needs no right of the signed-in user) and nothing else depends on the function in the catalog (policy, default, check, index, view, trigger: pg_depend).
     A function with a SECURITY INVOKER caller (a trigger firing as the signed-in user, or an RPC such as file_report) is EXCLUDED and the header says why.
 (b) D2-06: _command_auto() records the swallowed race (an administrator turned a mode on at the same moment) as an event, best-effort (the 0187 pattern).
     file_report() (D2-07) is deliberately NOT touched: the core filing path already survives failures (proved by inject.py).
 (c) D3-07: assign_case's notices without report_id are deliberate ("it is no longer theirs to open": linking the case would make _notifications_scope drop the notice
     for the staff member who just lost the case): left as is, nothing to generate.
Emits supabase/drafts/0192_mechanical_fixes.sql + 0192_undo.sql + tests/76_mechanical_fixes.test.sql; the test fails before and passes after on a scratch database,
the undo is tested. usage: SWEEP_PORT=.. FIX_TEMPLATE=postgres python fix/gen_mechanical_fixes.py"""
import json, re
from fixlib import *


def classify():
    cg = json.loads(read(OUT / "callgraph.json"))["functions"]
    dbo = sorted(n for n, r in cg.items() if r["api_callable"] and r["class"] == "DB-ONLY")
    meta = {r["proname"]: r for r in psqlj("select p.proname, p.prosecdef sd, p.prorettype::regtype::text ret, p.oid::regprocedure::text sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'")}
    safe, excluded = [], []
    for n in dbo:
        inv = [c for c in cg[n]["db_callers"] if not meta[c]["sd"]]
        deps = int(psql(f"select count(*) from pg_depend d join pg_proc p on p.oid = d.refobjid where p.proname = '{n}' and p.pronamespace = 'public'::regnamespace and d.deptype = 'n'")[0][0])
        if inv: excluded.append((n, f"a SECURITY INVOKER caller runs it as the signed-in user: {', '.join(inv[:3])}"))
        elif deps: excluded.append((n, f"{deps} catalog object(s) depend on it (policy, default, check, index or view)"))
        elif cg[n].get("string_refs"): excluded.append((n, "a client file names it as a string"))
        else: safe.append((n, meta[n]["sig"], cg[n]["db_callers"]))
    return safe, excluded


def main():
    safe, excluded = classify()
    G = grants()["fn"]
    up_rev = "\n".join(f"revoke all on function {sig} from public, anon, authenticated;   -- called only by: {', '.join(cl[:4])}" for n, sig, cl in safe)
    acls = {n: [r[0] for r in psql(f"select coalesce(case when a.grantee = 0 then 'public' else a.grantee::regrole::text end, '') from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = '{sig}'::regprocedure and a.grantee <> p.proowner and a.privilege_type = 'EXECUTE' order by 1")] for n, sig, cl in safe}
    undo_rev = chr(10).join(f"revoke all on function {sig} from public, anon, authenticated, service_role;" + chr(10) + f"grant execute on function {sig} to {', '.join(acls[n]) if acls[n] else 'service_role'};" for n, sig, cl in safe)
    ca_old = fn_def("_command_auto()")
    old_handler = "exception when unique_violation then null;   -- an administrator turned one on at the same moment"
    if old_handler not in ca_old:
        raise SystemExit("_command_auto's handler has changed shape; do by hand")
    ca_new = ca_old.replace(old_handler, "exception when unique_violation then\n"
                            "  -- an administrator turned one on at the same moment: nothing to do, but leave a trace (0187's best-effort event log)\n"
                            "  begin\n    perform public._smart_event('command_auto_skipped', null, 'SMART auto switch skipped: an administrator turned a mode on at the same moment', '{}'::jsonb);\n"
                            "  exception when others then null;\n  end;").replace("CREATE OR REPLACE FUNCTION", "create or replace function")
    up = "set search_path = public, extensions;\nset local lock_timeout = '5s';\n\n-- (a) C-03: API rights nothing needs\n" + up_rev + "\n\n-- (b) D2-06: _command_auto records its swallowed race\n" + ca_new
    undo = ("-- UNDO of 0192_mechanical_fixes: the grants as they were and _command_auto as it was (tested). No data changes.\nset search_path = public, extensions;\n" + undo_rev + "\n\n"
            + ca_old.replace("CREATE OR REPLACE FUNCTION", "create or replace function") + "\n")
    why = (f"Ace: 'mechanical fixes do'. Three parts.\n"
           f"(a) C-03: {len(safe)} functions are callable by the API but only other database code calls them; revoking the API's right is safe for exactly these because EVERY caller is\n"
           f"SECURITY DEFINER (runs as the owner, which keeps its right) and nothing else in the catalog depends on them (pg_depend: no policy, default, check, index or view):\n"
           f"  {', '.join(n for n, s, c in safe)}.\n"
           f"EXCLUDED, with the reason (revoking would break them):\n" + "\n".join(f"  {n}: {r}" for n, r in excluded) + "\n"
           f"(b) D2-06: _command_auto() swallowed one specific, benign error (unique_violation: an administrator turned a mode on in the same moment) without a trace; it now records a\n"
           f"'command_auto_skipped' event, best-effort. D2-07 (file_report) is accepted as it is: the core filing path, proved to survive failures.\n"
           f"(c) D3-07: assign_case's notices without a case link are deliberate (the staff member who lost the case must not be sent a link they can no longer open): left as is.")
    mode = psql("select mode from public.command_modes order by 1 limit 1")[0][0]
    revoked = ", ".join(f"'{sig}'" for n, sig, cl in safe)
    kept = ", ".join(f"'{psql(f'''select oid::regprocedure::text from pg_proc where proname = '{n}' and pronamespace = 'public'::regnamespace''')[0][0]}'" for n, r in excluded)
    checks = [
        (f"the {len(safe)} database-only functions are no longer executable by signed-in or signed-out callers (and still exist)",
         f"    foreach s in array array[{revoked}] loop\n      perform s::regprocedure;\n      if has_function_privilege('authenticated', s::regprocedure, 'execute') or has_function_privilege('anon', s::regprocedure, 'execute') then raise exception '% is still executable by the API', s; end if;\n    end loop;"),
        (f"the {len(excluded)} excluded functions keep their rights (a SECURITY INVOKER caller or a dependent object needs them)",
         f"    foreach s in array array[{kept}] loop\n      if not has_function_privilege('authenticated', s::regprocedure, 'execute') then raise exception '% lost a right it needs', s; end if;\n    end loop;"),
        ("a resident still files a report (triggers and the invoker chain through the excluded helpers still work) and a signed-in call to a revoked helper is refused",
         as_role("v_res", "    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Mech probe', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);\n"
                          "    if not exists (select 1 from public.reports where subject = 'Mech probe') then raise exception 'filing failed'; end if;\n"
                          "    begin perform public.display_name('Reyes, Maria'); raise exception 'a signed-in resident can still call display_name'; exception when insufficient_privilege then null; end;")),
        ("_command_auto records the race with an administrator instead of swallowing it silently",
         f"    update public.command_state set auto_switch = true where id = 1;\n"
         f"    create or replace function public.feature_on(p_key text) returns boolean language sql as 'select true';\n"
         f"    create or replace function public._command_active() returns public.command_sessions language sql as 'select null::public.command_sessions';\n"
         f"    create or replace function public._command_suggestion(p_signal smallint default null) returns jsonb language sql as $f$ select '{{\"mode\":\"{mode}\",\"name_en\":\"Probe\",\"why_en\":\"probe\"}}'::jsonb $f$;\n"
         f"    insert into public.command_sessions (mode, how, reason) values ('{mode}', 'admin', 'an administrator got there first');\n"
         f"    perform public._command_auto();\n"
         f"    if not exists (select 1 from public.smart_events where kind = 'command_auto_skipped') then raise exception 'the skipped auto switch left no event'; end if;"),
    ]
    test_sql = test_text(checks)
    undo_note = "supabase/drafts/0192_undo.sql restores the grants on the revoked functions and _command_auto word for word (tested); no data changes."
    num, proven = emit_and_prove("mechanical_fixes", "mechanical fixes: revoke the API's right on database-only helpers (proved safe), record _command_auto's swallowed race",
                                 why, undo_note, up, "-- see supabase/drafts/0192_undo.sql", test_sql, "gen_mechanical_fixes.py")
    wt(DRAFTS / "0192_undo.sql", undo)
    t = DRAFTS / "tests" / f"{num}_mechanical_fixes.test.sql"
    if t.exists(): t.replace(DRAFTS / "tests" / "76_mechanical_fixes.test.sql")
    f = DRAFTS / f"{num}_mechanical_fixes.sql"; wt(f, read(f).replace(f"tests/{num}_mechanical_fixes.test.sql", "tests/76_mechanical_fixes.test.sql"))
    scratch()
    import hashlib
    sig = lambda: hashlib.md5((psql("select string_agg(p.oid::regprocedure::text || ':' || (select coalesce(string_agg(case when a.grantee = 0 then 'public' else a.grantee::regrole::text end || '=' || a.privilege_type, ',' order by a.grantee), '') from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '|' order by p.oid::regprocedure::text) from pg_proc p where p.pronamespace = 'public'::regnamespace", db=SCRATCH, raw=True) + psql("select pg_get_functiondef('public._command_auto()'::regprocedure)", db=SCRATCH, raw=True)).replace(chr(13), "").encode()).hexdigest()
    h0 = sig(); run_sql(DRAFTS / f"{num}_mechanical_fixes.sql"); h1 = sig(); run_sql(DRAFTS / "0192_undo.sql"); h2 = sig()
    print(f"  safe to revoke {len(safe)}; excluded {len(excluded)}; undo tested: draft changes the catalog: {h0 != h1}; the undo restores grants and body exactly: {h0 == h2}")
    json.dump({"revoked": [n for n, s, c in safe], "excluded": excluded}, open(OUT / "mechanical_0192.json", "w"), indent=1)


def test_text(checks):
    t = test_file("mechanical_fixes (draft test for 0192; moves to supabase/tests when Ace says apply 0192)", checks)
    return t.replace("  v_case uuid; n integer;", "  v_case uuid; n integer; s text;")


if __name__ == "__main__":
    main()
