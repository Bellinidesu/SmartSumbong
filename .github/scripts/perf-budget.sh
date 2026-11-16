#!/usr/bin/env bash
# Portal performance budget (CI, portal job). Fails when a change makes the
# portal heavier than these limits, sizes as a browser receives them
# (text gzipped, as Apache's mod_deflate serves it; images as they are).
# Raising a limit is allowed, but on purpose, in the same pull request.
#
#   sign-in page, everything it loads      336 KB (was 320: the small SMART engine mark under the card)
#   each portal script (assets/js)          16 KB   (was 14, 8 before: widgets-core.js holds the Workspace widget engine and library); spatial.js 64 KB
#   each inline script in a page            40 KB raw
#   each stylesheet (assets/css)            36 KB   (was 20: flair-map.css carries the map controls and panels; only Spatial Distribution loads it)
#   each .webp photo (assets/img)          160 KB
#
# Big third-party libraries (MapLibre, supabase-js) load only on the pages
# that need them and are checked by version, not here.
set -u
cd "$(dirname "$0")/../.."
fail=0
size() { case "$1" in *.css|*.js|*.svg|*.html|*.json) gzip -9 -c "$1" | wc -c ;; *) wc -c < "$1" ;; esac; }
over() { echo "FAIL $1: $2 bytes, budget $3"; fail=1; }

for f in admin/assets/js/*.js;   do
  case "$f" in admin/assets/js/spatial.js) lim=65536 ;; *) lim=16384 ;; esac   # Spatial's map engine (16 Nov 2026: moved out of the page so it is cached)
  s=$(size "$f"); [ "$s" -le $lim ] || over "$f" "$s" $lim
done
for f in admin/assets/css/*.css; do s=$(size "$f"); [ "$s" -le 36864 ]  || over "$f" "$s" 36864;  done
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
for f in inter-regular inter-semibold inter-tight-bold; do
  total=$((total + $(size "admin/assets/vendor/fonts/$f.woff2")))
done
if [ "$total" -le 344064 ]; then echo "ok   sign-in page: $total bytes of 344064"; else over "sign-in page" "$total" 344064; fi
# Inline scripts (16 Nov 2026 sweep): a script written into the page is downloaded and compiled on every visit and never cached,
# so a page's own logic belongs in assets/js/. Each inline <script> block in a page source stays under 40 KB.
for f in admin/*.php admin/includes/*.php; do
  big=$(php -r '$s = file_get_contents($argv[1]); preg_match_all("#<script(?![^>]*\bsrc=)(?![^>]*application/json)[^>]*>(.*?)</script>#s", $s, $m); $mx = 0; foreach ($m[1] as $b) { $mx = max($mx, strlen($b)); } echo $mx;' "$f")
  [ "$big" -le 40960 ] || over "$f (largest inline script)" "$big" 40960
done
[ $fail = 0 ] && echo "ok   every script, stylesheet and photo within budget"
exit $fail
