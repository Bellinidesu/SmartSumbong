"""Shared by the fix generators. A generator reads the detector/prober output (tools/sweep/out/*.json) and the CURRENT function definitions from the
throwaway database, and emits a DRAFT into supabase/drafts/ (NOT supabase/migrations/: a merge must not deploy it): NNNN_slug.sql with the header
'DRAFT: not applied until Ace says apply NNNN' and a plain-language UNDO note, plus tests/NNNN_slug.test.sql in the repo's rolled-back style. prove() builds a
scratch database from sweep_probe (schema as of the migrations), runs the test BEFORE the draft (it must report a FAIL), applies the draft, runs it AFTER (only ok),
and prints a 5-line summary. Nothing here touches live or supabase/migrations."""
import os, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import *

DRAFTS = ROOT / "supabase" / "drafts"
(DRAFTS / "tests").mkdir(parents=True, exist_ok=True)
SCRATCH = "sweep_fix"
TEMPLATE = os.environ.get("FIX_TEMPLATE", "sweep_probe")   # a database already at the latest migration (e.g. postgres of a full local build) skips the catch-up
HEADER = """-- DRAFT: not applied until Ace says apply {num}
-- {num}_{slug}: {title}
--
-- {why}
--
-- UNDO (plain language): {undo}
-- Proof: supabase/drafts/tests/{num}_{slug}.test.sql fails before this file and passes after it (run by tools/sweep/fix/{gen}).
-- To use: move this file to supabase/migrations/ and the test to supabase/tests/ (number the test), rebuild the baseline and grants.txt.
"""
PREAMBLE = """  v_res uuid := gen_random_uuid(); v_sup uuid := gen_random_uuid(); v_kpo uuid := gen_random_uuid(); v_kenv uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_case uuid; n integer;"""
SETUP = """  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', x.id, 'authenticated', 'authenticated', public.auth_email_for(x.mob),
         jsonb_build_object('full_name', x.nm, 'mobile_number', x.mob, 'role', 'resident', 'id_type', 'barangay_id',
                            'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                            'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now()
    from (values (v_res, '+639999999901', 'Draft, Resident'), (v_sup, '+639999999902', 'Draft, Super'), (v_kpo, '+639999999903', 'Draft, Kagawad Peace'),
                 (v_kenv, '+639999999904', 'Draft, Kagawad Env'), (v_stf, '+639999999905', 'Draft, Staff Peace')) as x(id, mob, nm);
  update public.users set verification_status = 'verified', verified_at = now() where id in (v_res, v_sup, v_kpo, v_kenv, v_stf);
  update public.users set role = 'admin', admin_tier = 'super' where id = v_sup;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'peace_order' where id = v_kpo;
  update public.users set role = 'admin', admin_tier = 'committee', committee = 'environment' where id = v_kenv;
  update public.users set role = 'admin', admin_tier = 'moderator', committee = 'peace_order' where id = v_stf;
  update public.users set role = 'admin', admin_tier = 'super', committee = null where role = 'admin' and id not in (v_sup, v_kpo, v_kenv, v_stf) and admin_tier in ('committee', 'moderator');
  insert into public.reports (resident_id, category, subject, description, latitude, longitude)
  values (v_res, 'peace_order_nuisance', 'Maingay', 'Videoke hanggang hatinggabi sa kanto.', 14.51944, 121.01219) returning id into v_case;
  set local session_replication_role = replica;
  update public.reports set status = 'resolved', resolved_at = now(), committee = 'peace_order', handler_id = v_kpo, handled_since = now() where id = v_case;
  set local session_replication_role = origin;"""


def test_file(title, checks):
    """checks: list of (label, plpgsql statements that raise on failure). Returns the SQL text of a rolled-back test in the repo's style."""
    q = lambda t: t.replace("'", "''")
    body = "\n".join(f"  begin\n{code}\n    v_log := v_log || E'\\n' || 'ok  {q(label)}';\n  exception when others then reset role; v_log := v_log || E'\\n' || 'FAIL {q(label)}: ' || sqlerrm; end;\n" for label, code in checks)
    return f"-- {title}. Rolled back (ends by raising SWEEP-ROLLBACK), like every script in supabase/tests.\ndo $sweep$\ndeclare\n  v_log text := 'setup ok';\n{PREAMBLE}\nbegin\n{SETUP}\n\n{body}\n  raise exception E'SWEEP-ROLLBACK\\n%', v_log;\nend $sweep$;\n"


def as_role(uid_var, sql):
    return f"    execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', {uid_var}::text, true);\n{sql}\n    reset role;"


def wt(path, text):
    """write with LF endings on every platform (a CRLF inside a function body would end up in the database)"""
    Path(path).write_bytes(text.replace(chr(13), "").encode("utf-8"))


def next_number():
    used = [int(p.name[:4]) for p in list(DRAFTS.glob("[0-9][0-9][0-9][0-9]_*.sql"))] + [int(f.name[:4]) for f in migrations()]
    return max(used) + 1


def fn_def(sig):
    """current definition of a function from the local (migrations-built) database"""
    return psql(f"select pg_get_functiondef('public.{sig}'::regprocedure)", raw=True).replace(chr(13), "").strip().rstrip(";") + ";"


def scratch():
    P = [f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-X", "-q", "-d", "postgres", "-c"]
    subprocess.run(P + [f"drop database if exists {SCRATCH}"], capture_output=True)
    r = subprocess.run(P + [f"create database {SCRATCH} template {TEMPLATE}"], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[:200])


def run_sql(path_or_text, text=False):
    args = [f"{PGBIN}/psql{EXE}", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres", "-d", SCRATCH, "-X", "-q"]
    r = subprocess.run(args + (["-c", path_or_text] if text else ["-f", str(path_or_text)]), capture_output=True, text=True, encoding="utf-8")
    return r.stdout + r.stderr


def results(out):
    ok = [l for l in out.splitlines() if re.match(r"^ok ", l)]
    fail = [l for l in out.splitlines() if re.match(r"^(FAIL|BAD)", l)]
    return ok, fail


def emit_and_prove(slug, title, why, undo, up_sql, undo_sql, test_sql, gen, before_prep=""):
    num = f"{next_number():04d}" if not list(DRAFTS.glob(f"*_{slug}.sql")) else list(DRAFTS.glob(f"*_{slug}.sql"))[0].name[:4]
    head = HEADER.format(num=num, slug=slug, title=title, why=why.replace("\n", "\n-- "), undo=undo, gen=gen)
    draft = DRAFTS / f"{num}_{slug}.sql"
    test = DRAFTS / "tests" / f"{num}_{slug}.test.sql"
    wt(draft, head + "\n" + up_sql.strip() + "\n\n-- UNDO SQL (not run; for the person applying this):\n" + "\n".join("-- " + l for l in undo_sql.strip().splitlines()) + "\n")
    wt(test, test_sql)
    scratch()
    b_ok, b_fail = results(run_sql(test))
    out_apply = run_sql(draft)
    err = [l for l in out_apply.splitlines() if "ERROR" in l]
    a_ok, a_fail = results(run_sql(test))
    proven = bool(b_fail) and not a_fail and bool(a_ok) and not err
    print(f"DRAFT {num}_{slug}: {title}")
    print(f"  files: supabase/drafts/{num}_{slug}.sql + tests/{num}_{slug}.test.sql   (NOT applied; moves to migrations on 'apply {num}')")
    print(f"  before: {len(b_ok)} ok, {len(b_fail)} FAIL   after: {len(a_ok)} ok, {len(a_fail)} FAIL   apply errors: {len(err)}")
    print(f"  proven failing-before/passing-after: {'YES' if proven else 'NO'}")
    for l in (a_fail[:3] + err[:2] + ([] if b_fail else ["(the test did not fail before: it proves nothing yet)"])): print("   !", l[:160])
    return num, proven
