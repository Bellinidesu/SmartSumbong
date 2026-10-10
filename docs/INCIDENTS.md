# When something breaks

What to do, in order, when SmartSumbong is down, wrong, or leaking. Written
for whoever is on duty, not only the developer. `docs/OPERATIONS.md` says
how the system runs normally; this file is for when it doesn't.

## Who

| Role | Who | Reach them |
|---|---|---|
| Incident lead (decides, talks to the barangay) | _fill in_ | _fill in_ |
| Developer on call (Supabase, Render, Cloudinary, Firebase access) | _fill in_ | _fill in_ |
| Barangay contact (tells residents, pauses filing if asked) | _fill in_ | _fill in_ |
| Data Protection Officer (personal data involved) | _fill in_ | _fill in_ |

Keep the table current. Everything below assumes these people exist.

## How bad is it

| Level | Means | Examples | Respond |
|---|---|---|---|
| 1 | People's data exposed, or residents cannot report anything | A secret key leaked; database down; IDs visible to strangers | Now, any hour. Tell the incident lead and the DPO. |
| 2 | One part broken, a workaround exists | Push notifications not arriving; portal down but app works; uploads failing | Same day. |
| 3 | Annoying, nothing lost | A page slow; a wrong label; one scheduled job failed once | Next working day. |

## First five minutes, every time

1. Open the portal: **Settings → System status**. The *Needs attention*
   box lists what the hourly health check found (failed scheduled jobs,
   database size, photo cleanup, Edge Function failures); *Recent errors*
   lists the latest crashes (server, browser, function).
2. Check the providers' own status pages: status.supabase.com,
   status.render.com, status.cloudinary.com, status.firebase.google.com.
   If it is theirs, say so to the barangay and wait; do not change things.
3. Write down the time and what you saw. Every action you take goes in the
   same note. It becomes the report afterwards.

## Pausing report filing

When new complaints would be lost or mishandled (database trouble, a bad
release), stop new filings and tell residents why, from the Supabase SQL
editor:

```sql
update operational_settings
   set filing_paused = true,
       filing_paused_message = 'Filing is paused while we fix a problem. For anything urgent, call the barangay hall.'
 where id = 1;
```

The app shows that sentence when someone tries to file. Undo with
`set filing_paused = false`. Reports already filed are untouched and the
portal keeps working.

## Scenarios

### The portal does not load
- The database pings it every 10 minutes and tells every admin after two
  misses, so you may already have a notification.
- Render dashboard → smartsumbong-ph → Events and Logs. A failed deploy:
  roll back to the previous deploy (Render keeps them). A crash loop: the
  log names the PHP file.
- The app keeps working without the portal; residents can still file.

### The app cannot sign in or load anything
- Supabase dashboard: is the project paused (free plan, a week without
  use)? Restore it; `keep-supabase-awake.yml` is meant to prevent this.
- Over the free plan's limits (database 500 MB, egress)? The health check
  warns at 80% of 500 MB. Archive old data or move to a paid plan.
- If only sign-in fails and CAPTCHA protection was just switched on: switch
  it off (Supabase → Authentication → Bot and Abuse Protection) until every
  phone has an app built with `TURNSTILE_SITE_KEY`.

### Push notifications stopped
- Recent errors will show `send-dispatch-push` failures. FCM 401 means the
  Firebase service account key is wrong or revoked: set new
  `FCM_PRIVATE_KEY` / `FCM_CLIENT_EMAIL` secrets.
- If `PUSH_WEBHOOK_SECRET` was just set, the Database Webhook must send the
  same value as `x-webhook-secret`, or every push is refused.
- In-app notifications still arrive; only the phone banner is missing.

### Photo uploads fail
- `sign-upload` needs `CLOUDINARY_API_KEY` and `CLOUDINARY_API_SECRET`.
  Without them it answers 503 and the app falls back to the unsigned
  presets; if those were already deleted, uploads fail. Restore the secrets
  (or, short term, recreate the preset).
- Cloudinary quota full: Settings → Plan and usage shows credits. Upgrade or
  delete old media.

### A scheduled job keeps failing
- The alert names the job. In the SQL editor:
  `select * from cron.job_run_details where status = 'failed' order by start_time desc limit 5;`
  The `return_message` says why. Fix with a new migration, never by editing
  an applied one.

## A secret leaked (Level 1)

Rotate first, investigate second. Each key, where it lives, and what breaks
until the new one is in place:

| Secret | Rotate in | Then update | Until updated |
|---|---|---|---|
| Supabase secret / service-role key | Supabase → Project Settings → API keys (create a new secret key, delete the old) | Edge Function secrets are injected automatically; GitHub secrets if any workflow used it | Functions fail |
| Supabase database password | Supabase → Database → Settings | GitHub `SUPABASE_DB_PASSWORD` (backups) | Nightly backup fails |
| Supabase access token | supabase.com → Account → Access tokens | GitHub `SUPABASE_ACCESS_TOKEN` | Backups, staging checks fail |
| Cloudinary API secret | Cloudinary → Settings → API Keys (generate new, then disable old) | `supabase secrets set CLOUDINARY_API_SECRET=…` and Render `CLOUDINARY_API_SECRET` | Signed uploads and private photo links fail |
| Firebase service account key | Google Cloud → IAM → Service accounts → Keys (add new, delete old) | `FCM_PRIVATE_KEY`, `FCM_CLIENT_EMAIL` | Push banners stop |
| Semaphore API key | Semaphore dashboard | `SEMAPHORE_API_KEY` | SMS codes stop |
| `PUSH_WEBHOOK_SECRET`, `MEDIA_CLEANUP_SECRET` | Make a new random value | The function secret **and** the webhook header / Vault entry (`vault.update_secret`) | Push / cleanup refused |
| Turnstile secret | Cloudflare → Turnstile | Supabase → Bot and Abuse Protection | Sign-in refused while CAPTCHA is on |
| `BACKUP_PASSPHRASE` | New value in the password manager | GitHub secret | Old backups still need the old passphrase: keep it until they expire (30 days) |

The Supabase publishable (anon) key and the Firebase API keys are public by
design (they ship in the app; `.gitleaks.toml` explains). If one is abused,
restrict it (Google Cloud → Credentials → restrict to the app) rather than
rotating, which would need a new app release.

Then: `gitleaks` (Security workflow) to make sure nothing else is in the
history; if the secret is in git history, rotating is the fix: rewriting
history does not un-publish a public repository.

## Personal data exposed (Level 1)

Residents' names, numbers, IDs, selfies and complaints are personal data
under the Data Privacy Act (RA 10173).
1. Stop the exposure first (rotate the key, take the page down, pause
   filing, make the photo private).
2. Tell the DPO immediately. The National Privacy Commission must be
   notified within 72 hours of knowing about a breach likely to harm the
   people involved, and those people told too; the DPO decides and files.
3. Keep the note from "First five minutes": what was exposed, whose, for
   how long, how it was stopped.

## A migration went wrong

Migrations cannot be un-applied. Write the next numbered migration that
puts things right, test it with `bash supabase/tests/local/run-local.sh`,
and push it. If data was destroyed, restore it from the nightly backup into
a **separate** project first (`docs/OPERATIONS.md`, Backups) and copy back
only the rows you need. Never restore over the live project.

## Afterwards

Within a week, write a short note in `docs/incidents/YYYY-MM-DD-what.md`:
what happened, the timeline, what was affected, the cause, and the change
that stops it happening again. No blame; the point is the fix.
