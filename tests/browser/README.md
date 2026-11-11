# Browser tests

Every portal page opened in Chromium by Playwright, signed in as a demo
administrator, against a **fake Supabase** (`fake/`, made-up data, invented
names, numbers and emails). Each page must:

- answer 200 and throw no error in the console;
- have no **serious or critical** accessibility problem by axe-core's WCAG 2.1
  A and AA rules, in light mode, and dark mode for the dashboard and cases.

Run on this PC (Git Bash):

    cd tests/browser
    npm ci && npx playwright install chromium      # once
    SITE=$(mktemp -d) bash serve.sh                 # the portal on 127.0.0.1:8013, fake Supabase on 54399
    npx playwright test
    kill $(cat "$SITE/pids")                        # stop both

`serve.sh` copies `admin/` into a throwaway folder with its own fake `.env`,
so the repo's real `.env` is never read and the live project is never
touched. `router.php` signs every request in; it exists only in that copy and
is never in the Docker image. CI runs the same in the **browser** job.

Lighthouse 13 (`node lighthouse.mjs`) scores sign-in, the dashboard, cases and
the summary in the same Chromium: accessibility must stay at 95 or more and
best practices at 90 or more; performance under 80 only warns, because CI
machines vary. On 22 Oct 2026: accessibility 98 to 100, best practices 96 to
100, performance 93 to 99. The reports land in `lighthouse/`. (Lighthouse CI,
the usual wrapper, was not used: its dependencies carry 17 known advisories
and it has not been updated since June 2025; Lighthouse itself has none.)

To check a new page, add it to `PAGES` in `pages.spec.mjs`; if it needs data
the fake does not have yet, add it to `fake/fake_sb.py` (keep it invented).

## The speed probe

`chooser-probe.spec.mjs` presses every chooser on every page (tabs, chips, filters, pagers that stay on the page) for a super
admin and a Kagawad, and prints for each press whether it swapped in place or reloaded, how long until it settled, and the
server's Server-Timing (waits on the database, calls, server time); `?_trace=1` lists each wait. Give the fake a round trip so
waits cost what a distant database makes them cost, and the shared cache its live lifetime:

    SITE=$(mktemp -d) FAKE_RTT_MS=100 bash serve.sh
    sed -i 's/^FEATURE_CACHE_TTL=0/FEATURE_CACHE_TTL=300/' "$SITE/.env"
    CP=1 OUT=probe.jsonl npx playwright test chooser-probe.spec.mjs --workers=1

The local server answers one request at a time, so background calls (the street labels, the widgets) can make a page's own
time look longer than it is on Render; the waits and the server time are the figures to compare.
