#!/usr/bin/env bash
# Starts the portal for the browser tests: a throwaway copy of admin/ with a fake .env, signed in as a demo
# administrator (router.php), talking to a fake Supabase on 127.0.0.1:54399 (fake/). Never the live project:
# the copy has its own .env, so the repo's real one is not read. Stop with: kill $(cat "$SITE/pids")
set -eu
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
SITE=${SITE:-$(mktemp -d)}
rm -rf "$SITE/admin"; cp -r "$root/admin" "$SITE/admin"; cp "$here/router.php" "$SITE/"
[ -d "$here/mock" ] && cp "$here/mock/"*.php "$SITE/admin/" 2>/dev/null || true   # throwaway mockups: the test site only, never the image
printf 'FEATURE_CACHE_TTL=0
SUPABASE_URL=http://127.0.0.1:54399\nSUPABASE_PUBLISHABLE_KEY=fake\nCLOUDINARY_CLOUD_NAME=fake\nCLOUDINARY_UPLOAD_PRESET=fake\nVAPID_PUBLIC_KEY=BF6und7IVdYoCyKU-iUigL7T4GtiSorz7hwO206W7Ru6IvICvAYOYwhwyXzaZ2sbuv9uRV2pg4qmL5V_WZfEJqU\n' > "$SITE/.env"
PY=$(command -v python3 || command -v python)
(cd "$here/fake" && exec "$PY" fake_ws.py) > "$SITE/fake.log" 2>&1 & echo $! > "$SITE/pids"
(cd "$SITE" && exec php -S 127.0.0.1:8013 -t . router.php) > "$SITE/php.log" 2>&1 & echo $! >> "$SITE/pids"
for i in $(seq 1 30); do curl -fs http://127.0.0.1:8013/admin/ping.php > /dev/null && curl -s http://127.0.0.1:54399/ > /dev/null && break; sleep 1; done
echo "portal on http://127.0.0.1:8013/admin (site $SITE)"
