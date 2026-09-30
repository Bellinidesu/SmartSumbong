# SmartSumbong

A hybrid barangay complaint and incident reporting system for **Barangay 183, Pasay City**.
Capstone project, BS Information Technology, Polytechnic University of the Philippines.

## Scope

Complaint reporting only. The emergency dispatch feature was removed by unanimous
panel direction — the system surfaces emergency service hotlines instead of
handling emergency response itself.

Three actors: **Resident**, **Barangay Tanod**, **Barangay Admin**.

## Stack

| Layer | Technology |
|---|---|
| Backend | Supabase — PostgreSQL, Realtime, Edge Functions, Auth, RLS, pg_cron |
| GIS | PostGIS; MapLibre GL (portal: JS, app: Flutter) on OpenFreeMap vector tiles |
| Admin portal | PHP 8, own CSS (Figma design, light/dark, English/Tagalog), Chart.js |
| Mobile app | Flutter — one app for residents and tanods (Android) |
| Media | Cloudinary (unsigned uploads, EXIF stripped on the phone) |
| Push | Firebase Cloud Messaging, via the `send-dispatch-push` Edge Function |
| Walking routes | OpenStreetMap FOSSGIS router (tanod navigation) |
| SMS / Email | Not used. See below. |

### On SMS and email

Neither is a dependency, and no path through the system requires one.

The sign-in identity is the mobile number, and the auth address derived
from it (`639XXXXXXXXX@auth.smartsumbong.local`) is on a reserved domain
that cannot receive mail — deliberately, so that nothing can be looked
up and nothing enumerated (migration 0021). One consequence is that
Supabase's built-in password reset mails an address that does not exist.

The reset path is therefore in person: the barangay checks an ID at the
counter, the same inspection that approved the account, and issues a
temporary password the resident must change on next sign-in (migrations
0028 and 0029). It costs nothing to run, needs no SMS credit, and works
during an outage.

The admin portal is the one exception. An administrator signs in with a
real email address (`login.php`), not a synthetic one, so Supabase's
built-in recovery mail actually reaches them —
`admin/forgot-password.php` and `admin/reset-password.php` use it.
**This needs one manual step per environment:** add
`<your deployment URL>/admin/reset-password.php` to Supabase Dashboard →
Authentication → URL Configuration → Redirect URLs, or GoTrue will
refuse the recovery link with an unauthorized-redirect error. There is
no equivalent for residents or tanods — see above.

Verification is a human decision that takes minutes to hours. The
pending screen polls rather than waiting on a message.

SMS through Semaphore remains an option and would improve the
experience — it reaches a handset with no data connection, which no
push notification can. It is not built because it carries a per-message
cost against a system specified to run at no ongoing cost, and because
making it a dependency would mean the barangay stops being able to
verify accounts when the load runs out.

## Getting started

```bash
npm install -g supabase
supabase login
supabase link --project-ref <your-project-ref>

# Enable in Dashboard → Database → Extensions first:
#   postgis, pg_cron

supabase db push
psql "$DATABASE_URL" -f supabase/seed.sql

cp .env.example .env    # then fill it in — .env is gitignored
```

Then see `DEPLOY.md` for the admin portal (Render or `run-dev-server.bat`)
and for building the Android app.

## Layout

```
admin/                   PHP admin portal
  dashboard.php            figures for a month (live)
  cases.php, case.php      Case Reports: the list, and one complaint with every
                           admin action (validate, assign, reroute, approve
                           resolution, status, escalate, threads)
  spatial.php              map: pins, heatmap, hotspots
  summary.php              Report Summary + printable PDF
  residents.php,
  personnel.php            accounts (includes/accounts.php)
  retirement-requests.php  Extra Administrative Services (includes/retirement.php)
  includes/                auth, Supabase client, layout, i18n (t(en, fil))
  assets/                  css, js (map-theme.js), map data, vendored libraries
mobile/core/             shared Flutter package (auth, media upload, push, …)
mobile/resident/         the SmartSumbong app — residents, and tanods under
                         lib/tanod/ (dispatch window, navigation, outbox)
supabase/migrations/     0001–0074, applied in order (see docs/schema.md)
supabase/functions/      Edge Functions: delete-account, send-dispatch-push
supabase/seed.sql        SLA guide hours (placeholders) + boundary
docs/schema.md           tables, functions by actor, rules, use-case coverage
docs/chat/               admin ↔ tanod chat: draft schema (not a migration)
DEPLOY.md                portal on Render, database, building the APK
run-dev-server.bat       local portal on http://127.0.0.1:8000/admin/
```

## Conventions

- The actor is **`tanod`**. The word "responder" belongs nowhere in this codebase.
- Reports are **never deleted** — `deleted_at` only. The audit trail is the product.
- Tanod change dispatch state through functions, never direct `UPDATE`.
- SLA guide hours live in `sla_policies` as data, not as constants; the
  deadline itself is set by the admin when assigning.
- Every dispatch is the admin's. Escalation means sending a case to an
  outside office. A tanod's resolution waits for the admin's approval.
- Features put away for later stay in the code behind a switch rather than
  being deleted (`ID_OCR_ENABLED`, `ADMIN_SUCCESSION_ENABLED`, `kIdOcrEnabled`).

## Security

This repository is **public**.

- No real resident names, complaints, or ID images. Seed data is fictional.
- Never commit `.env`. Use Codespaces Secrets.
- `SUPABASE_SERVICE_ROLE_KEY` is server-side only — it bypasses RLS entirely.
- A leaked key must be rotated. Deleting the file does not remove it from history.
