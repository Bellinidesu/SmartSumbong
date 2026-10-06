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
   - **mobile** — `flutter analyze` with no findings allowed, unit tests;
   - **database** — the 126 rolled-back system checks in `supabase/tests`
     against the real project.
3. Merge when CI is green. Render deploys the portal automatically **only
   after CI passes** (Auto-Deploy: *After CI checks pass*), and checks
   `/admin/ping.php` before switching traffic to the new version.
4. Database changes: `supabase db push --linked` (each migration is a new
   numbered file; never edit an applied one). Functions:
   `supabase functions deploy <name> --project-ref xmkpokcnjzgxgwysperh --use-api`.

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
`BACKUP_PASSPHRASE` (also `SUPABASE_URL`, `SUPABASE_ANON_KEY` for the daily
keep-awake job).

Supabase secrets (Edge Functions): FCM service account values for
`send-dispatch-push`; `SEMAPHORE_API_KEY` and the OTP secret for
`password-otp` (SMS reset is switched off in the app until Semaphore credits
are bought).

Supabase Auth → URL Configuration: Site URL and redirect URL are the
Singapore portal.

## Monitoring

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
