#!/usr/bin/env bash
# Portal performance budget (CI, portal job). Fails when a change makes the
# portal heavier than these limits, sizes as a browser receives them
# (text gzipped, as Apache's mod_deflate serves it; images as they are).
# Raising a limit is allowed, but on purpose, in the same pull request.
#
#   sign-in page, everything it loads      320 KB
#   each portal script (assets/js)           8 KB
#   each stylesheet (assets/css)            20 KB
#   each .webp photo (assets/img)          160 KB
#
# Big third-party libraries (MapLibre, supabase-js) load only on the pages
# that need them and are checked by version, not here.
set -u
cd "$(dirname "$0")/../.."
fail=0
size() { case "$1" in *.css|*.js|*.svg|*.html|*.json) gzip -9 -c "$1" | wc -c ;; *) wc -c < "$1" ;; esac; }
over() { echo "FAIL $1: $2 bytes, budget $3"; fail=1; }

for f in admin/assets/js/*.js;   do s=$(size "$f"); [ "$s" -le 8192 ]   || over "$f" "$s" 8192;   done
for f in admin/assets/css/*.css; do s=$(size "$f"); [ "$s" -le 20480 ]  || over "$f" "$s" 20480;  done
for f in admin/assets/img/*.webp; do s=$(size "$f"); [ "$s" -le 163840 ] || over "$f" "$s" 163840; done

# The sign-in page as served, plus every local file it references.
php -S 127.0.0.1:8095 -t . > /tmp/perf-php.log 2>&1 &
pid=$!
sleep 2
curl -s http://127.0.0.1:8095/admin/login.php > /tmp/login.html
kill $pid
total=$(size /tmp/login.html)
for a in $(grep -oE '(src|href)="assets/[^"]+"' /tmp/login.html | sed -E 's/^(src|href)="//; s/"$//; s/\?.*//' | sort -u); do
  total=$((total + $(size "admin/$a")))
done
# The font files the sign-in page renders with (a browser downloads only
# the weights a page uses, not every one fonts.css declares).
for w in regular semibold bold; do
  total=$((total + $(size "admin/assets/vendor/fonts/urbanist-$w.woff2")))
done
if [ "$total" -le 327680 ]; then echo "ok   sign-in page: $total bytes of 327680"; else over "sign-in page" "$total" 327680; fi
[ $fail = 0 ] && echo "ok   every script, stylesheet and photo within budget"
exit $fail
