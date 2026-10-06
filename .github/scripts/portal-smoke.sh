#!/usr/bin/env bash
# Starts the portal with PHP's own server and checks it answers the way
# the live one must (CI, industry pass 7). No database is needed: every
# check here is about pages that work signed out.
set -u
php -S 127.0.0.1:8000 -t . > /tmp/php.log 2>&1 &
sleep 2
B=http://127.0.0.1:8000/admin
fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi
}

check "login page" "$(curl -s -o /dev/null -w '%{http_code}' "$B/login.php")" 200
check "dashboard needs sign-in" "$(curl -s -o /dev/null -w '%{http_code}' "$B/dashboard.php")" 302
check "ping" "$(curl -s "$B/ping.php")" ok
check "error page" "$(curl -s -o /dev/null -w '%{http_code}' "$B/error.php")" 404

curl -si "$B/login.php" > /tmp/login.txt
if grep -qi "^content-security-policy:.*'nonce-" /tmp/login.txt; then echo "ok   CSP with nonce"; else echo "FAIL no nonce CSP"; fail=1; fi
nonce=$(grep -io "'nonce-[^']*'" /tmp/login.txt | head -1 | sed "s/'nonce-//; s/'//")
bad=$(grep -o '<script[^>]*>' /tmp/login.txt | grep -vc "nonce=\"$nonce\"" || true)
check "every script carries the nonce" "$bad" 0
inline=$(git ls-files 'admin/*.php' | xargs grep -lE '\son(click|change|submit|input|load|error)="' || true)
check "no inline event handlers" "$inline" ""

[ $fail -eq 0 ] || { echo "--- php server log"; cat /tmp/php.log; }
exit $fail
