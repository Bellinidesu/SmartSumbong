# Deploying SmartSumbong

How to stand up every part from nothing: a new Supabase project, the Edge
Functions, Cloudinary, Firebase, the portal on Render, GitHub, and a signed
app. It is also the reference for **every configuration value** the system
reads. Day-to-day releases and monitoring are in
[docs/OPERATIONS.md](docs/OPERATIONS.md).

The production system today:

| Part | Where | Identifier |
|---|---|---|
| Admin portal | Render web service, Singapore | `smartsumbong-ph` → https://smartsumbong-ph.onrender.com |
| Old portal address | Render web service, Ohio | `smartsumbong` (only forwards, `PORTAL_MOVED_TO`) |
| Database, Auth, Realtime, Edge Functions | Supabase, Mumbai | project `xmkpokcnjzgxgwysperh` |
| Photos and video | Cloudinary | cloud `nwb2kryl` |
| Push, crash reports | Firebase | the project in `mobile/resident/android/app/google-services.json` |
| SMS | Semaphore | the account whose key is `SEMAPHORE_API_KEY` |

## What you need

PHP 8.5, Flutter 3.47 with Android Studio (its bundled JDK), Node 24, Deno 2.9,
the Supabase CLI 2.121 and the GitHub CLI. Accounts: Supabase, Render,
Cloudinary, Firebase (Google Cloud), GitHub; Semaphore and Cloudflare only for
SMS and the bot check.

## 1. The database (Supabase)

1. Create the project. In Database → Extensions enable **postgis** and
   **pg_cron** (and **pg_net**, used by the keep-awake and cleanup jobs).
   `pgcrypto` is created by the first migration.
2. Link and apply the schema:

   ```bash
   supabase link --project-ref <ref>
   supabase db push                       # applies supabase/migrations in order
   psql "$DATABASE_URL" -f supabase/seed.sql
   ```

   A new project may instead load `supabase/baseline/baseline.sql` (the same
   schema in one file; its header explains how) and then take later
   migrations with `supabase db push`.
3. Authentication → URL Configuration: **Site URL** is the portal's address;
   add `https://<portal>/admin/reset-password.php` to **Redirect URLs**, or the
   admin password-reset link is refused.
4. Authentication → Emails → Templates → Reset Password: paste
   `docs/email/reset-password.html` (subject: *Reset your SmartSumbong password*).
   Only administrators get mail; residents and tanods sign in with a number.

Migrations are numbered and never edited once applied: a change is the next
number. Numbers 0048 and 0108–0113 are unused (0108–0113 became 0114–0120 to
follow production's 0107). Drafts that must not be pushed live outside
`supabase/migrations` (for example `docs/chat/`).

## 2. Edge Functions

Set the secrets (Edge Functions → Secrets, or `supabase secrets set NAME=value`):

| Secret | Function | Purpose |
|---|---|---|
| `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` | `send-dispatch-push` | the Firebase service account that sends pushes |
| `PUSH_WEBHOOK_SECRET` (optional) | `send-dispatch-push` | once set, only a caller sending it as `x-webhook-secret` is answered |
| `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | `sign-upload`, `media-cleanup` | signing uploads and private links; deleting old identity photos |
| `MEDIA_CLEANUP_SECRET` | `media-cleanup` | the shared secret pg_cron sends (also stored in Vault, below) |
| `SEMAPHORE_API_KEY` | `password-otp` | sending SMS codes (by Semaphore's OTP route, `/api/v4/otp`) |
| `SEMAPHORE_SENDER_NAME` (optional) | `password-otp` | a sender name Semaphore has approved for the account; without it codes come from Semaphore's default name |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected into every function by Supabase.

Deploy them all (Actions → **Deploy** does this, see OPERATIONS), or by hand:

```bash
for f in send-dispatch-push sign-upload password-otp delete-account media-cleanup; do
  supabase functions deploy "$f" --project-ref <ref> --use-api
done
```

`supabase/config.toml` sets each function's JWT check; never run
`supabase config push` from it.

Then wire them up:

- **Push.** Database → Webhooks → new webhook on **INSERT** into
  `public.notifications`, calling the `send-dispatch-push` function. If
  `PUSH_WEBHOOK_SECRET` is set, add the header `x-webhook-secret` with the
  same value.
- **Photo cleanup.** In the SQL editor, store where to call it:

  ```sql
  select vault.create_secret('https://<ref>.supabase.co/functions/v1/media-cleanup', 'media_cleanup_url');
  select vault.create_secret('<the MEDIA_CLEANUP_SECRET value>', 'media_cleanup_secret');
  ```

  The Deploy workflow does this by itself the first time. The daily job does
  nothing until both entries exist.

## 3. Cloudinary

1. Settings → Security → signature algorithm **SHA-256** (every signature in
   the system uses it; while the two disagree, signed uploads fail and private
   ID photos do not open).
2. Upload presets, *unsigned*, overwrite off: `smartsumbong_unsigned` (jpg, png,
   webp) and `smartsumbong_unsigned_video` (mp4). They are only a fallback for
   app builds older than signed uploads; once no phone runs one, delete them.
3. The API key and secret go to Supabase (above), to Render (below), and to
   GitHub if the Deploy workflow should set them.

## 4. Firebase

1. Create a project with an Android app, package `ph.smartsumbong.resident`.
   Add the release key's fingerprints (Project settings → Your apps → SHA
   certificate fingerprints): both **SHA-1** and **SHA-256** from
   `keytool -list -v -keystore <keystore> -alias <alias>`.
2. Put `google-services.json` in `mobile/resident/android/app/` and regenerate
   `lib/firebase_options.dart` with `flutterfire configure`.
3. Cloud Messaging uses the HTTP v1 API: create a service-account key
   (Project settings → Service accounts) and set its project id, client email
   and private key as the `FCM_*` secrets above.
4. Crashlytics needs no extra setup beyond the plugin.
5. The Firebase API keys ship inside the app by design. Restrict them in
   Google Cloud Console → APIs & Services → Credentials: API restrictions to
   the Firebase APIs the app uses, application restriction to Android apps
   with the package name and the **SHA-1** fingerprint (that screen takes
   SHA-1 only).

## 5. The portal (Render)

**New → Web Service** from this repository, runtime **Docker** (the
`Dockerfile` at the root), region Singapore, health check path
`/admin/ping.php`. Auto-Deploy is **off**: after a merge, deploy with
**Manual Deploy → Deploy latest commit** (Render can instead be set to
deploy *after CI checks pass*).

Environment variables, every one the portal reads (`admin/includes/config.php`).
`.env` is git-ignored, so a value that exists only on a laptop is not on
Render:

| Variable | Needed for | Without it |
|---|---|---|
| `SUPABASE_URL` | everything | the portal does not start |
| `SUPABASE_PUBLISHABLE_KEY` (or `SUPABASE_ANON_KEY`) | everything; public by design | the portal does not start |
| `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_UPLOAD_PRESET` | showing and uploading photos | photos do not show |
| `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | signed uploads, private ID photo links, Plan and usage | uploads use the fallback preset; ID photos and credits missing |
| `MAPILLARY_TOKEN` | street view: "Look around" and the case map's snapshot | no street view |
| `TURNSTILE_SITE_KEY` | the bot check on sign-in pages | no bot check |
| `BARANGAY_HALL_HOURS`, `BARANGAY_HALL_PHONE` | the hall line shown to residents | the default text |
| `RESIDENT_APP_URL` | the Workspace's Report QR widget (an https link) | the widget asks for the link |
| `PORTAL_MOVED_TO` | only on an old host: forwards every page to the new address | no forwarding |

Nothing on Render needs the service-role key.

Free instances sleep after about 15 minutes idle; the database pings
`/admin/ping.php` every 10 minutes (`keep-portal-awake`) so this one does not.

## 6. GitHub

Settings → Secrets and variables → Actions:

| Name | Kind | Used by |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` | secret | Deploy, Nightly backup, staging checks |
| `BACKUP_PASSPHRASE` | secret | Nightly backup (encrypts the dump; keep it in the team's password manager) |
| `HEALTHCHECKS_BACKUP_URL` | secret, optional | Nightly backup: a check's ping address on healthchecks.io, which emails the team when a night's backup fails or does not run |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | secret | Keep Supabase awake |
| `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | secret, optional | Deploy (sets them as function secrets) |
| `STAGING_DB_PASSWORD` + variable `STAGING_PROJECT_REF` | optional | CI's staging checks after a merge |

Settings → Code security: Dependabot alerts and security updates, secret
scanning and push protection on. Settings → General: *Automatically delete
head branches* on. The workflows are described in OPERATIONS.

## 7. The app

```bash
cd mobile/resident
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` is for almost every
phone, `app-armeabi-v7a-release.apk` for 32-bit ones. Minimum Android 7.0.

- `dart_defines.json` (committed) holds the public client values:
  `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable key),
  `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_UPLOAD_PRESET`,
  `CLOUDINARY_UPLOAD_PRESET_VIDEO`. Never put a secret in it: anything in an
  APK can be read out of it. Optional: `--dart-define=TURNSTILE_SITE_KEY=…`
  (and `TURNSTILE_BASE_URL`) for the bot check.
- **Signing.** `mobile/resident/android/key.properties` (never committed):

  ```properties
  storePassword=…
  keyPassword=…
  keyAlias=…
  storeFile=<path to the .jks>
  ```

  With it, the release is signed with the barangay's key; without it, with the
  debug key. Back the keystore up in two places: a lost key means the app can
  never be updated, only reinstalled.

## 8. Running locally

```bash
cp .env.example .env    # then fill it in
php -S 127.0.0.1:8000 -t .
```

or `run-dev-server.bat` on Windows. The portal is at
http://127.0.0.1:8000/admin/ and talks to the project `.env` names: against
production, anything you click changes real data. The app's preview
(`flutter run -d web-server --web-port 5000 -t lib/main_preview.dart`) needs
no backend at all.
