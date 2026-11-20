# tools/sweep: the scripted backend sweep

Scripts that find gaps systematically. Each runs alone, prints a compact result, and writes details to `out/*.json` (gitignored).
Read-only against the live project (live row counts and the portal's response headers only). Nothing here changes a migration or live behaviour.

    bash tools/sweep/run_all.sh          # everything, ~20-30 min (migrations 3 min, seed 250x 3-5 min, replays 5-10 min)
    bash tools/sweep/run_all.sh quick    # static only, ~1 min, needs the local database from an earlier full run

| Script | Step | What it does |
|---|---|---|
| `local_db.sh` | setup | Throwaway PostgreSQL 16 + PostGIS (pg_cron stubbed), all migrations applied. `up`, `down`, `psql ...`. Env: `PGBIN`, `SWEEP_PORT` (55441). |
| `pagemap.py` | 1 | Page -> press -> backend objects map (admin/*.php, includes, JS). Flags: POST handlers without CSRF, direct table writes, RPCs missing / not granted, never called. |
| `capture_pages.py` | 2a | Runs every real portal page, per rung (super, captain, committee, moderator), against the test fake Supabase with a logger; records each backend request. |
| `loadcost.py` | 2b | Seeds the throwaway DB at 1x (82 cases) and 250x (20,000), replays the captured requests plus a few phone-app reads through a local PostgREST as each rung's own role (row level security on), prints the 15 slowest, pages over 200 ms, chatty pages, seq scans. |
| `smart.py` | 3 | SMART engine: `smart_queue` per rung, triggers on filing, snapshot refresh, watcher, proof that filing survives a broken engine, grow-only tables. |
| `standards.py` | 4 | Live portal headers/cookies, Edge Functions vs config.toml, migration hygiene and numbering gaps, pgTAP coverage map, secrets scan (file:line only). |
| `detectors.py` | 7 | Six detectors: lifecycle, producer/consumer, request/decision symmetry, author-admitted gaps, role symmetry, doc vs code. |
| `ledger.py` | 5 | Rebuilds the AUTO block of `docs/sweep/GAP_LEDGER.md` with A/B/C classes. |

Needs: PostgreSQL 16 + PostGIS binaries (`PGBIN`; on Windows the EDB zip plus the OSGeo PostGIS bundle), PostgREST 12 (`PGRST_BIN`, needs libpq on PATH),
`php`, Python 3.9+ (stdlib only), the Supabase CLI linked to the project for the live counts. On Linux: `apt-get install postgresql-16 postgresql-16-postgis-3`
and set `PGBIN=/usr/lib/postgresql/16/bin`.

Limits worth knowing: the page requests come from the test fake, so a page's data-dependent follow-up requests may differ on live; queries run on a laptop
(timings are relative, not Singapore's); bulk history is loaded with the SMART triage trigger off and the newest 3,000 open cases triaged.
