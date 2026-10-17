# Contributing to SmartSumbong

How changes are made to this repository. It is short on purpose: the rules
below are the ones CI cannot check for you, plus the ones it can, so nothing
surprises you at review.

## The flow

1. **Branch from `main`.** One branch per change, named for it
   (`case-page-paging`, `deps-notifications`). `main` is the only permanent
   branch; `bellinist` holds the parked 3D City work and is not merged.
2. **Make the change, then run the checks** that apply (below).
3. **Open a pull request** to `main`. The description says what changed, why,
   and how it was checked. CI and the Security workflow run on it.
4. **Squash-merge** when every check is green. The PR title becomes the commit
   subject on `main`, so write it as one (see *Commit messages*). The branch
   deletes itself.
5. **Ship it.** Portal: Render → Manual Deploy. Database or Edge Functions:
   Actions → Deploy (backup first). App: build and hand out the APK.
   [docs/OPERATIONS.md](docs/OPERATIONS.md) has the details.

## Checks to run before pushing

| You changed | Run |
|---|---|
| anything in `admin/` | `php -l` on changed files, `node --check` on changed scripts, `php .github/scripts/i18n-check.php`, `bash .github/scripts/perf-budget.sh`, `bash .github/scripts/portal-smoke.sh` |
| `mobile/core` or `mobile/resident` | `flutter analyze` and `flutter test` in each package you touched |
| `supabase/functions` | `deno check supabase/functions/*/index.ts && deno lint supabase/functions && deno test --allow-env supabase/functions` |
| `supabase/migrations` | `bash supabase/tests/local/run-local.sh` if you have PostgreSQL; then rebuild the baseline (push a `baseline-*` branch, or run `bash supabase/baseline/build.sh`) |

CI runs all of these anyway; running them first saves a round trip.

## Rules the code keeps

**Database**
- A schema change is a **new numbered migration**. Never edit one that has
  been applied; fix it with the next number.
- Every state change is a function that also writes the audit trail and the
  notifications. No bare `UPDATE` from a client.
- New tables get row-level security; policies use `(select auth.uid())`; every
  foreign key gets an index.
- Complaints are never deleted (`deleted_at`).
- Add a rolled-back check in `supabase/tests` for new behaviour.

**Portal**
- **No inline event handlers or inline scripts without the nonce**: the
  Content-Security-Policy refuses them. Use `data-autosubmit`,
  `data-native-confirm` or `data-confirm` (`admin/assets/js/p.js`), or a script
  file. A new outside service goes into the policy in `admin/includes/config.php`.
- **Every string in both languages**: `t('English', 'Tagalog')`.
- Escape everything shown: `e()` in PHP, `esc()`/`textContent` in scripts.
- Keep within the size budgets; raise one only on purpose, in the PR that needs it.

**App**
- `flutter analyze` must report nothing.
- Never put a secret in `dart_defines.json`: it is committed and ships in the APK.

**Everywhere**
- The actor is **tanod**, never "responder".
- Names are stored "Last, First" and shown First Last (`display_name()`).
- Features put away for later stay behind a switch rather than being deleted.
- Never commit `.env`, keystores or `key.properties`. Push protection will
  stop a recognised key; do not work around it, move the key out.
- Match the code around you: its naming, its comment density, its idiom.
  Comments say *why*, and date a decision when the date matters
  ("(Rose, 30 Sep 2026)").

**Design**
- Screens follow the Figma file 1:1; behaviour does not change in a visual pass.
- Every change is balanced and aligned: equal widths for paired buttons, one
  spacing rhythm per screen, both themes and both languages checked.

## Commit messages

The history on `main` is one squash commit per pull request, so the PR title
is the commit subject.

```
Area: what changed, in plain words (#PR)

Why it changed and anything a reader of `git log` needs: the cause of a bug,
the trade-off taken, what was checked. Wrap at about 72 columns.

Co-Authored-By: Name <email>        (when someone else, or an AI assistant, wrote part of it)
```

- **Area** is what a reader would look for: `Portal`, `App`, `Case page`,
  `Spatial Distribution`, `SMART`, `Workspace widgets`, `CI`, `Docs`, a
  migration number (`0132:`).
- Say what changed for the people using it, not which functions moved:
  "Case Reports: a possible duplicate stays inside the SMART column", not
  "fix css".
- One change per commit. A sweep of small fixes says so ("Symmetry sweep").
- The template is in `.github/gitmessage.txt`; use it with
  `git config commit.template .github/gitmessage.txt`.

## Documentation

When behaviour changes, update the document that describes it in the same
pull request: [README](README.md), [DEPLOY](DEPLOY.md) for configuration,
[docs/](docs/) for the rest, and [CHANGELOG](CHANGELOG.md) under *Unreleased*.
