# Where every secret lives, and how to get it back (15 Nov 2026)

Nothing that matters lives only on one person's computer. The project runs on a few accounts (GitHub, Supabase, Render, Google/Firebase, Cloudinary, Resend,
Semaphore); each secret lives in the system that uses it, and every one but the app's signing key can be re-issued from its provider's dashboard.

| Secret | Lives in | If it is lost |
|---|---|---|
| App signing key (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) | GitHub → Settings → Environments → `release` (secrets; usable only from `main`, unreadable once saved) | **Not recoverable.** Android accepts an update only when it is signed by the same key. A new key means every phone must uninstall and reinstall the app. |
| Supabase secret and service-role keys | Supabase dashboard → Project Settings → API keys | Create new keys there, update the places that use them (Edge Function secrets). |
| Edge Function secrets (`FCM_*`, `VAPID_*`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM_NAME`, `SEMAPHORE_API_KEY`, `PUSH_WEBHOOK_SECRET`, `MEDIA_CLEANUP_SECRET`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`) | Supabase → Edge Functions → Secrets (names and digests only are visible) | Re-issue at the provider and `supabase secrets set`. A new `VAPID` pair means browsers turn alerts on again. |
| Firebase push credentials (`FCM_PRIVATE_KEY`) | Supabase secret; the service account is in Google Cloud → IAM → Service accounts → `firebase-adminsdk-fbsvc` → Keys | Create a new key there, set the secret, delete the old key. Rotated 15 Nov 2026; the old keys are deleted. |
| Portal settings (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `CLOUDINARY_*`, `MAPILLARY_TOKEN`, `VAPID_PUBLIC_KEY`) | Render → smartsumbong-ph → Environment | Re-enter from the providers. The portal holds no Supabase secret key. |
| CI (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BACKUP_PASSPHRASE`) | GitHub → Settings → Secrets and variables → Actions | Re-issue and re-enter. Keep `BACKUP_PASSPHRASE` somewhere you will find it: it opens the nightly database backups. |

## The Gmail app password (`SMTP_PASS`, 17 Nov 2026)

`password-otp` emails reset and confirming codes from one Gmail account
(`SMTP_USER`). `SMTP_PASS` is a Gmail **app password** for it: 16 letters,
made at <https://myaccount.google.com/apppasswords> (2-Step Verification must
be on), shown once. It can only send and read mail as that account; it cannot
change the account's password or settings. It lives only in Supabase's
function secrets (set it with `supabase secrets set`, DEPLOY.md, "Forgot
password by email"); keep no other copy. If it leaks or is lost, revoke it on
the same Google page, make a new one and set the secret again; nothing else
changes. Changing the Google account's own password also revokes every app
password, so set a new one after any such change.

## Firebase API keys

The three Firebase client keys (Android, iOS, Browser) are public by design but restricted (15 Nov 2026): the Android key to `ph.smartsumbong.resident` signed with
the release certificate, the iOS key to that bundle id, the Browser key to the portal's own sites. Debug builds of the app (`flutter run`) are not allowed by the
Android key on purpose; to test one, add the debug certificate to the key in Google Cloud → Credentials.

## Releasing the app

See DEPLOY.md section 7: Actions → "Build signed APK" → Run workflow. The job refuses any APK that is not signed by the certificate with SHA-1
`8C:AD:8F:D8:04:19:77:2C:FC:86:6A:8F:2E:23:D0:FD:DA:44:0E:25`.

## Known gap (to close after the defense)

GitHub does not let anyone read a secret back, so the signing key now exists in one place. If the repository, the `release` environment or the account that owns
them is lost, the key is gone with it. The fix is a sealed copy kept by the client's own administrator in their password manager; it is not set up yet.
