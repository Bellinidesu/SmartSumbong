#!/usr/bin/env bash
# Rebuilds supabase/baseline/baseline.sql: the whole schema that
# supabase/migrations produces, as one file, then proves it by loading it
# into a clean database and running every check in supabase/tests.
#
#   bash supabase/baseline/build.sh           rebuild, then prove
#   bash supabase/baseline/build.sh --check   only prove the committed file (CI)
#
# Needs what supabase/tests/local/run-local.sh needs (PostgreSQL 16,
# PostGIS, pg_cron). Run it after adding a migration, and commit both.
set -eu
check_only=""; [ "${1:-}" = "--check" ] && check_only=1
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
bin=/usr/lib/postgresql/${PGVER:-16}/bin
dir=${PGSCRATCH:-/var/tmp/smartsumbong-base}
port=55435
as_pg() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
psql=(psql -h "$dir" -p "$port" -U postgres -d postgres -X -q -v ON_ERROR_STOP=1)

fresh() {
  as_pg "$bin/pg_ctl -D $dir/data stop -m immediate" >/dev/null 2>&1 || true
  rm -rf "$dir"; mkdir -p "$dir"; [ "$(id -u)" = 0 ] && chown postgres "$dir"
  as_pg "$bin/initdb -D $dir/data -A trust -U postgres" >/dev/null
  printf "port = %s\nunix_socket_directories = '%s'\nshared_preload_libraries = 'pg_cron'\ncron.database_name = 'postgres'\nlisten_addresses = ''\n" \
    "$port" "$dir" >> "$dir/data/postgresql.conf"
  as_pg "$bin/pg_ctl -D $dir/data -l $dir/log -w start" >/dev/null
  "${psql[@]}" -c "alter database postgres set search_path = \"\$user\", public, extensions"
  "${psql[@]}" -f "$root/supabase/tests/local/supabase_stub.sql" >/dev/null
}


# A fingerprint of everything that matters: functions (body, settings,
# grants), tables and columns, grants, policies, indexes, constraints,
# triggers, realtime and scheduled jobs.
fingerprint() {
  psql -h "$dir" -p "$port" -U postgres -d postgres -X -At <<'SQL'
select 'fn ' || p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) || ' ' || coalesce(p.proacl::text, '')
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')
   and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
select 'col ' || c.oid::regclass || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull || ' ' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
  from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p')
   and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e');
-- MAINTAIN ('m') exists from PostgreSQL 17 only: a baseline dumped on 16
-- cannot express it on a partial grant (look_shares), so it is left out.
select 'acl ' || c.oid::regclass || ' ' || regexp_replace(coalesce(c.relacl::text, ''), '(=[arwdDxt*]*)m', '\1', 'g') || ' rls=' || c.relrowsecurity
  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','S','p')
   and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e');
select 'pol ' || schemaname || '.' || tablename || ' ' || policyname || ' ' || cmd || ' ' || roles::text || ' ' || coalesce(qual, '') || ' ' || coalesce(with_check, '') from pg_policies where schemaname = 'public';
select 'idx ' || indexdef from pg_indexes where schemaname = 'public' and tablename <> 'spatial_ref_sys';
select 'con ' || conrelid::regclass || ' ' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint where connamespace = 'public'::regnamespace and conrelid <> 0;
select 'trg ' || tgrelid::regclass || ' ' || tgname || ' ' || pg_get_triggerdef(oid) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'cron.%';
select 'pub ' || schemaname || '.' || tablename from pg_publication_tables where pubname = 'supabase_realtime';
select 'cron ' || jobname || ' ' || schedule || ' ' || command from cron.job;
select 'type ' || t.oid::regtype || ' ' || coalesce((select string_agg(enumlabel, ',' order by enumsortorder) from pg_enum where enumtypid = t.oid), '')
  from pg_type t where t.typnamespace = 'public'::regnamespace and t.typtype = 'e';
select 'row ' || c.relname || ' ' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text
  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'spatial_ref_sys';
SQL
}

# 1. Every migration, in order.
fresh
last=""
for f in "$root"/supabase/migrations/*.sql; do "${psql[@]}" -f "$f" >/dev/null 2>&1 || { echo "migration failed: $f"; exit 1; }; last=$(basename "$f" .sql); done

fingerprint | sort > "$dir.migrated.txt"

# 2. The result as one file.
out="$here/baseline.sql"
if [ -z "$check_only" ]; then
q() { psql -h "$dir" -p "$port" -U postgres -d postgres -X -At -c "$1"; }
{
  cat <<HEAD
-- SmartSumbong: the whole database schema as one file, equal to applying
-- supabase/migrations 0001 through ${last%%_*} in order (${last}).
-- GENERATED by supabase/baseline/build.sh, which also proves it: loaded
-- into a clean database, every check in supabase/tests passes. Do not
-- edit by hand; add a migration and rebuild.
--
-- For a NEW Supabase project only (enable postgis and pg_cron first):
--   psql "\$DATABASE_URL" -f supabase/baseline/baseline.sql
--   psql "\$DATABASE_URL" -f supabase/seed.sql
-- then mark the migrations it covers as applied, so db push skips them:
--   supabase migration repair --status applied $(ls "$root"/supabase/migrations/*.sql | xargs -n1 basename | cut -d_ -f1 | tr '\n' ' ')
-- The live project keeps its migration history; never run this there.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists postgis;
create extension if not exists pg_cron;

-- Supabase grants every new table, sequence and function in public to the
-- API roles by default. The grants below are the exact ones the
-- migrations ended with (including every revoke), so that default is off
-- while this file loads and back on at the end.
alter default privileges in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges in schema public revoke all on functions from anon, authenticated, service_role;
HEAD
  "$bin/pg_dump" -h "$dir" -p "$port" -U postgres -d postgres --schema=public --no-owner \
      --exclude-table-data=public.spatial_ref_sys \
    | sed -e 's/^CREATE SCHEMA public;$/CREATE SCHEMA IF NOT EXISTS public;/' \
          -e '/^COMMENT ON SCHEMA public IS/d' \
          -e '/^-- Dumped \(from\|by\)/d' \
          -e '/^\\\(un\)\?restrict /d'
  echo
  echo "-- Triggers on auth.users (signup and the synthetic sign-in address)."
  q "select pg_get_triggerdef(t.oid) || ';' from pg_trigger t where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal order by t.tgname" \
    | sed -e 's/EXECUTE FUNCTION \([a-z_]*\)(/EXECUTE FUNCTION public.\1(/'
  echo
  echo "-- Realtime."
  echo "do \$\$ begin if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if; end \$\$;"
  q "select 'alter publication supabase_realtime add table ' || schemaname || '.' || tablename || ';' from pg_publication_tables where pubname = 'supabase_realtime' order by 1"
  echo
  echo "-- Scheduled jobs."
  q "select format('select cron.schedule(%L, %L, %L);', jobname, schedule, command) from cron.job order by jobname"
  echo
  echo "-- Supabase's defaults back on for whatever comes next."
  echo "alter default privileges in schema public grant all on tables to anon, authenticated, service_role;"
  echo "alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;"
  echo "alter default privileges in schema public grant all on functions to anon, authenticated, service_role;"
} > "$out"
fi

# 3. Proof: a clean database from the baseline alone passes every check.
fresh
"${psql[@]}" -f "$out" >/dev/null 2>&1
fail=0
fingerprint | sort > "$dir.baseline.txt"
if diff -q "$dir.migrated.txt" "$dir.baseline.txt" >/dev/null; then
  echo "schema fingerprint: identical ($(wc -l < "$dir.baseline.txt") objects)"
else
  echo "schema fingerprint DIFFERS from the migrations (rebuild: bash supabase/baseline/build.sh):"; diff "$dir.migrated.txt" "$dir.baseline.txt" | head -20; fail=1
fi
for f in "$root"/supabase/tests/0*.sql; do
  log=$("${psql[@]}" -f "$f" 2>&1 || true)
  okc=$(printf '%s\n' "$log" | grep -cE '^ok' || true)
  bad=$(printf '%s\n' "$log" | grep -E '^(FAIL|BAD)' || true)
  echo "$(basename "$f") on the baseline: $okc ok"
  if [ -n "$bad" ] || [ "$okc" -eq 0 ]; then printf '%s\n' "${bad:-$(printf '%s\n' "$log" | tail -5)}"; fail=1; fi
done
as_pg "$bin/pg_ctl -D $dir/data stop -m fast" >/dev/null
echo "baseline: $(wc -l < "$out") lines, $last"
exit $fail
