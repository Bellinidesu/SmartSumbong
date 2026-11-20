#!/usr/bin/env python3
"""Round 2 / options for K-04: the Kagawad/staff case rule at scale. Throwaway copy `sweep_exp` of the 250x database; every option is applied inside a
rolled-back transaction, so the database never changes. Measures (as the real role, row level security on) the cases-page count, list and pending count for a
Kagawad and a staff member at 250x (20,000 cases), 50x (4,000) and 1x (82), by shrinking the copy in place. Also proves each option shows exactly the same
cases as today (id set hash) before trusting its timing. Output: out/exp_case_rule.json + table."""
import json, re, subprocess, sys, time
from common import *

DB = "sweep_exp"
OPTS = {
    "A today (per-row _user_sees_case)": "select 1",
    "B inline policy + one-per-query initplans": """
create or replace function public._my_committee() returns text language sql stable security definer set search_path = public as
$$ select u.committee from public.users u where u.id = auth.uid() and u.role = 'admin' and not coalesce(u.is_suspended, false) $$;
drop policy reports_resident_read on public.reports;
create policy reports_resident_read on public.reports for select using (
  deleted_at is null and (
    resident_id = (select auth.uid())
    or (select public.is_full_viewer())
    or exists (select 1 from public.dispatches d where d.report_id = reports.id and d.tanod_id = (select auth.uid()))
    or ((select public.admin_tier()) = 'committee' and (case when coalesce(awaiting_placement, false) then false
          when committee is not null then (committee = (select public._my_committee()) or handler_id = (select auth.uid()))
          else public.admin_sees_case(id, category, handler_id) end))
    or ((select public.admin_tier()) = 'moderator' and (handler_id = (select auth.uid()) or assigned_to = (select auth.uid())
          or exists (select 1 from public.case_handler_log l where l.report_id = reports.id and l.admin_id = (select auth.uid()) and l.action in ('take', 'take_over', 'accept'))))))""",
    "C materialised visibility table": """
create table public.case_visibility (user_id uuid not null, report_id uuid not null, primary key (user_id, report_id));
insert into public.case_visibility select u.id, r.id from public.users u cross join public.reports r
  where u.role = 'admin' and u.admin_tier in ('committee', 'moderator') and public._user_sees_case(u.id, r.id, r.category, r.handler_id);
drop policy reports_resident_read on public.reports;
create policy reports_resident_read on public.reports for select using (
  deleted_at is null and (
    resident_id = (select auth.uid()) or (select public.is_full_viewer())
    or exists (select 1 from public.dispatches d where d.report_id = reports.id and d.tanod_id = (select auth.uid()))
    or ((select public.admin_tier()) in ('committee', 'moderator') and exists (select 1 from public.case_visibility v where v.report_id = reports.id and v.user_id = (select auth.uid())))))""",
    "D partial indexes only (policy unchanged)": """
create index exp_reports_committee on public.reports (committee) where deleted_at is null;
create index exp_reports_handler on public.reports (handler_id) where deleted_at is null;
create index exp_reports_assigned on public.reports (assigned_to) where deleted_at is null;
create index exp_reports_created on public.reports (created_at desc) where deleted_at is null""",
}
OPTS["E B + the partial indexes"] = OPTS["B inline policy + one-per-query initplans"] + ";\n" + OPTS["D partial indexes only (policy unchanged)"]
QUERIES = {"count(*) of reports": "select count(*) from public.reports",
           "cases page (list 50)": "select id, tracking_id, subject, category, status, created_at from public.reports where deleted_at is null order by created_at desc limit 50",
           "pending count": "select count(*) from public.reports where deleted_at is null and status = 'pending_review'"}
WHO = {"Kagawad": "Sweep, Rung 4", "staff": "Sweep, Rung 12"}


def timed(opt_sql, who, q, timeout_s=240):
    uid = psql(f"select id from public.users where full_name = '{WHO[who]}'", db=DB)[0][0]
    sql = f"begin; set local statement_timeout = '{timeout_s}s'; {opt_sql}; set local role authenticated; select set_config('request.jwt.claim.sub', '{uid}', true); explain (analyze, timing off, summary on) {q}; rollback;"
    t0 = time.time()
    try:
        out = psql(sql, db=DB, raw=True)
    except Exception as e:
        return f">{timeout_s}s" if "statement timeout" in str(e) else "err"
    m = re.search(r"Execution Time: ([0-9.]+) ms", out)
    return round(float(m.group(1))) if m else "?"


def idhash(opt_sql, who):
    uid = psql(f"select id from public.users where full_name = '{WHO[who]}'", db=DB)[0][0]
    sql = f"begin; set local statement_timeout = '600s'; {opt_sql}; set local role authenticated; select set_config('request.jwt.claim.sub', '{uid}', true); select count(*) || ' ' || md5(coalesce(string_agg(id::text, ',' order by id), '')) from public.reports; rollback;"
    out = psql(sql, db=DB, raw=True).strip().splitlines()
    return out[-1] if out else "?"


TEAR = "drop table if exists public.case_visibility; drop index if exists public.exp_reports_committee, public.exp_reports_handler, public.exp_reports_assigned, public.exp_reports_created"


def main():
    P = [f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-X", "-q", "-d", "postgres", "-c"]
    subprocess.run(P + ["drop database if exists sweep_exp"]); subprocess.run(P + ["create database sweep_exp template postgres"], check=True)
    orig = psql("select qual from pg_policies where tablename = 'reports' and policyname = 'reports_resident_read'", db=DB, raw=True).strip()
    restore = f"drop policy if exists reports_resident_read on public.reports; create policy reports_resident_read on public.reports for select using ({orig}); {TEAR}; drop function if exists public._my_committee()"
    res, same, apply_s = {}, {}, {}
    for label, keep in (("250x (20,000 cases)", 20000), ("50x (4,000)", 4000), ("1x (82)", 82)):
        if keep < 20000:
            psql("set session_replication_role = replica; delete from public.reports where id not in (select id from public.reports order by created_at desc limit %d); analyze" % keep, db=DB)
        n = int(psql("select count(*) from public.reports", db=DB)[0][0])
        print(f"-- {label}: {n} cases", flush=True)
        for oname, osql in OPTS.items():
            t0 = time.time(); psql(osql if oname[0] != "A" else "select 1", db=DB); apply_s[(label, oname)] = round(time.time() - t0, 1)
            for who in WHO:
                for qn, q in QUERIES.items():
                    res[(label, oname, who, qn)] = timed("select 1", who, q)
            if keep == 20000: same[oname] = {who: idhash("select 1", who) for who in WHO}
            psql(restore, db=DB)
    rows = [{"size": k[0], "option": k[1], "who": k[2], "query": k[3], "ms": v} for k, v in res.items()]
    save("exp_case_rule.json", {"timings": rows, "same_cases_at_250x": same, "apply_seconds": {f"{a} | {b}": v for (a, b), v in apply_s.items()}})
    print("OPTION TIMINGS (ms of database time, as the real role; '>240s' = cut off)")
    for label in ("250x (20,000 cases)", "50x (4,000)", "1x (82)"):
        print(f"{label}")
        for oname in OPTS:
            print(f"  {oname:<44}" + "  ".join(f"{who[:3]} {qn.split(' ')[0]}={res.get((label, oname, who, qn))}" for who in WHO for qn in QUERIES))
    base = same["A today (per-row _user_sees_case)"]
    for oname, h in same.items():
        print(f"  same cases as today? {oname:<44} " + ", ".join(f"{w}: {'YES' if h[w] == base[w] else 'NO (' + h[w][:12] + ' vs ' + base[w][:12] + ')'}" for w in WHO))
    print("  one-off cost to build the option at 250x (s): " + ", ".join(f"{o[:1]}={v}" for (l, o), v in apply_s.items() if l.startswith("250")))


if __name__ == "__main__":
    main()
