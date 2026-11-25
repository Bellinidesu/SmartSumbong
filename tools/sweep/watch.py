"""Daily watch until the defense (round 3, 25 Nov 2026). READ-ONLY, under 10 s, one screen. Run it every morning:

    python tools/sweep/watch.py            [--stuck-days 3]   exit 1 when something needs a look (a line marked !!)

What it looks at (counts and grouped error messages only; no names, numbers or addresses):
  sign-ups      auth accounts with no public.users row (the 23-24 Nov outage), unconfirmed derived (phone) addresses,
                sign-ups in the last 24 h, and whether both auth.users triggers are there
  errors        portal_errors seen in the last 24 h, grouped by source/page/message (digits, ids and addresses masked)
  mail          password-otp / SMTP errors in the last 24 h
  cases         reports still pending (not yet reviewed) for more than N days
  notices       smart_events notice_error / command_auto_skipped / engine_error in the last 24 h
  cron          each job's last run: failed, or no run for far longer than its schedule
  backup        the nightly backup workflow's last run (gh)
"""
import json, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, live_ro  # noqa: E402

DAYS = int(sys.argv[sys.argv.index("--stuck-days") + 1]) if "--stuck-days" in sys.argv else 3
SQL = f"""
select json_build_object(
  'orphans', (select count(*) from auth.users a where not exists (select 1 from public.users u where u.id = a.id)),
  'orphans_24h', (select count(*) from auth.users a where a.created_at > now() - interval '24 hours'
                    and not exists (select 1 from public.users u where u.id = a.id)),
  'unconfirmed_phone', (select count(*) from auth.users where email like '%@auth.smartsumbong.local' and email_confirmed_at is null),
  'signups_24h', (select count(*) from auth.users where created_at > now() - interval '24 hours'),
  'triggers', (select count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal and tgenabled = 'O'
                 and tgname in ('on_auth_user_created', 'auth_users_confirm_synthetic')),
  'errors', (select coalesce(json_agg(e order by e.n desc), '[]') from (
                select source, page, left(regexp_replace(regexp_replace(regexp_replace(message,
                         '[0-9a-f]{{8}}-[0-9a-f-]{{27}}', '<id>', 'gi'), '[^ ]+@[^ ]+', '<addr>', 'g'), '[0-9]+', '#', 'g'), 80) msg,
                       sum(count)::int n, max(last_seen) last
                  from public.portal_errors where last_seen > now() - interval '24 hours' group by 1, 2, 3 limit 12) e),
  'mail_errors', (select coalesce(sum(count), 0) from public.portal_errors where last_seen > now() - interval '24 hours'
                    and (page ilike '%password-otp%' or message ~* 'smtp|mail|semaphore')),
  'stuck', (select count(*) from public.reports where deleted_at is null and status = 'pending_review' and created_at < now() - interval '{DAYS} days'),
  'stuck_oldest_days', (select coalesce(extract(day from now() - min(created_at))::int, 0) from public.reports
                          where deleted_at is null and status = 'pending_review' and created_at < now() - interval '{DAYS} days'),
  'events', (select coalesce(json_object_agg(kind, n), '{{}}') from (select kind, count(*) n from public.smart_events
               where at > now() - interval '24 hours' and kind in ('notice_error', 'command_auto_skipped', 'engine_error') group by kind) k),
  'cron', (select coalesce(json_agg(c order by c.jobname), '[]') from (
             select j.jobname, j.schedule, j.active, d.status, d.start_time, left(regexp_replace(coalesce(d.return_message, ''), '[0-9]+', '#', 'g'), 70) msg
               from cron.job j left join lateral (select status, start_time, return_message from cron.job_run_details r
                                                   where r.jobid = j.jobid order by start_time desc limit 1) d on true) c)
)::text j"""


def every_minutes(s):
    """Rough period of a cron schedule in minutes (for 'has it run lately')."""
    m, h = (s.split() + ["*", "*"])[:2]
    if m.startswith("*/"): return int(m[2:])
    if m == "*": return 1
    if h.startswith("*/"): return int(h[2:]) * 60
    if h == "*": return 60
    return 1440


def main():
    from datetime import datetime, timezone
    d = json.loads(live_ro(SQL)[0]["j"])
    now = datetime.now(timezone.utc)
    bad = 0
    out = []

    def line(flag, text):
        nonlocal bad
        bad += flag
        out.append(("!! " if flag else "ok ") + text)

    line(d["triggers"] != 2, f"auth.users triggers: {d['triggers']}/2 present")
    line(d["orphans"] > 0, f"sign-ups: {d['signups_24h']} in 24 h; accounts without a users row: {d['orphans']} ({d['orphans_24h']} new in 24 h); "
         f"unconfirmed phone addresses: {d['unconfirmed_phone']}")
    if d["unconfirmed_phone"]:
        line(True, "unconfirmed derived (phone) addresses can never sign in: the confirm trigger was missing when they signed up")
    errs = d["errors"]
    line(bool(errs), f"portal_errors in 24 h: {sum(e['n'] for e in errs)} in {len(errs)} groups")
    for e in errs[:8]:
        out.append(f"     {e['n']:>4}x {e['source']}/{e['page'][:28]}: {e['msg']}")
    line(d["mail_errors"] > 0, f"mail / password-otp errors in 24 h: {d['mail_errors']}")
    line(d["stuck"] > 0, f"reports pending (not reviewed) > {DAYS} days: {d['stuck']}" + (f" (oldest {d['stuck_oldest_days']} days)" if d["stuck"] else ""))
    ev = d["events"]
    line(bool(ev), "smart_events in 24 h: " + (", ".join(f"{k}={v}" for k, v in ev.items()) or "no notice_error / command_auto_skipped / engine_error"))
    failed, late = [], []
    for c in d["cron"]:
        if not c["active"]:
            late.append(f"{c['jobname']} (inactive)"); continue
        if c["status"] == "failed":
            failed.append(f"{c['jobname']}: {c['msg']}")
        if c["start_time"]:
            age = (now - datetime.fromisoformat(c["start_time"].replace(" ", "T").replace("+00", "+00:00") if "+" in c["start_time"] else c["start_time"] + "+00:00")).total_seconds() / 60
            if age > 3 * every_minutes(c["schedule"]) + 15:
                late.append(f"{c['jobname']} last ran {age / 60:.1f} h ago")
        else:
            late.append(f"{c['jobname']} never ran")
    line(bool(failed or late), f"cron: {len(d['cron'])} jobs, {len(failed)} last run failed, {len(late)} late/never/inactive")
    for x in (failed + late)[:6]:
        out.append("     " + x[:110])
    try:
        r = subprocess.run(["gh", "run", "list", "--workflow", "backup.yml", "--limit", "1", "--json", "conclusion,createdAt,status"],
                           capture_output=True, text=True, cwd=ROOT, timeout=20)
        b = json.loads(r.stdout)[0]
        age = (now - datetime.fromisoformat(b["createdAt"].replace("Z", "+00:00"))).total_seconds() / 3600
        line(b["conclusion"] != "success" or age > 36, f"backup: last run {b['createdAt'][:16]}Z ({age:.0f} h ago) {b['status']}/{b['conclusion']}")
    except Exception as e:  # no gh / not logged in: say so, do not fail the watch
        out.append(f"?? backup: could not ask gh ({str(e)[:60]})")
    print(f"WATCH {now:%Y-%m-%d %H:%M} UTC (read-only)")
    print("\n".join(out))
    print(f"RESULT: {'all quiet' if not bad else f'{bad} to look at (!!)'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
