# Deploying SmartSumbong

> **Current setup (October 2026): see [docs/OPERATIONS.md](docs/OPERATIONS.md).**
> The portal now runs on Render in Singapore (smartsumbong-ph) and deploys
> automatically after CI passes. The notes below are the original first-time
> setup and are kept for reference.

Three parts, deployed separately:

| Part | Where it runs | How it updates |
|---|---|---|
| Admin portal (`admin/`) | Render web service, from this repo's `Dockerfile` | Push to `main` — Render rebuilds |
| Database, auth, realtime, push functions | Supabase project | `supabase db push` (migrations), `supabase functions deploy` |
| Mobile app (`mobile/resident`, residents and tanods) | Testers' phones | Build an APK and hand it out |

## Admin portal on Render

Set up once: **New + → Web Service → `Bellinidesu/SmartSumbong`**, runtime
**Docker** (auto-detected), root directory blank, instance **Free**.
Environment variables:

- `SUPABASE_URL` — the project URL
- `SUPABASE_ANON_KEY` — the publishable key (the same one the app uses)

`config.php` reads both from the environment. Nothing server-side needs the
service-role key.

After that, **every push to `main` redeploys**. Check Render's Events tab that
the build finished.

Free services sleep after 15 minutes idle; the first request after that takes
about a minute, and admin sessions do not survive the restart (sign in again).
Open the portal a few minutes before a demo.

### One Supabase setting per portal URL

Authentication → URL Configuration → Redirect URLs → add
`https://<your-render-url>/admin/reset-password.php`. Without it, the admin
"forgot password" email links to a URL Supabase refuses.

## Database

```
supabase link --project-ref <ref>     # once
supabase migration list               # what is applied where
supabase db push                      # apply new migrations
```

Migrations run in order and are never edited after they are applied; a
change is a new numbered migration. `docs/schema.md` explains what they add
up to. Drafts that must not be pushed live outside `supabase/migrations/`
(for example `docs/chat/`).

The GitHub Action `keep-supabase-awake.yml` pings the project so the free
tier does not pause it. It needs the repository secrets it names.

## Mobile app

From `mobile/resident`:

```
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` is the one for
almost every phone. `dart_defines.json` holds the app's public settings —
Supabase URL, the publishable key, Cloudinary's unsigned upload presets —
which ship inside the APK anyway. Never put a secret key in it.

## Running locally

`run-dev-server.bat` (or `php -S 127.0.0.1:8000 -t .` from the repo root)
serves the portal at `http://127.0.0.1:8000/admin/` against the same live
Supabase project — view freely, but anything you click changes real data.
