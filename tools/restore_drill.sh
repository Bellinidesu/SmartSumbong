#!/usr/bin/env bash
# The nightly restore drill (7 Nov 2026, the gap search): a backup nobody has restored is a hope, not a backup.
#
# Run by .github/workflows/backup.yml right after the dump: decrypts the archive just made (proving the passphrase round trip),
# loads roles, schema and data into a throwaway PostgreSQL 17 with PostGIS and pg_cron (the same stub of Supabase's roles and
# auth schema the migration checks use), then compares every public table's row count with the rows the dump holds for it.
# Any table that does not come back whole fails the night (and the backup check emails the team).
#
# The repository is public: this prints how many tables matched, or the names of the tables that did not; never any data.
#
#   bash tools/restore_drill.sh out/smartsumbong-<date>.tgz.gpg     (BACKUP_PASSPHRASE in the environment)
set -euo pipefail
archive=$1
root=$(cd "$(dirname "$0")/.." && pwd)
bin=/usr/lib/postgresql/${PGVER:-17}/bin
work=$(mktemp -d)
trap 'pg_ctl_stop; rm -rf "$work"' EXIT
pg_ctl_stop() { "$bin/pg_ctl" -D "$work/data" stop -m immediate >/dev/null 2>&1 || true; }

# 1. decrypt and unpack (inside the runner only; the folder is removed at the end)
gpg --batch --quiet --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" --decrypt "$archive" | tar xz -C "$work"
for f in roles.sql schema.sql data.sql; do [ -s "$work/$f" ] || { echo "::error::the backup has no $f"; exit 1; }; done

# 2. a throwaway database
"$bin/initdb" -D "$work/data" -A trust -U postgres >/dev/null
printf "port = 55441\nunix_socket_directories = '%s'\nshared_preload_libraries = 'pg_cron'\ncron.database_name = 'postgres'\nlisten_addresses = ''\n" "$work" >> "$work/data/postgresql.conf"
"$bin/pg_ctl" -D "$work/data" -l "$work/log" -w start >/dev/null
psql=(psql -h "$work" -p 55441 -U postgres -d postgres -X -q)
"${psql[@]}" -c "alter database postgres set search_path = \"\$user\", public, extensions" >/dev/null
"${psql[@]}" -v ON_ERROR_STOP=1 -f "$root/supabase/tests/local/supabase_stub.sql" >/dev/null

# 3. restore as the runbook says (docs/OPERATIONS.md): roles, schema, data. Statements about Supabase's own machinery (its
#    admin roles, its managed schemas) have nothing to land on in a plain PostgreSQL; they are counted, and the data decides.
load() { "${psql[@]}" -v ON_ERROR_STOP=0 -f "$work/$1" 2>&1 | grep -c '^psql:.*ERROR' || true; }
e_roles=$(load roles.sql); e_schema=$(load schema.sql); e_data=$(load data.sql)
echo "restore: roles.sql $e_roles, schema.sql $e_schema, data.sql $e_data statements did not apply (Supabase's own machinery)"

# 4. every public table holds as many rows as the dump has for it
python3 - "$work/data.sql" > "$work/expected.tsv" <<'PY'
import re, sys
want, cur, n = {}, None, 0
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if cur is None:
        m = re.match(r'COPY "?public"?\."?([A-Za-z0-9_]+)"? ', line)
        if m: cur, n = m.group(1), 0
    elif line.rstrip('\n') == '\\.':
        want[cur] = want.get(cur, 0) + n; cur = None
    else:
        n += 1
for t, c in sorted(want.items()): print(f"{t}\t{c}")
PY
tables=0; bad=()
while IFS=$'\t' read -r t want; do
  tables=$((tables + 1))
  got=$("${psql[@]}" -At -c "select count(*) from public.\"$t\"" 2>/dev/null || echo missing)
  [ "$got" = "$want" ] || bad+=("$t")
done < "$work/expected.tsv"
[ "$tables" -gt 0 ] || { echo "::error::the dump holds no public tables"; exit 1; }
if [ ${#bad[@]} -gt 0 ]; then
  echo "::error::restore drill: ${#bad[@]} of $tables tables did not come back whole: ${bad[*]}"
  exit 1
fi
echo "restore drill: all $tables public tables came back with every row"
