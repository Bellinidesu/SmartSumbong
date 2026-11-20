#!/usr/bin/env bash
# Builds a SMALL throwaway database `sweep_probe` (schema + reference data of the 250x database, none of its cases or people) for the dynamic probers.
# usage: bash tools/sweep/probe_db.sh   (needs local_db.sh up)
set -u
PGBIN=${PGBIN:-/c/Users/acele/pgtmp/pg/pgsql/bin}; PORT=${SWEEP_PORT:-55441}; EXE=""; [ -f "$PGBIN/psql.exe" ] && EXE=.exe
P=("$PGBIN/psql$EXE" -h 127.0.0.1 -p "$PORT" -U postgres -X -q)
"${P[@]}" -d postgres -c "drop database if exists sweep_probe" -c "create database sweep_probe" || exit 1
ex=""; for t in reports status_logs notifications report_triage dispatches report_concerns users report_media report_messages smart_events dispatch_updates case_handler_log smart_patterns_seen chat_state attendance account_audit portal_uptime error_log; do ex="$ex --exclude-table-data=public.$t"; done
"$PGBIN/pg_dump$EXE" -h 127.0.0.1 -p "$PORT" -U postgres -d postgres --no-owner $ex --exclude-table-data=auth.users --exclude-table-data=auth.identities | sed 's/^CREATE EXTENSION IF NOT EXISTS pg_cron.*//' | "${P[@]}" -d sweep_probe -v ON_ERROR_STOP=0 >/dev/null 2>/tmp/probe_db.err
"${P[@]}" -d sweep_probe -c 'alter database sweep_probe set search_path = "$user", public, extensions'
"${P[@]}" -d sweep_probe -Atc "select 'sweep_probe: '||(select count(*) from pg_proc where pronamespace='public'::regnamespace)||' functions, '||(select count(*) from public.reports)||' reports, errors in dump: '" ; grep -c ERROR /tmp/probe_db.err
