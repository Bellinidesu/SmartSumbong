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
