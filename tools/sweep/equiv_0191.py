#!/usr/bin/env python3
"""0191 EQUIVALENCE PROOF with the four intended differences written down as the ONLY allowed ones. Exhaustive fixture (sql/equiv_fixture.sql: every rung and
state x every case variant, 22 tables) on a copy of the pristine database k04_base (= main, 0001-0190). For every person, under row level security as the API's own role:
  rows read in each of the 22 tables, the per-case function _user_sees_case per case, the set helper _my_scoped_case_ids(), and whether a notice about the case is stored
is snapshotted under TODAY's definitions ('old'), after supabase/drafts/0191_case_rule_consistency.sql ('new') and after supabase/drafts/0191_undo.sql ('undo').
Then, per (person, case) and per (person, table row), the differences old -> new are classified against explicit predicates written from the four intended items
(NOT from the new code):  1 deleted  2 retired  3 committee switched off  4 awaiting placement, handler.  Any difference that matches no item is UNEXPECTED (= failure);
every pair an item says must change is checked to have changed (completeness, exact at the per-case-function level). undo must equal old everywhere.
usage: SWEEP_PORT=55444 python equiv_0191.py [--resume]      Output: out/equiv_0191.json + a compact table"""
import json, sys, time
from common import *
import equiv_case_rule as E

DRAFT = ROOT / "supabase" / "drafts" / "0191_case_rule_consistency.sql"
UNDO = ROOT / "supabase" / "drafts" / "0191_undo.sql"
DB = "sweep_equiv191"
CASE_OF = {"reports": "x.id", "dispatch_media": "(select d.report_id from public.dispatches d where d.id = x.dispatch_id)",
           "dispatch_updates": "(select d.report_id from public.dispatches d where d.id = x.dispatch_id)", "users": "null::uuid"}
ATTRS = """create or replace view eq.attrs as
  select a.name, a.id, u.role::text role, u.admin_tier tier, u.committee, coalesce(u.is_suspended, false) susp, coalesce(u.is_retired, false) ret,
         coalesce((select c.active from public.committees c where c.key = u.committee), false) comm_on
    from eq.actors a left join public.users u on u.id = a.id;
create or replace view eq.cases as
  select r.id, r.category, r.committee, r.handler_id, coalesce(r.awaiting_placement, false) awaiting, (r.deleted_at is not null) deleted from public.reports r;"""
# the four intended items, as predicates on (person a, case c). They say what MAY change and, for the per-case function, what MUST.
P1 = "(a.role = 'admin' and not a.susp and a.tier in ('committee', 'moderator') and c.deleted)"
P2 = "(a.role = 'admin' and a.ret)"
P3 = "(a.role = 'admin' and not a.susp and not a.ret and a.tier = 'committee' and c.committee = a.committee and not a.comm_on and c.handler_id is distinct from a.id and not c.awaiting and not c.deleted)"
P4 = "(a.role = 'admin' and not a.susp and not a.ret and a.tier is not null and c.awaiting and c.handler_id = a.id and not (c.deleted and a.tier in ('committee', 'moderator')))"


def snapshot(label):
    cols = {t: bool(psql(f"select 1 from information_schema.columns where table_schema = 'public' and table_name = '{t}' and column_name = 'id'", db=DB)) for t in E.TABLES}
    psql(f"delete from eq.snap where label = '{label}'", db=DB)
    parts = []
    for t in E.TABLES:
        rid = "x.id::text" if cols[t] else "null"
        case = CASE_OF.get(t, "x.report_id")
        parts.append(f"foreach t in array array['{t}'] loop perform set_config('request.jwt.claim.sub', a.id::text, true); perform set_config('request.jwt.claims', json_build_object('sub', a.id, 'role', 'authenticated')::text, true); "
                     f"execute 'set local role authenticated'; execute format('insert into eq.snap(label, actor, tbl, k, rid, cid) select %L, %L, %L, md5(x::text), {rid}, {case}::text from public.%I x', '{label}', a.name, t, t); execute 'reset role'; end loop;")
    sql = f"""do $s$ declare a record; t text; r record; stored boolean; begin
  for a in select * from eq.actors order by name loop
    {' '.join(parts)}
    insert into eq.snap(label, actor, tbl, k, rid) select '{label}', a.name, 'fn:usc', '', r2.id::text from public.reports r2 where public._user_sees_case(a.id, r2.id, r2.category, r2.handler_id);
    perform set_config('request.jwt.claim.sub', a.id::text, true);
    insert into eq.snap(label, actor, tbl, k, rid) select '{label}', a.name, 'fn:set', '', x::text from public._my_scoped_case_ids() x where exists (select 1 from pg_proc where proname = '_my_scoped_case_ids');
    -- is a notice about the case stored for this person? (the trigger decides; every 7th case, rolled back each time)
    for r in select id from public.reports where tracking_id like 'EQ-%' order by tracking_id offset 0 limit 100000 loop
      if hashtext(r.id::text) % 7 <> 0 then continue; end if;
      stored := false;
      begin
        insert into public.notifications (user_id, report_id, kind, message) values (a.id, r.id, 'status_change', 'eq probe');
        stored := exists (select 1 from public.notifications where user_id = a.id and report_id = r.id and message = 'eq probe');
        raise exception 'eq-rollback' using errcode = 'SW001';
      exception when sqlstate 'SW001' then null; end;
      if stored then insert into eq.snap(label, actor, tbl, k, rid) values ('{label}', a.name, 'fn:notice', '', r.id::text); end if;
    end loop;
  end loop; end $s$;"""
    # eq.snap is written to by the DO block as the superuser, and by role authenticated inside it (granted)
    t0 = time.time(); psql(sql, db=DB); return round(time.time() - t0, 1)


def classify():
    """differences old->new per table and per function pair, against the four predicates. Returns the counts and the unexpected ones."""
    out = {"tables": {}, "fn": {}}
    for tbl in E.TABLES:
        # a row (actor, k) lost = in old not in new; gained = in new not old. Its case via cid
        rows = psql(f"""with o as (select actor, k, max(rid) rid, max(cid) cid from eq.snap where label = 'old' and tbl = '{tbl}' group by 1, 2),
                             n as (select actor, k, max(rid) rid, max(cid) cid from eq.snap where label = 'new' and tbl = '{tbl}' group by 1, 2),
                             l as (select o.actor, o.cid, 'lost' dir from o left join n using (actor, k) where n.k is null),
                             g as (select n.actor, n.cid, 'gained' dir from n left join o using (actor, k) where o.k is null),
                             d as (select * from l union all select * from g)
                        select d.dir,
                               case when d.cid is null then 'nocase'
                                    when d.dir = 'lost' and {P1} then '1 deleted'
                                    when d.dir = 'lost' and {P3} then '3 committee off'
                                    when d.dir = 'gained' and {P4} then '4 awaiting'
                                    else 'UNEXPECTED' end item, count(*)
                          from d join eq.attrs a on a.name = d.actor left join eq.cases c on c.id::text = d.cid group by 1, 2 order by 1, 2""", db=DB)
        out["tables"][tbl] = {f"{r[0]}:{r[1]}": int(r[2]) for r in rows}
    # per-case function, exact: new must equal (old minus P1,P2,P3) plus (P4 not in old)
    q = lambda label: f"select actor, rid from eq.snap where label = '{label}' and tbl = 'fn:usc'"
    exp = f"""with o as ({q('old')}), n as ({q('new')}),
        pairs as (select a.name actor, c.id::text rid, a, c from eq.attrs a cross join eq.cases c),
        old_true as (select * from o),
        expected as (
          select actor, rid from o where not exists (select 1 from eq.attrs a join eq.cases c on c.id::text = o.rid where a.name = o.actor and ({P1} or {P2} or {P3}))
          union
          select a.name, c.id::text from eq.attrs a cross join eq.cases c where {P4} and not exists (select 1 from o where o.actor = a.name and o.rid = c.id::text)
                                                                          and not ({P2})
        )
        select (select count(*) from o) old_n, (select count(*) from n) new_n,
               (select count(*) from (select * from expected except select * from n) q) missing,
               (select count(*) from (select * from n except select * from expected) q) extra,
               (select count(*) from (select a.name, c.id::text from eq.attrs a join o on o.actor = a.name join eq.cases c on c.id::text = o.rid where {P1}) q) p1,
               (select count(*) from (select a.name, c.id::text from eq.attrs a join o on o.actor = a.name join eq.cases c on c.id::text = o.rid where {P2} and not ({P1})) q) p2,
               (select count(*) from (select a.name, c.id::text from eq.attrs a join o on o.actor = a.name join eq.cases c on c.id::text = o.rid where {P3} and not ({P1}) and not ({P2})) q) p3,
               (select count(*) from (select a.name, c.id::text from eq.attrs a cross join eq.cases c where {P4} and not exists (select 1 from o where o.actor = a.name and o.rid = c.id::text) and not ({P2})) q) p4"""
    r = psql(exp, db=DB)[0]
    out["fn"]["usc"] = dict(zip(["old_true_pairs", "new_true_pairs", "expected_but_missing", "unexpected_extra", "item1_lost", "item2_lost", "item3_lost", "item4_gained"], map(int, r)))
    # lockstep in the NEW state: the set helper equals the per-case function for the scoped, active admins (Kagawad/staff), exactly
    r = psql("""with f as (select s.actor, s.rid from eq.snap s join eq.attrs a on a.name = s.actor where s.label = 'new' and s.tbl = 'fn:usc' and a.role = 'admin' and not a.susp and not a.ret and a.tier in ('committee', 'moderator')),
                     h as (select actor, rid from eq.snap where label = 'new' and tbl = 'fn:set')
                select (select count(*) from f), (select count(*) from h), (select count(*) from (select * from f except select * from h) q), (select count(*) from (select * from h except select * from f) q)""", db=DB)[0]
    out["fn"]["lockstep_new"] = dict(zip(["function_pairs", "set_pairs", "function_not_in_set", "set_not_in_function"], map(int, r)))
    # the stored-notice probe: differences only where the function (or retirement) changed
    r = psql("""with o as (select actor, rid from eq.snap where label = 'old' and tbl = 'fn:notice'), n as (select actor, rid from eq.snap where label = 'new' and tbl = 'fn:notice'),
                     l as (select * from o except select * from n), g as (select * from n except select * from o)
                select (select count(*) from o), (select count(*) from n), (select count(*) from l), (select count(*) from g),
                       (select count(*) from l join eq.attrs a on a.name = l.actor join eq.cases c on c.id::text = l.rid where """ + P1 + " or " + P2 + " or " + P3 + """),
                       (select count(*) from g join eq.attrs a on a.name = g.actor join eq.cases c on c.id::text = g.rid where """ + P4 + ")", db=DB)[0]
    out["fn"]["notices"] = dict(zip(["old_stored", "new_stored", "lost", "gained", "lost_explained", "gained_explained"], map(int, r)))
    # undo must equal old everywhere
    r = psql("""select count(*) from (select actor, tbl, k, rid from eq.snap where label = 'old' except select actor, tbl, k, rid from eq.snap where label = 'undo') q""", db=DB)[0]
    r2 = psql("""select count(*) from (select actor, tbl, k, rid from eq.snap where label = 'undo' except select actor, tbl, k, rid from eq.snap where label = 'old') q""", db=DB)[0]
    out["undo_differences"] = int(r[0]) + int(r2[0])
    return out


def main():
    P = E.P
    if "--resume" not in sys.argv:
        E.sh(P("postgres") + ["-c", f"drop database if exists {DB}", "-c", f"create database {DB} template k04_base"])
        t0 = time.time(); print(E.run_file(DB, ROOT / "tools/sweep/sql/equiv_fixture.sql").strip().splitlines()[-1:], f"fixture {round(time.time() - t0)}s", flush=True)
        psql("alter table eq.snap add column if not exists rid text, add column if not exists cid text", db=DB)
        psql(ATTRS, db=DB)
        psql("grant select on eq.attrs, eq.cases to authenticated", db=DB)
        steps = [("old", None), ("new", DRAFT), ("undo", UNDO)]
        # the draft must move from 'new' to 'undo' as a fresh apply each time: old -> apply draft -> new -> apply undo -> undo
        sec = {}
        for label, f in steps:
            if f: E.run_file(DB, f)
            sec[label] = snapshot(label); print(label, "snapshot", sec[label], "s", flush=True)
    res = classify()
    n_actors = int(psql("select count(*) from eq.actors", db=DB)[0][0]); n_cases = int(psql("select count(*) from public.reports", db=DB)[0][0])
    res["actors"], res["cases"] = n_actors, n_cases
    save("equiv_0191.json", res)
    print(f"EQUIVALENCE 0191: {n_actors} people x {n_cases} cases x {len(E.TABLES)} tables (exhaustive fixture)")
    unexpected = 0
    print(f"  {'table':<20}{'lost:1 deleted':>16}{'lost:3 comm off':>17}{'gained:4 await':>16}{'UNEXPECTED':>12}")
    for t in E.TABLES:
        d = res["tables"][t]; un = sum(v for k, v in d.items() if "UNEXPECTED" in k or (t != "users" and "nocase" in k))
        unexpected += un
        print(f"  {t:<20}{d.get('lost:1 deleted', 0):>16}{d.get('lost:3 committee off', 0):>17}{d.get('gained:4 awaiting', 0):>16}{un:>12}")
    f = res["fn"]["usc"]
    print(f"  per-case function: {f['old_true_pairs']} true pairs before, {f['new_true_pairs']} after; item 1 lost {f['item1_lost']}, item 2 lost {f['item2_lost']}, item 3 lost {f['item3_lost']}, item 4 gained {f['item4_gained']};"
          f" expected-but-missing {f['expected_but_missing']}, unexpected-extra {f['unexpected_extra']}")
    print(f"  lockstep (new): set helper vs function for Kagawad/staff: {res['fn']['lockstep_new']}")
    print(f"  notices stored: {res['fn']['notices']}; undo differences vs old: {res['undo_differences']}")
    bad = unexpected + f["expected_but_missing"] + f["unexpected_extra"] + res["undo_differences"] + sum(res["fn"]["lockstep_new"][k] for k in ("function_not_in_set", "set_not_in_function")) \
        + (res["fn"]["notices"]["lost"] - res["fn"]["notices"]["lost_explained"]) + (res["fn"]["notices"]["gained"] - res["fn"]["notices"]["gained_explained"])
    print("RESULT:", "ONLY THE FOUR INTENDED DIFFERENCES" if bad == 0 else f"UNEXPECTED DIFFERENCES ({bad})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
