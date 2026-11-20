#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
export SWEEP_PGDIR=/c/Users/acele/pgtmp/mechdata SWEEP_PORT=55445
D=../../supabase/drafts/0192_mechanical_fixes.sql
echo "== pgTAP before/after"; python pgtap_compare.py $D supabase/drafts/tests/76_mechanical_fixes.test.sql 2>&1 | tail -10
echo "== probes before/after"; bash probe_db.sh 2>&1 | tail -1; python probe_compare_0191.py $D --exclude out/mechanical_0192.json 2>&1 | grep -v Warn | tail -16
