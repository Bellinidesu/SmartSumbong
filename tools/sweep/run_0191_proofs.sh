#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
export SWEEP_PGDIR=/c/Users/acele/pgtmp/crcdata SWEEP_PORT=55444
D=../../supabase/drafts/0191_case_rule_consistency.sql
echo "== pgTAP before/after"; python pgtap_compare.py $D supabase/drafts/tests/71_case_rule_consistency.test.sql 2>&1 | tail -12
echo "== probes before/after"; bash probe_db.sh 2>&1 | tail -1; python probe_compare_0191.py $D 2>&1 | grep -v Warn | tail -16
echo "== timing"; python time_0191.py 2>&1 | tail -8
