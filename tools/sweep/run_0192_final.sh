#!/usr/bin/env bash
cd "$(dirname "$0")"
export SWEEP_PGDIR=/c/Users/acele/pgtmp/mechdata SWEEP_PORT=55445
echo "== pgTAP before/after (final draft)"; python pgtap_compare.py ../../supabase/drafts/0192_mechanical_fixes.sql supabase/drafts/tests/76_mechanical_fixes.test.sql 2>&1 | tail -8
