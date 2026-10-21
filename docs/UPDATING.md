# Keeping the open-source parts up to date

SmartSumbong is built from many open-source pieces. Each kind is updated a
different way, but the rule is the same for all: **a bot or a script says
what is out of date, the update goes in as a pull request, CI checks it, a
person merges it, and the portal goes live on the next Manual Deploy.**
Nothing updates itself in production.

| What | Where it is pinned | Who says it is out of date | How it is updated |
|---|---|---|---|
| GitHub Actions | commit hashes in `.github/workflows/*.yml` | Dependabot, weekly | merge its pull request |
| The portal's Docker base image (PHP, Apache) | `Dockerfile` | Dependabot, weekly | merge its pull request, then Manual Deploy |
| Flutter packages | `mobile/*/pubspec.yaml` and `pubspec.lock` | Dependabot, weekly | merge its pull request; build a new APK |
| PHP libraries (OpenSpout, for the Report Summary spreadsheet) | `admin/composer.json` and `admin/composer.lock` | Dependabot, weekly; CI runs `composer audit` | merge its pull request, then Manual Deploy (the image installs the locked versions) |
| Browser libraries in the portal (MapLibre, supabase-js, Mapillary, fonts) | `admin/assets/vendor/vendor.json` | the **Vendored libraries** workflow, weekly: one issue listing newer versions and known advisories | `python tools/vendor.py fetch <library>`, below |
| Browser-test tools (Playwright, axe-core) | `tests/browser/package-lock.json` | Dependabot, monthly | merge its pull request |
| Supabase CLI | `version:` in the CI, Backup and Deploy workflows | its release notes; the CLI warns locally | change the three pins and the laptop together |
| Edge Functions' imports | versions written in the import (`jsr:@std/assert@1.0.19`) | by hand, when a function is touched | change the version, run `deno test` |
| Database extensions (PostGIS, pg_trgm, pg_cron…) | Supabase manages them | Supabase's dashboard | Supabase upgrades them; a migration only if we need a new one |

Security scanning runs on every pull request and weekly: gitleaks (secrets),
osv-scanner (the lockfiles, `composer.lock` included), CodeQL (the code). The vendored libraries are
checked against OSV by the weekly workflow above, because a copied file has no
lockfile for osv-scanner to read.

## Browser libraries (`admin/assets/vendor`)

The portal has no build step: each library is a file served as it is, so the
strict content-security policy can allow only our own origin. `vendor.json`
records, for every file, the npm package and version it came from, its
licence, how it was made and its SHA-256. CI runs `python3 tools/vendor.py
check` on every push, so a file changed without updating the record fails the
build.

There are three kinds:

- **copy**: the file is published as is (supabase-js's UMD build, MapLibre's
  worker and CSS, the fonts).

      python tools/vendor.py fetch supabase-js          # latest; or name a version
      git diff admin/assets/vendor                      # read what changed
      # open the pages that use it, then commit and open a pull request

  `fetch` downloads from npm, refuses the file if it does not match npm's own
  integrity hash, copies it in and updates `vendor.json`.

- **build**: made from the published files (`maplibre-gl.js` is compiled to a
  classic script). `fetch` checks and unpacks the version and prints the
  steps; the exact command is in the library's README. Then `python
  tools/vendor.py rehash maplibre-gl <version>`.

- **patched**: a published file with a recorded change (`mapillary.js`, see
  its `PATCH.txt`, so the CSP needs no `unsafe-eval`). Apply the same change to
  the new version, then `rehash`.

Which versions to take: patch and minor versions when CI passes and the pages
look right; a major version only after reading its changelog; an advisory the
same week.

## Deploying an update

- **Portal**: merge, then Render → `smartsumbong-ph` → Manual Deploy. The
  image is rebuilt from the Dockerfile, so a new PHP or Apache comes in the same
  way.
- **Database**: a new migration goes in with `supabase db push`; rebuild
  `supabase/baseline/baseline.sql` in the same pull request (see its README).
- **Edge Functions**: Actions → Deploy.
- **App**: a new APK.

## Adding a new open-source piece

1. The licence is permissive (MIT, BSD, Apache-2.0, ISC, CC0, MPL-2.0 for a
   tool we only run). Copyleft and source-available ones are not added; see
   [OPEN_SOURCE_SHORTLIST.md](OPEN_SOURCE_SHORTLIST.md) for the alternatives.
2. It goes in through the matching row above (a browser library is added to
   `vendor.json` with its licence file beside it).
3. It is credited in [OPEN_SOURCE.md](OPEN_SOURCE.md).
