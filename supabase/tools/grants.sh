#!/usr/bin/env bash
# The grants on file (11 Nov 2026, the backend sweep): supabase/grants.txt says, for every function, table, view and sequence in
# public, what a signed-out caller and a signed-in one may do. It is checked twice:
#   - CI: the migrations must produce exactly this file, so a migration that forgets a revoke fails the build;
#   - every night: the live database must match it, so a restore, a dashboard click or a new project that leaves grants wider
#     (or narrower) than the migrations intend is caught the same night.
# Why it exists: a dump restored into a new Supabase project keeps every right the new project grants by default (anon and
# authenticated get everything on each object as it is made, and a dump carries no revoke for that). The move to Singapore left
# signed-out callers able to run 383 functions instead of 62 until it was found by hand.
#
#   bash supabase/tools/grants.sh print <psql connection options>     the lines for that database, sorted
#   bash supabase/tools/grants.sh check <psql connection options>     compare them with supabase/grants.txt (exit 1 when they differ)
#   bash supabase/tools/grants.sh write <psql connection options>     rewrite supabase/grants.txt from that database
#   bash supabase/tools/grants.sh apply <psql connection options>     make that database's grants what the file says (one
#                                                                     transaction: revoke, then grant what is listed); for a
#                                                                     restore into a new project, then run check
#
# Connection options are psql's own (-h, -p, -U, -d); a password comes from PGPASSWORD. Object names and rights only: no data.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
file="$here/../grants.txt"
mode=${1:?print, check, write or apply}; shift
lines() { PGOPTIONS='-c search_path=public,extensions' psql "$@" -X -At -v ON_ERROR_STOP=1 -f "$here/grants.sql" | LC_ALL=C sort; }
case "$mode" in
  print) lines "$@" ;;
  write) lines "$@" > "$file"; echo "wrote $(wc -l < "$file") lines to supabase/grants.txt" ;;
  check)
    now=$(mktemp); lines "$@" > "$now"
    if diff <(LC_ALL=C sort "$file") "$now" > "$now.diff"; then
      echo "grants: all $(wc -l < "$now") objects match supabase/grants.txt"
    else
      echo "::error::grants differ from supabase/grants.txt ('<' is the file, '>' is this database):"
      head -60 "$now.diff"
      echo "($(grep -c '^[<>]' "$now.diff") lines differ)"
      exit 1
    fi ;;
  apply)
    sql=$(mktemp)
    {
      echo "begin;"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        if [[ $line =~ ^fn\ (.*)\ anon=([^ ]+)\ authenticated=([^ ]+)$ ]]; then
          obj="function public.${BASH_REMATCH[1]}"; a=${BASH_REMATCH[2]}; u=${BASH_REMATCH[3]}
          [ "$a" = call ] && a=execute; [ "$u" = call ] && u=execute
        elif [[ $line =~ ^(table|view)\ ([^ ]+)\ anon=([^ ]+)\ authenticated=([^ ]+)\ rls=(on|off)$ ]]; then
          obj="table public.\"${BASH_REMATCH[2]}\""; a=${BASH_REMATCH[3]}; u=${BASH_REMATCH[4]}
        elif [[ $line =~ ^seq\ ([^ ]+)\ anon=([^ ]+)\ authenticated=([^ ]+)$ ]]; then
          obj="sequence public.\"${BASH_REMATCH[1]}\""; a=${BASH_REMATCH[2]}; u=${BASH_REMATCH[3]}
        else
          echo "::error::a line of supabase/grants.txt is not understood: $line" >&2; exit 1
        fi
        echo "revoke all on $obj from public, anon, authenticated;"
        [ "$a" = "-" ] || echo "grant $a on $obj to anon;"
        [ "$u" = "-" ] || echo "grant $u on $obj to authenticated;"
      done < "$file"
      echo "commit;"
    } > "$sql"
    psql "$@" -X -q -v ON_ERROR_STOP=1 -f "$sql" > /dev/null
    echo "applied the grants of $(grep -c . "$file") objects"
    rm -f "$sql" ;;
  *) echo "print, check, write or apply"; exit 2 ;;
esac
