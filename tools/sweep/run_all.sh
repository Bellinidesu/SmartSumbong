#!/usr/bin/env bash
# Runs the whole backend sweep: throwaway DB from the migrations -> page/press map -> page request capture -> load cost + SMART at 1x and 250x
# -> detectors -> standards -> ledger rows -> fix generators. Read-only against live (only the live row counts and the portal's headers).
# The fix generators and the case-rule options experiment (they write drafts into supabase/drafts) run only with WITH_FIX=1 / WITH_EXP=1.
# About 20-30 minutes on a laptop (migrations ~3 min, 250x seed ~3 min, replays ~5 min). Needs: PostgreSQL 16 + PostGIS binaries (PGBIN),
# PostgREST (PGRST_BIN), php, python 3.9+, supabase CLI linked (for live counts; skipped if not linked).
#   bash tools/sweep/run_all.sh            everything
#   bash tools/sweep/run_all.sh quick      static only (pagemap, detectors, standards, ledger); needs the local DB from a previous run
set -u
cd "$(dirname "$0")"
mode=${1:-full}
step() { echo "== $*"; }
if [ "$mode" != "quick" ]; then
  step "local database"; bash local_db.sh up || exit 1
  python - <<'PY'
from common import live, save
try:
    save("live_counts.json", live("select relname, n_live_tup::int n, pg_total_relation_size(relid)::int sz from pg_stat_user_tables where schemaname='public' order by n_live_tup desc limit 60"))
except Exception as e:
    print("live counts skipped:", str(e)[:100])
PY
fi
step "pages and presses (static)"; python pagemap.py
if [ "$mode" != "quick" ]; then
  step "capture what each page asks the backend"; python capture_pages.py
  step "load cost and SMART at 1x and 250x"; python loadcost.py --scales "${SCALES:-1,250}"
fi
step "SMART engine"; python smart.py
step "callers (strict cross-check)"; python callgraph.py | head -4
if [ "$mode" != "quick" ]; then
  step "dynamic probers (small database: fixtures, every function as every role, failure injection)"
  bash probe_db.sh && python probe.py run && python probe.py report | grep -E "^(PROBE|\(a\)|\(b\)|\(c\))|FINDING|DOC vs" && python inject.py | tail -12
fi
step "detectors"; python detectors.py
step "standards"; python standards.py
step "author-admitted markers"; python markers.py | head -1
step "ledger"; python ledger.py
[ -d fix ] && [ "${WITH_FIX:-0}" = 1 ] && { step "fix generators (DRAFTS in supabase/drafts, never applied; each proves failing-before/passing-after on a scratch database)"; for g in fix/gen_*.py; do python "$g" || true; done; }
[ "$mode" != "quick" ] && [ "${WITH_EXP:-0}" = 1 ] && { step "options for the case rule at 1x/50x/250x"; python exp_case_rule.py | tail -22; }
