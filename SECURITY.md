# Security

SmartSumbong holds residents' names, mobile numbers, ID photos, selfies,
locations and complaints: personal data under the Data Privacy Act of 2012
(RA 10173). This repository is public; the data is not.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through GitHub:
**Security → Report a vulnerability** on this repository. Include what you
found, how to reproduce it, and what it exposes. You will get an answer
within a few days, and a fix or a plan within two weeks for anything that
exposes personal data.

Please do not test against the live portal or app with real accounts, and do
not access, change or keep anyone's data. A local copy (README, *Getting
started*) or the app's preview mode is enough to show most problems.

## Supported versions

Only `main`, as deployed to https://smartsumbong-ph.onrender.com and the
current APK, receives fixes.

## How the system protects data

**Access**
- Row-level security on every table: a resident sees their own account and
  complaints, a tanod their own dispatches, an admin everything, and an admin
  acts on a case only while handling it.
- Every state change is a database function that checks the caller first. The
  portal calls the database with the signed-in admin's own token; only the
  Edge Functions hold the service-role key.
- Sign-in lockout after repeated failures, counted per account and per
  network address; an optional Turnstile bot check; sessions end on
  suspension or a password reset; idle sign-out on the portal.

**Integrity**
- The complaint and account audit trails are append-only and hash-chained;
  the database can verify that no row was changed or removed.
- Complaints are never deleted.

**Media**
- Uploads are signed (SHA-256) and limited per address; location and camera
  data are stripped before a photo leaves the phone or the server.
- Identity photos are private assets, viewable only through a link signed
  for that viewing; replaced or orphaned ones are deleted after a week.

**The portal**
- A strict Content-Security-Policy with a per-request nonce; no inline event
  handlers; HSTS, `nosniff`, frame and referrer protections; secure session
  cookies; CSRF tokens on every write; outside feeds read through a guard that
  refuses private addresses.

**The app**
- Session tokens in the OS keystore; optional fingerprint or face unlock; no
  live location tracking (a tanod's location is taken at key moments only).

**The repository**
- No real personal data, ever; seed data is fictional.
- `.env`, keystores and `key.properties` are git-ignored. `dart_defines.json`
  and the Firebase configuration are committed and hold only client values
  that are public by design (the Supabase publishable key, Cloudinary's cloud
  name and presets, Firebase's API keys, to be restricted to the app in
  Google Cloud as DEPLOY.md, section 4, describes).
- gitleaks, GitHub secret scanning with push protection, osv-scanner and
  CodeQL run on every pull request and weekly; Dependabot raises security
  updates. GitHub Actions are pinned to commit hashes.

## If something leaks

[docs/INCIDENTS.md](docs/INCIDENTS.md) is the runbook: rotate first, then
investigate; personal data exposed means the Data Protection Officer is told at
once, and the National Privacy Commission within 72 hours where required.
