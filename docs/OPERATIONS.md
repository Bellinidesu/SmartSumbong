# Operating SmartSumbong

How the system runs in production, how changes reach it, and what to do
when something breaks. Written for whoever maintains it next (October 2026).

## What runs where

| Part | Where | Notes |
|---|---|---|
| Admin portal (`admin/`) | Render web service **smartsumbong-ph**, Singapore, Docker (`Dockerfile`, PHP 8.5 + Apache) | https://smartsumbong-ph.onrender.com. The old Ohio service `smartsumbong.onrender.com` only forwards old links (`PORTAL_MOVED_TO`). |
| Database, sign-in, realtime, Edge Functions | Supabase project `xmkpokcnjzgxgwysperh` (Mumbai) | Migrations in `supabase/migrations`, functions in `supabase/functions`. |
| Photos and videos | Cloudinary cloud `nwb2kryl` | Presets `smartsumbong_unsigned` (jpg/png/webp) and `smartsumbong_unsigned_video` (mp4); overwrite off. |
| Push notifications | Firebase Cloud Messaging, sent by the `send-dispatch-push` Edge Function | |
| Mobile app (`mobile/resident`, residents and tanods) | Android APK | Built locally; see *Releasing the app*. |

## How a change reaches production

1. Work on a branch; open a pull request to `main`.
2. **CI** (`.github/workflows/ci.yml`) runs on every push and pull request:
   - **portal** — every PHP and JS file parses; the portal starts and answers
     (login, sign-in redirect, ping, 404 page, security headers, a nonce on
     every script, no inline event handlers);
   - **mobile** — `flutter analyze` with no findings allowed, all tests;
   - **functions** — the Edge Functions type-check, lint and pass their tests;
   - **database** — every migration applied to a throwaway PostgreSQL in the
     runner, every rolled-back check in `supabase/tests`, and the baseline
     still matching the migrations. The live project is never touched;
   - **staging** — after a merge to `main` only, and only if a staging
     project is configured (repository variable `STAGING_PROJECT_REF`,
     secrets `SUPABASE_ACCESS_TOKEN` and `STAGING_DB_PASSWORD`): migrations
     pushed to staging, then the same checks there. The script refuses the
     production project.

   **Security** (`.github/workflows/security.yml`), on pull requests, merges
   and every Monday: gitleaks over the whole history (`.gitleaks.toml` lists
   the public client keys), osv-scanner over the lockfiles, CodeQL over the
   JavaScript, TypeScript and workflows. Actions are pinned to commit hashes
   and tools to exact versions; Dependabot proposes updates weekly
   (Flutter packages, Actions, the Docker base image).
3. Merge when CI is green. Render deploys the portal automatically **only
   after CI passes** (Auto-Deploy: *After CI checks pass*), and checks
   `/admin/ping.php` before switching traffic to the new version.
4. Database changes: `supabase db push --linked` (each migration is a new
   numbered file; never edit an applied one). Functions:
   `supabase functions deploy <name> --project-ref xmkpokcnjzgxgwysperh --use-api`.
   Each function's logic is in `handler.ts` (tested by `handler.test.ts`
   with every outside call stubbed); `index.ts` only serves it. Locally:
   `deno check supabase/functions/*/index.ts && deno lint supabase/functions
   && deno test --allow-env supabase/functions`.
   Push the migrations before deploying a function that uses what they add
   (for example `password-otp` needs 0107's `otp_attempt`).
   `supabase/config.toml` pins each function's JWT check; never run
   `supabase config push` from it.

Rules the code must keep (CI enforces most of them):

- **No inline event handlers** in the portal (`onclick=` …): the
  Content-Security-Policy refuses them. Use `data-autosubmit` /
  `data-native-confirm` (see `admin/assets/js/p.js`). A new outside service
  must be added to the policy in `admin/includes/config.php`.
- New tables get row-level security; policies use `(select auth.uid())`;
  every foreign key gets an index.
- Names are stored "Last, First" and shown First Last (`display_name()`).

## Configuration

Render environment variables (smartsumbong-ph): `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`,
`CLOUDINARY_API_SECRET`.

GitHub Actions secrets: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`,
`BACKUP_PASSPHRASE` (the nightly backup), `STAGING_DB_PASSWORD` and the
variable `STAGING_PROJECT_REF` (optional staging checks) (also `SUPABASE_URL`, `SUPABASE_ANON_KEY` for the daily
keep-awake job).

Supabase secrets (Edge Functions): FCM service account values for
`send-dispatch-push`, and optionally `PUSH_WEBHOOK_SECRET` (0107: once set,
the function only answers a caller sending it as `x-webhook-secret`, so add
that header to the Database Webhook first or pushes stop); `SEMAPHORE_API_KEY` and the OTP secret for
`password-otp` (SMS reset is switched off in the app until Semaphore credits
are bought).

**Signed uploads (0109).** `sign-upload` needs `CLOUDINARY_API_KEY` and
`CLOUDINARY_API_SECRET` as Supabase secrets; until they are set it answers
503 and the app keeps using the unsigned presets. The portal signs on its
own whenever the same two values are in Render's environment. Rollout:
push 0109, set the secrets, deploy `sign-upload`, release the app, check
that a new complaint photo, a tanod proof photo, a registration ID and a
portal photo all upload. Only once no phone runs an older build, delete
`smartsumbong_unsigned` and `smartsumbong_unsigned_video` in Cloudinary;
until then both the app and the portal fall back to them if a signature
is ever refused.

**Private identity photos (0110).** New registration IDs and selfies are
stored as Cloudinary *authenticated* assets: their stored address opens
nothing. The portal signs a viewing link each time it shows one (needs
`CLOUDINARY_API_SECRET` in Render); the app asks `sign-upload` for one when
it re-reads its own ID. Profile pictures go to the public `avatars/`
folder. Photos uploaded before 0110 stay public until moved, once, with
`node scripts/privatize-identity-photos.mjs` (dry run) and then `--apply`
(it needs the Supabase service key and the Cloudinary key and secret in
its environment; run it from a trusted machine, never commit them).

**Identity photo cleanup (0111).** When an account is deleted, an ID is
replaced or declined, or a profile picture changes, the old photo's
address is queued in `media_trash`. A week later the `media-cleanup`
function deletes the file from Cloudinary if nothing uses it any more
(evidence photos are never queued). To switch it on, once:
1. `supabase secrets set MEDIA_CLEANUP_SECRET=<long random string>` (the
   Cloudinary key and secret are already set for `sign-upload`), then
   deploy `media-cleanup`.
2. In the SQL editor, store where to call it, in Vault:
   `select vault.create_secret('https://xmkpokcnjzgxgwysperh.supabase.co/functions/v1/media-cleanup', 'media_cleanup_url');`
   `select vault.create_secret('<the same long random string>', 'media_cleanup_secret');`

The daily `media-cleanup` job does nothing until both are there.

**Bot check on sign-in (CAPTCHA).** Built in but off. To switch it on:
1. Cloudflare → Turnstile → add a widget (mode *Invisible* or *Managed*)
   for `smartsumbong-ph.onrender.com`; note the site key and secret key.
2. Render: add `TURNSTILE_SITE_KEY` (the portal then loads the widget on
   every page with a password form and on login / forgot-password).
3. App: build with `--dart-define=TURNSTILE_SITE_KEY=<site key>` (and
   `TURNSTILE_BASE_URL` if the widget's domain is not the portal's).
4. Only once every phone runs that build: Supabase → Authentication →
   Bot and Abuse Protection → enable CAPTCHA, provider Turnstile, paste the
   secret key. From then on sign-in, sign-up and password-reset links
   without a valid token are refused; until then tokens are sent and
   ignored. Turning it off again is the same switch.

Supabase Auth → URL Configuration: Site URL and redirect URL are the
Singapore portal.

## Monitoring

When something is wrong, `docs/INCIDENTS.md` says what to do.

- **Health check** (0112, hourly) — failed scheduled jobs, the database
  past 80% of 500 MB, identity photos the cleanup missed, and Edge Function
  failures each raise one alert: every admin is notified once and it shows
  under Settings → System status → *Needs attention* until it clears.
  Edge Function errors are also listed under *Recent errors*.

- **Uptime** — the database pings `/admin/ping.php` every 10 minutes
  (`keep-portal-awake`, which also stops Render's free plan from sleeping).
  Two misses in a row notify every admin; recovery is announced too.
  Settings → System status shows the last day and week.
- **Errors** — portal crashes and browser errors go to `portal_errors`,
  grouped, newest in Settings → System status. App crashes go to Firebase
  Crashlytics.
- **Speed and quality** — `?_trace=1` on any portal page lists each database
  call's time in the page source. Lighthouse: 100 on performance,
  accessibility and best practices.
- **Dependencies** — Dependabot opens weekly update pull requests (Flutter
  packages, GitHub Actions). Merge them through CI like any change.

## Backups and restore

- **Nightly** (`.github/workflows/backup.yml`, 02:30 PH time): roles, schema
  and data, encrypted with `BACKUP_PASSPHRASE`, kept 30 days as the
  `smartsumbong-backup` artifact of each run.
- **Restore** into a fresh Supabase project:
  1. Download the artifact; `gpg --decrypt smartsumbong-<date>.tgz.gpg | tar xz`.
  2. `psql "<new project connection string>" -f roles.sql`, then
     `-f schema.sql`, then `-f data.sql`.
  3. Point the portal (`SUPABASE_URL`, key) and the app's
     `dart_defines.json` at the new project; redeploy the Edge Functions and
     set their secrets.
- Photos live in Cloudinary, not in the database backup.

## Releasing the app

```
cd mobile/resident
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

`app-arm64-v8a-release.apk` for most phones, `app-armeabi-v7a-release.apk`
for 32-bit ones (e.g. Oppo A12). Minimum Android 7.0.

Signing: with `mobile/resident/android/key.properties` (never committed) the
release is signed with the barangay's key; without it, with the debug key.
**Back the keystore up in two places** — a lost key means the app can never
be updated, only reinstalled.

## When something breaks

| Symptom | First look |
|---|---|
| Portal down | Render dashboard → smartsumbong-ph → Logs / Events; Settings → System status in the portal once it is back. |
| A page errors | Settings → System status → Recent errors; Render logs. |
| App crashes | Firebase Crashlytics. |
| No push notifications | Supabase → Edge Functions → `send-dispatch-push` logs; the user's `device_tokens`. |
| Database checks fail in CI | The failing line names the step; run `supabase db query --linked -f supabase/tests/01_lifecycle.sql` locally. |
| Supabase paused | Restore it in the dashboard; the daily keep-awake job should prevent this. |

## Secrets hygiene

Never commit `.env`, `dart_defines.json`, `key.properties` or keystores (all
in `.gitignore`; the repository is public). Rotate a key that was shared in
chat or a screenshot. Delete API keys made for one-off jobs (the Render API
key used for the Singapore move) when the job is done.
