#!/usr/bin/env bash
# Runs the whole backend sweep: throwaway DB from the migrations -> page/press map -> page request capture -> load cost + SMART at 1x and 250x
# -> detectors -> standards -> ledger rows -> fix generators. Read-only against live (only the live row counts and the portal's headers).
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
  step "load cost and SMART at 1x and 250x"; python loadcost.py --scales 1,250
fi
step "SMART engine"; python smart.py
step "detectors"; python detectors.py
step "standards"; python standards.py
step "ledger"; python ledger.py
[ -d fix ] && { step "fix generators (drafts only, never applied)"; for g in fix/gen_*.py; do python "$g" --check || true; done; }
