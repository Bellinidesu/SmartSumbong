#!/usr/bin/env bash
# Applies every migration to a throwaway local PostgreSQL 16 (PostGIS and
# pg_cron installed) and runs the rolled-back checks in supabase/tests.
# Nothing touches the live project.
#
#   apt-get install postgresql-16 postgresql-16-postgis-3 postgresql-16-cron
#   bash supabase/tests/local/run-local.sh
#
# Prints each check file's ok count and any FAIL/BAD line; exits non-zero
# when a migration fails to apply or a check fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
bin=/usr/lib/postgresql/16/bin
dir=${PGSCRATCH:-/var/tmp/smartsumbong-pg}
port=${PGPORT_LOCAL:-55433}
as_pg() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }

as_pg "$bin/pg_ctl -D $dir/data stop -m immediate" >/dev/null 2>&1
rm -rf "$dir"; mkdir -p "$dir"; [ "$(id -u)" = 0 ] && chown postgres "$dir"
as_pg "$bin/initdb -D $dir/data -A trust -U postgres" >/dev/null || exit 1
cat >> "$dir/data/postgresql.conf" <<CONF
port = $port
unix_socket_directories = '$dir'
shared_preload_libraries = 'pg_cron'
cron.database_name = 'postgres'
listen_addresses = ''
CONF
as_pg "$bin/pg_ctl -D $dir/data -l $dir/log -w start" >/dev/null || { cat "$dir/log"; exit 1; }

psql=(psql -h "$dir" -p "$port" -U postgres -d postgres -X -q -v ON_ERROR_STOP=1)
"${psql[@]}" -c "alter database postgres set search_path = \"\$user\", public, extensions" || exit 1
"${psql[@]}" -f "$here/supabase_stub.sql" >/dev/null || exit 1

fail=0
for f in "$root"/supabase/migrations/*.sql; do
  out=$("${psql[@]}" -f "$f" 2>&1) || { echo "MIGRATION FAILED: $(basename "$f")"; echo "$out" | grep -E 'ERROR|LINE' | head -5; fail=1; break; }
done
[ $fail = 0 ] && echo "migrations: $(ls "$root"/supabase/migrations/*.sql | wc -l) applied"
[ $fail = 0 ] && "${psql[@]}" -f "$root/supabase/seed.sql" >/dev/null 2>&1 || true

if [ $fail = 0 ]; then
  for f in "$root"/supabase/tests/0*.sql "$root"/supabase/tests/perf/*.sql; do
    out=$("${psql[@]}" -f "$f" 2>&1 || true)
    okc=$(printf '%s\n' "$out" | grep -cE '^ok' || true)
    bad=$(printf '%s\n' "$out" | grep -E '^(FAIL|BAD)' || true)
    echo "$(basename "$f"): $okc ok"
    if [ -n "$bad" ] || [ "$okc" -eq 0 ]; then printf '%s\n' "${bad:-$(printf '%s\n' "$out" | tail -5)}"; fail=1; fi
  done
fi

[ "${KEEP_DB:-}" ] && echo "left running: psql -h $dir -p $port -U postgres" || as_pg "$bin/pg_ctl -D $dir/data stop -m fast" >/dev/null
exit $fail
