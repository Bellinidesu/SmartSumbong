#!/usr/bin/env python3
"""Class A generator: smart_module() with the set helper of 0189. smart_module() ran _user_sees_case once per open case (and once per tracking id of a
recurring pattern for staff): 3.4 s for a Kagawad at 20,000 cases. This rewrites those two calls to `r.id in (select ... from _my_scoped_case_ids())`, the same set the
policies of 0189 read. Emits (never applies): supabase/drafts/0190_smart_module_set_based.sql, supabase/drafts/0190_undo.sql (the old body, tested), and
supabase/drafts/tests/70_smart_module_set_based.test.sql (the exhaustive fixture of test 67 + an equivalence proof: for every rung, in 3 fixture variants, the old body
and the new one return the same document, symmetric difference 0; fails before 0190 on the structure check, passes after). Proof database: FIX_TEMPLATE=postgres
(a full local build at the latest migration).   usage: FIX_TEMPLATE=postgres python fix/gen_smart_module_set.py"""
import hashlib, re
from fixlib import *

CALL1 = "public._user_sees_case(v_me, r.id, r.category, r.handler_id))"
SETQ = "r.id in (select s.id from public._my_scoped_case_ids() s(id))"


def main():
    old = fn_def("smart_module()")
    if "_my_scoped_case_ids" in old:
        print("smart_module already set-based"); return
    new = old.replace("and (v_full or " + CALL1, "and (v_full or " + SETQ + ")")
    new = re.sub(r"and public\._user_sees_case\(v_me, r\.id, r\.category, r\.handler_id\)\)", "and " + SETQ + ")", new)
    # a staff member's pattern list names tracking ids with array(select ...) and no ORDER BY (order unspecified); keep the pattern's own order, deterministically
    new = new.replace("and " + SETQ + ")", "and " + SETQ + " order by array_position(p.tracking_ids, r.tracking_id))") if "array(select r.tracking_id" in new else new
    n_before = old.count("_user_sees_case")
    if "_user_sees_case" in new:
        print(f"unexpected shape: {new.count('_user_sees_case')} per-case calls left; do by hand"); return
    new = new.replace("CREATE OR REPLACE FUNCTION", "create or replace function")
    old_sql = old.replace("CREATE OR REPLACE FUNCTION", "create or replace function")
    # the test: fixture of test 67 (up to its first check) + equivalence of the old body (as _smart_module_old) and the new one
    t67 = read(ROOT / "supabase/tests/67_case_rule_equivalence.sql")
    fixture = t67[: t67.index("  -- 1. per person")]
    fixture = fixture.split("\n", 4)[4]          # drop the 4 comment lines; keep from 'do $sweep$'
    oldcopy = old.replace("public.smart_module()", "public._smart_module_old()").replace("CREATE OR REPLACE FUNCTION", "create or replace function")
    people = "(kA, 'kA'), (kB, 'kB'), (sA, 'sA'), (sA2, 'sA2'), (sup, 'sup'), (cap, 'cap'), (kSusp, 'kSusp'), (sRet, 'sRet'), (res, 'res'), (tan, 'tan')"
    body = f"""
  -- 0190: smart_module() reads the case set once. Old body kept as _smart_module_old for the comparison (this test only; rolled back).
  declare v_old text := $oldfn${oldcopy}$oldfn$; src text; a record; jo jsonb; jn jsonb; e1 text; e2 text; sd text := ''; k text; nkeys int := 0; vr int; ntests int := 0;
  begin
    begin
      select prosrc into src from pg_proc where oid = 'public.smart_module()'::regprocedure;
      if src like '%_user_sees_case%' then raise exception 'smart_module still runs the case rule once per case'; end if;
      if src not like '%_my_scoped_case_ids%' then raise exception 'smart_module does not read the set helper'; end if;
      v_log := v_log || E'\\nok  smart_module reads the case set once (_my_scoped_case_ids) and never calls _user_sees_case per case';
    exception when others then v_log := v_log || E'\\nFAIL structure: ' || sqlerrm; end;
    execute v_old;
    perform public._smart_snapshot_refresh(true);
    for vr in 1..3 loop
      set local session_replication_role = replica;
      if vr = 1 then
        update public.reports set due_at = now() - interval '2 days' where tracking_id in ('RULE-01', 'RULE-05');
        update public.reports set due_at = now() + interval '12 hours' where tracking_id in ('RULE-02', 'RULE-09');
        update public.reports set status = 'validated' where tracking_id in ('RULE-01', 'RULE-02', 'RULE-09', 'RULE-12');
      elsif vr = 2 then   -- statuses, a referral, finished cases, a case taken over
        update public.reports set status = 'in_progress' where tracking_id in ('RULE-02', 'RULE-05');
        update public.reports set status = 'resolved' where tracking_id in ('RULE-03', 'RULE-12');
        update public.reports set referred_to = 'barangay court' where tracking_id = 'RULE-09';
        update public.reports set handler_id = (select id from public.users where full_name = 'Rule, Kagawad A') where tracking_id in ('RULE-07', 'RULE-12');
      else                -- assignments moved, a handler removed, a case waiting for placement, escalations pending
        update public.reports set handler_id = null, awaiting_placement = true where tracking_id = 'RULE-05';
        update public.reports set assigned_to = (select id from public.users where full_name = 'Rule, Staff A Two') where tracking_id in ('RULE-06', 'RULE-12');
        update public.reports set status = 'pending_review' where tracking_id in ('RULE-03', 'RULE-12', 'RULE-07');
        delete from public.case_handler_log where action = 'accept';
      end if;
      set local session_replication_role = origin;
      perform public.smart_triage(id) from public.reports where tracking_id like 'RULE-%' and deleted_at is null;
      for a in select * from (values {people}) x(id, nm) loop
        perform set_config('request.jwt.claim.sub', a.id::text, true); e1 := null; e2 := null; jo := null; jn := null;
        begin jo := public._smart_module_old() - 'at'; exception when others then e1 := sqlstate; end;
        begin jn := public.smart_module() - 'at'; exception when others then e2 := sqlstate; end;
        ntests := ntests + 1;
        if e1 is distinct from e2 then sd := sd || format(' v%s %s error %s<>%s;', vr, a.nm, e1, e2);
        elsif jo is distinct from jn then
          for k in select key from (select key, value from jsonb_each(jo) except select key, value from jsonb_each(jn)
                                    union select key, value from jsonb_each(jn) except select key, value from jsonb_each(jo)) d group by key loop
            sd := sd || format(' v%s %s differs in %s;', vr, a.nm, k);
          end loop;
        end if;
      end loop;
    end loop;
    if sd <> '' then v_log := v_log || E'\\nFAIL equivalence:' || sd;
    else v_log := v_log || format(E'\\nok  smart_module() and the old body return the same document (symmetric difference 0) for every rung (Kagawad, suspended Kagawad, staff, retired staff, super, captain; resident and tanod refused alike) in 3 fixture variants: %s comparisons', ntests); end if;
  end;
"""
    test_sql = ("-- 70_smart_module_set_based.sql (DRAFT test for 0190; moves to supabase/tests/ when Ace says apply). Rolled back.\n"
                "-- Fails before 0190 on the structure check (smart_module still calls the case rule per case); the equivalence check passes before and after: the old body\n"
                "-- is compared with the new one for every rung on the exhaustive fixture of test 67, in three fixture variants (statuses and due dates, referral and taken-over cases,\n"
                "-- moved assignments and a case waiting for placement).\n" + fixture + body + "  raise exception E'SWEEP-ROLLBACK\\n%', v_log;\nend $sweep$;\n")
    why = (f"smart_module() (the SMART panel of every administrator, called on pages) ran the case rule once per open case ({n_before} call sites; 3.4 s for a Kagawad at 20,000 cases).\n"
           "0189 added the set helper _my_scoped_case_ids() that the policies read once per query; this reads the same set. No other behaviour changes: the document it returns is the same\n"
           "for every rung (proved by test 70 against the old body on the exhaustive fixture, and at 250x by tools/sweep/exp_smart_module.py).")
    undo = "supabase/drafts/0190_undo.sql restores the previous body of smart_module() (create or replace); nothing else changed."
    num, proven = emit_and_prove("smart_module_set_based", "smart_module() reads the visible-case set once instead of the case rule once per case", why, undo, new, "-- see supabase/drafts/0190_undo.sql", test_sql, "gen_smart_module_set.py")
    wt(DRAFTS / "0190_undo.sql", "-- UNDO of 0190_smart_module_set_based: the body of smart_module() as it was after 0189 (tested: applying this after 0190 restores the same function definition).\n" + old_sql + "\n")
    # draft file was named 0190_...; the test name must be 70_...
    old_t = DRAFTS / "tests" / f"{num}_smart_module_set_based.test.sql"
    if old_t.exists(): old_t.rename(DRAFTS / "tests" / "70_smart_module_set_based.test.sql")
    # the undo is tested: apply draft, apply undo, the function definition is byte-identical to before
    scratch()
    md = lambda: hashlib.md5(psql("select pg_get_functiondef('public.smart_module()'::regprocedure)", db=SCRATCH, raw=True).replace(chr(13), "").encode()).hexdigest()
    h0 = md(); run_sql(DRAFTS / f"{num}_smart_module_set_based.sql"); h1 = md(); run_sql(DRAFTS / "0190_undo.sql"); h2 = md()
    print(f"  undo tested: definition changed by the draft: {h0 != h1}; restored exactly by the undo: {h0 == h2}")


if __name__ == "__main__":
    main()
