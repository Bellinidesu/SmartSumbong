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
| Push | FCM (planned) |
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
