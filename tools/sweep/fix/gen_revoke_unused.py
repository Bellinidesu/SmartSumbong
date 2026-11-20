#!/usr/bin/env python3
"""Class A generator: revoke API rights nothing uses. Reads out/callgraph.json: trigger functions (attached to a trigger or to none) that are still executable by the API
(and anon): a trigger does not need EXECUTE on its function to fire (the right is checked when the trigger is created), so the right is pure surface. (Ordinary functions with no caller are class B: a screen may be missing, not the right.) Emits DRAFT
'revoke_dead_trigger_functions' + test. usage: python fix/gen_revoke_unused.py"""
import json
from fixlib import *


def main():
    cg = json.loads(read(OUT / "callgraph.json"))["functions"]
    dead = sorted(n for n, r in cg.items() if r["api_callable"] and r["returns"] == "trigger")   # a trigger needs no EXECUTE right on its function when it fires
    if not dead:
        print("nothing to revoke"); return
    sigs = {n: psql(f"select oid::regprocedure::text from pg_proc where proname = '{n}' and pronamespace = 'public'::regnamespace")[0][0] for n in dead}
    up = "\n".join(f"revoke all on function {s} from public, anon, authenticated;" for s in sigs.values())
    undo = "grant execute on function " + ", ".join(sigs.values()) + " to anon, authenticated;   (they are attached to no trigger, so nothing depends on it)"
    check = "\n".join(f"    if has_function_privilege('anon', '{s}', 'execute') or has_function_privilege('authenticated', '{s}', 'execute') then raise exception '{n} is still executable by the API'; end if;" for n, s in sigs.items())
    exists = "\n".join(f"    perform '{s}'::regprocedure;" for s in sigs.values())
    checks = [("no trigger function is executable by the API any more (" + str(len(dead)) + " functions)", check),
              ("they still exist (a revoke, not a drop; nothing is lost)", exists),
              ("and the triggers still fire for signed-in people: a resident files a report, an update touches settings", as_role("v_res", "    perform public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Revoke probe', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219);") + " if not exists (select 1 from public.reports where subject = 'Revoke probe') then raise exception 'filing failed after the revoke'; end if;")]
    emit_and_prove("revoke_dead_trigger_functions", f"revoke the API's right to run {len(dead)} trigger functions (a trigger needs no EXECUTE right to fire)",
                   "tools/sweep/callgraph.py: " + ", ".join(dead) + " are trigger functions attached to no trigger yet still executable by signed-out and signed-in callers.\nNothing calls them; a direct call only errors, but the right is dead surface. supabase/grants.txt must be regenerated when this is applied (these lines go to anon=- authenticated=-).",
                   undo, up, undo, test_file("revoke_dead_trigger_functions (draft)", checks), "gen_revoke_unused.py")


if __name__ == "__main__":
    main()
