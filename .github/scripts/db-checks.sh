#!/usr/bin/env bash
# Runs the rolled-back system checks in supabase/tests against the linked
# project (CI, industry pass 7). Each script ends by raising, so nothing is
# saved; its message is the log. Any FAIL or BAD line fails the build.
set -u
supabase link --project-ref xmkpokcnjzgxgwysperh --password "$SUPABASE_DB_PASSWORD" > /dev/null
fail=0
for f in supabase/tests/0*.sql; do
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
