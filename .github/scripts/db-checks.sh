#!/usr/bin/env bash
# Applies the migrations to the STAGING Supabase project and runs the
# rolled-back system checks in supabase/tests there (CI, staging job).
# Each script ends by raising, so nothing is saved; its message is the log.
# Any FAIL or BAD line fails the build. Refuses to run against production:
# everyday checks run locally (supabase/tests/local/run-local.sh).
set -u
PRODUCTION=xmkpokcnjzgxgwysperh
ref=${STAGING_PROJECT_REF:-}
if [ -z "$ref" ] || [ "$ref" = "$PRODUCTION" ]; then
  echo "STAGING_PROJECT_REF must name a staging project, never production ($PRODUCTION)."; exit 1
fi
supabase link --project-ref "$ref" --password "$SUPABASE_DB_PASSWORD" > /dev/null || exit 1
supabase db push --linked --include-all --yes || exit 1
fail=0
for f in supabase/tests/[0-9][0-9]_*.sql; do
  out=$(supabase db query --linked -f "$f" 2>&1 || true)
  log=$(printf '%s' "$out" | sed 's/\\n/\n/g')
  okc=$(printf '%s\n' "$log" | grep -cE '^ok' || true)
  bad=$(printf '%s\n' "$log" | grep -E '^(FAIL|BAD)' || true)
  echo "$f: $okc ok"
  if [ -n "$bad" ] || [ "$okc" -eq 0 ]; then
    printf '%s\n' "$bad"
    fail=1
  fi
done
exit $fail
