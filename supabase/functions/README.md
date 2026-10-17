# Edge Functions

The five Deno functions the database and the app call. Each folder holds a
`handler.ts` (the logic), a `handler.test.ts` (its tests, with every outside
call stubbed through `_test/stub.ts`) and an `index.ts` that only serves the
handler. `_shared/log.ts` records failures where Settings → System status
shows them.

| Function | JWT check | Called by | Does | Secrets |
|---|---|---|---|---|
| `send-dispatch-push` | on | the Database Webhook on `notifications` inserts | sends the phone banner over FCM's HTTP v1 API, reading the notification as stored | `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`; optional `PUSH_WEBHOOK_SECRET` |
| `sign-upload` | off (checks its own) | the app | signs Cloudinary uploads (SHA-256) within per-address limits; signs a viewing link for the caller's own private ID photo | `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` |
| `password-otp` | off (the caller is signed out) | the app | SMS codes for a forgotten password and for moving to a new number: hashed, 10 minutes, 5 tries, 3 an hour | `SEMAPHORE_API_KEY` |
| `delete-account` | on | the app | finishes the caller's own account deletion with GoTrue's Admin API | — |
| `media-cleanup` | off (a shared secret) | pg_cron, daily | deletes identity photos from Cloudinary a week after nothing uses them | `MEDIA_CLEANUP_SECRET`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` |

Every function also gets `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` from Supabase. The JWT settings are pinned in
`../config.toml`; never run `supabase config push` from it.

```bash
deno check supabase/functions/*/index.ts
deno lint supabase/functions
deno test --allow-env supabase/functions
```

Deploy with Actions → Deploy, or one at a time:
`supabase functions deploy <name> --project-ref <ref> --use-api`. Push the
migrations a function relies on first. Setup of the secrets, the webhook and
the Vault entries: [DEPLOY.md](../../DEPLOY.md), section 2.
