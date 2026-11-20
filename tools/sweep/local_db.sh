#!/usr/bin/env bash
# Throwaway local PostgreSQL for the sweep: all 0001..N migrations on a plain PG16 + PostGIS, pg_cron stubbed.
# Usage: bash tools/sweep/local_db.sh [up|down|psql ...]   env: PGBIN (dir with initdb/psql), SWEEP_PGDIR, SWEEP_PORT
# Windows: PGBIN=C:/Users/acele/pgtmp/pg/pgsql/bin ; Linux: PGBIN=/usr/lib/postgresql/16/bin (needs postgis).
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
PGBIN=${PGBIN:-/c/Users/acele/pgtmp/pg/pgsql/bin}; DIR=${SWEEP_PGDIR:-/c/Users/acele/pgtmp/sweepdata}; PORT=${SWEEP_PORT:-55441}
EXE=""; [ -f "$PGBIN/psql.exe" ] && EXE=.exe
PSQL=("$PGBIN/psql$EXE" -h 127.0.0.1 -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1)
case "${1:-up}" in
 down) "$PGBIN/pg_ctl$EXE" -D "$DIR" stop -m immediate >/dev/null 2>&1; exit 0;;
 psql) shift; exec "${PSQL[@]}" -d "${SWEEP_DB:-postgres}" "$@";;
esac
"$PGBIN/pg_ctl$EXE" -D "$DIR" stop -m immediate >/dev/null 2>&1; rm -rf "$DIR"
"$PGBIN/initdb$EXE" -D "$DIR" -A trust -U postgres -E UTF8 >/dev/null || exit 1
printf "port=%s\nlisten_addresses='127.0.0.1'\nfsync=off\nsynchronous_commit=off\nfull_page_writes=off\nshared_buffers=512MB\nmax_connections=60\nshared_preload_libraries='pg_stat_statements'\n" "$PORT" >> "$DIR/postgresql.conf"
"$PGBIN/pg_ctl$EXE" -D "$DIR" -l "$DIR/log" -w start >/dev/null || { cat "$DIR/log"; exit 1; }
"${PSQL[@]}" -d postgres -c 'alter database postgres set search_path = "$user", public, extensions' || exit 1
sed -e '/^create extension pg_cron;/d' "$root/supabase/tests/local/supabase_stub.sql" > "$DIR/stub.sql"
"${PSQL[@]}" -d postgres -f "$DIR/stub.sql" >/dev/null || exit 1
"${PSQL[@]}" -d postgres -f "$here/sql/cron_stub.sql" >/dev/null || exit 1
n=0
for f in "$root"/supabase/migrations/*.sql; do
  sed -e 's/create extension if not exists pg_cron[^;]*;//I' "$f" > "$DIR/m.sql"
  out=$("${PSQL[@]}" -d postgres -f "$DIR/m.sql" 2>&1) || { echo "MIGRATION FAILED $(basename "$f")"; echo "$out" | grep -E 'ERROR|LINE' | head -4; exit 1; }
  n=$((n+1))
done
"${PSQL[@]}" -d postgres -f "$root/supabase/seed.sql" >/dev/null 2>&1
echo "local db up: port $PORT, $n migrations"
