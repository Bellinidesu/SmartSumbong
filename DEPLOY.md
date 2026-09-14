# Deploying for the Sep 29–30 defense

This is the defense deploy, not turnover — same Supabase project you've been
using all along, just the admin portal + public dashboard put somewhere with
a real URL instead of `run-dev-server.bat` on your laptop. Free, no card.

## 1. Push these files, then connect the repo to Render

New this pass: `Dockerfile`, `docker-entrypoint.sh`, `.dockerignore`, root
`index.php` (landing page), updated `.htaccess`.

```
git add Dockerfile docker-entrypoint.sh .dockerignore index.php .htaccess \
        .gitignore mobile/tanod/.gitignore
git commit -m "Add Docker deploy for the Sep 29-30 defense"
git push
```

Then on [render.com](https://render.com) (sign up with GitHub, no card
needed):

1. **New +** → **Web Service** → connect the `Bellinidesu/SmartSumbong`
   repo.
2. Runtime: Render should auto-detect the `Dockerfile`. If it asks, pick
   **Docker**, root directory blank (repo root).
3. Instance type: **Free**.
4. **Environment** tab → add:
   - `SUPABASE_URL` = your project's URL (same one in your current `.env`)
   - `SUPABASE_ANON_KEY` = your current anon/publishable key
   (`config.php` already reads these straight from the environment — no
   code change needed, and nothing here is a new secret, it's the same
   publishable key already in the mobile apps.)
5. **Create Web Service.** First build takes a few minutes (installing
   `curl`/`mbstring`, enabling `mod_rewrite`). You get a URL like
   `https://smartsumbong.onrender.com`.

## 2. One Supabase setting to update

Dashboard → **Authentication → URL Configuration → Redirect URLs** → add:

```
https://<your-render-url>/admin/reset-password.php
```

Without this, admin "forgot password" emails link back to a URL Supabase
refuses (`admin/forgot-password.php` / `reset-password.php` already assume
this — see the README's note on it). Nothing else needs to change — the
mobile apps talk to Supabase directly and don't go through this portal.

## 3. What "activatable on phone" actually looks like

Free Render web services sleep after 15 minutes idle and wake on the next
request — about a 1-minute cold start. In practice: open the URL from your
phone a few minutes before you need it (checking the dashboard, whatever),
and it's warm for the actual defense. If it's asleep when a panelist opens
it cold, the first load just takes a beat longer — nothing breaks.

One consequence: admin login sessions don't survive a sleep/wake cycle
(the container restarts, so PHP's session store resets). If the portal
goes idle for 15+ minutes mid-defense, whoever's logged into `admin/` will
need to log in again. Worth mentioning to whoever's driving the portal so
it doesn't look like a bug live.

## 4. Fallback

`run-dev-server.bat` still works exactly as before if you ever need to
demo fully offline (venue wifi dies, etc.) — nothing about this deploy
changes the local path, it's purely additive.

## Not done here (deliberately, since this isn't turnover)

- No fresh Supabase project — reusing the current one, per the existing
  plan to spin up a clean project after the mock defense.
- Didn't touch the `Claude outputs/` or `mobile/tanod/drop/` gitignore
  gaps' *existing tracked state* — the new `.gitignore` lines stop them
  from being committed going forward, but if either was ever already
  committed, `git rm -r --cached "Claude outputs" mobile/tanod/drop` clears
  it out (run that once, separately, whenever — not blocking for the 29th).
