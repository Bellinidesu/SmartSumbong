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
| Backend | Supabase — PostgreSQL, Realtime, Edge Functions, Auth, RLS |
| GIS | PostGIS, Leaflet.js, OpenStreetMap |
| Admin portal | PHP + Bootstrap 5 |
| Mobile client | Flutter (web prototype first) |
| Media | Cloudinary (live), barangay server (cold archive) |
| Push / SMS / Email | FCM · Semaphore PH · Resend |

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

## Layout

```
supabase/migrations/   0001 schema · 0002 dispatch & SLA · 0003 RLS
                       0004 realtime & signup bridge · 0005 PostGIS proximity
                       0006 dispatch lifecycle · 0007 awaiting-unit queue
                       0008 reroute guard · 0009 admin manual dispatch
                       0010 barangay-owned settings · 0011 admin case review
                       0012 dashboard metrics · 0013 account management
                       0014 admin succession · 0015 audit integrity
                       0016 security hardening
supabase/seed.sql      SLA policy windows (placeholders) + boundary
LICENSE                use grant, reserved rights, PUP interest
docs/schema.md         schema reference, function map, use case coverage
docs/deployment.md     fresh install and first-admin bootstrap
docs/turnover.md       account ownership, break-glass, succession, known gaps
docs/manual.md         admin portal guide for barangay staff
admin/                 PHP admin portal (login, cases, case, dashboard, logout)
```

## Conventions

- The actor is **`tanod`**. The word "responder" belongs nowhere in this codebase.
- Reports are **never deleted** — `deleted_at` only. The audit trail is the product.
- Tanod change dispatch state through functions, never direct `UPDATE`.
- SLA windows live in `sla_policies` as data, not as constants.

## Security

This repository is **public**.

- No real resident names, complaints, or ID images. Seed data is fictional.
- Never commit `.env`. Use Codespaces Secrets.
- `SUPABASE_SERVICE_ROLE_KEY` is server-side only — it bypasses RLS entirely.
- A leaked key must be rotated. Deleting the file does not remove it from history.
