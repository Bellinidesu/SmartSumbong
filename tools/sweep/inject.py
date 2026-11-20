#!/usr/bin/env python3
"""Round 2 / (2d): FAILURE INJECTION on sweep_probe. For each side effect (SMART scoring, SMART events, notification delivery, push via pg_net, secrets vault,
the status-log chain) make it raise, run the main presses as the right actor, and record: did the press still succeed, and was the failure recorded
anywhere (new rows in any log/event/error/alert/audit table). Everything runs in a rolled-back subtransaction. Output: out/inject.json + compact table."""
import json
from common import *
from probe import sql_file, ACTORS, DB

INJECT = {
    "none (control)": "select 1",
    "SMART scoring unavailable (lexicon table gone)": "alter table public.smart_lexicon rename to smart_lexicon_x",
    "smart_triage() raises": "@replace:smart_triage(uuid)",
    "SMART event log raises": "@replace:_smart_event(text,uuid,text,jsonb)",
    "notification trigger raises": "create or replace function public._notifications_scope() returns trigger language plpgsql as $f$ begin raise exception 'injected: notification delivery down'; end $f$",
    "push (pg_net) raises": "create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds integer default 5000) returns bigint language plpgsql as $f$ begin raise exception 'injected: push gateway down'; end $f$",
    "secrets vault missing": "alter view vault.decrypted_secrets rename to decrypted_secrets_x",
    "status-log chain raises": "create or replace function public.chain_status_log() returns trigger language plpgsql as $f$ begin raise exception 'injected: audit chain down'; end $f$",
}
PRESSES = {   # label: (actor, state, variant, call)
    "file_report (resident)": ("res1", None, 0, "select public.file_report(p_category => 'peace_order_nuisance', p_subject => 'Probe file', p_description => 'Videoke hanggang hatinggabi sa kanto.', p_latitude => 14.51944, p_longitude => 121.01219)"),
    "review_report validate (Kagawad)": ("kag1", "pending_review", 0, "select public.review_report('{report}'::uuid, 'validate')"),
    "admin_dispatch (Kagawad)": ("kag1", "validated", 1, "select public.set_resolution_target(p_report => '{report}'::uuid, p_due => now() + interval '3 days', p_reason => 'probe'); select public.admin_dispatch('{report}'::uuid, '{tan1}'::uuid, 'probe')"),
    "post_report_message (resident)": ("res1", "in_progress", 1, "select public.post_report_message('{report}'::uuid, 'hello from the resident')"),
    "request_reopen (resident)": ("res1", "resolved", 1, "select public.request_reopen('{report}'::uuid, 'still flooding')"),
    "cancel_report (resident)": ("res1", "pending_review", 0, "select public.cancel_report('{report}'::uuid, 'probe')"),
}
LOGLIKE = "(error|event|alert|health|audit|log|failure|smart_events|chat_state)"


def resolve(inj_sql):
    if not inj_sql.startswith("@replace:"):
        return inj_sql
    sig = inj_sql.split(":", 1)[1]
    r = psqlj(f"select p.proname, pg_get_function_arguments(p.oid) a, pg_get_function_result(p.oid) r from pg_proc p where p.oid = 'public.{sig}'::regprocedure", db=DB)[0]
    return f"create or replace function public.{r['proname']}({r['a']}) returns {r['r']} language plpgsql as $f$ begin raise exception 'injected: {r['proname']} down'; end $f$"


def block(inj_label, inj_sql, label, actor, st, v, call):
    inj_sql = resolve(inj_sql)
    ctx = f"sweep.mk_ctx('{st}', {v})" if st else "'{}'::jsonb"
    return f"""do $p$
declare ctx jsonb; sql text; res text := 'ok'; k text; before jsonb; after jsonb; newrows jsonb; out jsonb;
begin
  begin
    ctx := {ctx};
    select jsonb_object_agg(c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text::int) into before
      from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname ~ '{LOGLIKE}';
    execute $i${inj_sql}$i$;
    sql := $c${call}$c$;
    for k in select jsonb_object_keys(ctx) loop sql := replace(sql, '{{' || k || '}}', coalesce(ctx->>k, '')); end loop;
    for k in select name from sweep.actors loop sql := replace(sql, '{{' || k || '}}', sweep.a(k)::text); end loop;
    perform set_config('request.jwt.claim.sub', sweep.a('{actor}')::text, true); perform set_config('request.jwt.claim.role', 'authenticated', true); set local role authenticated;
    begin execute sql; exception when others then res := sqlstate || ':' || left(sqlerrm, 90); end;
    reset role;
    select jsonb_object_agg(c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text::int) into after
      from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname ~ '{LOGLIKE}';
    select coalesce(jsonb_object_agg(a.key, (a.value::text::int - coalesce((before->>a.key)::int, 0))) filter (where a.value::text::int > coalesce((before->>a.key)::int, 0)), '{{}}') into newrows from jsonb_each(after) a;
    out := jsonb_build_object('inj', $l1${inj_label}$l1$, 'press', $l2${label}$l2$, 'res', res, 'new_rows', newrows);
    raise exception 'sweep' using errcode = 'SW001';
  exception when others then
    if sqlstate <> 'SW001' then out := jsonb_build_object('inj', $l1${inj_label}$l1$, 'press', $l2${label}$l2$, 'res', 'SETUP:' || sqlstate || ':' || left(sqlerrm, 90)); end if;
  end;
  insert into sweep.results values ('inject', 'inject', out);
end $p$;
"""


def main():
    sql_file(ROOT / "tools/sweep/sql/probe_setup.sql")
    psql("delete from sweep.results where kind = 'inject'", db=DB)
    f = OUT / "inject.sql"
    for il, isql in INJECT.items():
        for pl, (actor, st, v, call) in PRESSES.items():
            f.write_text(block(il, isql, pl, actor, st, v, call), encoding="utf-8")
            sql_file(f)
    rows = [r["data"] for r in psqlj("select data from sweep.results where kind = 'inject'", db=DB)]
    save("inject.json", rows)
    ctrl = {r["press"]: r["res"] for r in rows if r["inj"].startswith("none")}
    bad = []
    print("FAILURE INJECTION (press result under each injected failure; 'ok' = press still worked)")
    for il in INJECT:
        line = []
        for r in rows:
            if r["inj"] != il: continue
            ok = r["res"] == "ok"
            rec = ",".join(f"{k}+{v}" for k, v in (r.get("new_rows") or {}).items())
            line.append(f"{r['press'].split(' (')[0].split(' validate')[0]}={'ok' if ok else 'FAILS'}")
            if il.startswith("none") or ctrl.get(r["press"]) != "ok": continue
            if not ok and not il.startswith("status-log"):
                bad.append(f"{il}: '{r['press']}' FAILS ({r['res'][:60]}): a side effect that should be best-effort aborts the main action")
            if ok and r["press"].startswith("file_report") and not il.startswith(("secrets", "status-log", "push")) and not any(k in (r.get("new_rows") or {}) for k in ("smart_events", "error_log", "system_alerts")):
                bad.append(f"{il}: file_report still succeeds (good) but the failure is recorded nowhere (no error/event row), so nobody learns the engine/notice is broken")
        print(f"  {il:<44}" + " ".join(line))
    for b in sorted(set(bad)): print("  FINDING:", b[:220])
    save("inject_findings.json", sorted(set(bad)))


if __name__ == "__main__":
    main()
