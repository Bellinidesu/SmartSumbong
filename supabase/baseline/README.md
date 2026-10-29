# Baseline: the whole schema in one file

`baseline.sql` is what applying every migration in `supabase/migrations`
produces, as a single file: about 19,700 lines instead of 128 migration
files (0001–0144), with the history between them gone. Use it to read the current schema, or to
start a **new** Supabase project without replaying every migration.

It is generated, never edited. After adding a migration, rebuild it:

    bash supabase/baseline/build.sh        # needs a local PostgreSQL with PostGIS and pg_cron

or, with no local PostgreSQL, push a branch named `baseline-*` (or run
Actions → Rebuild baseline by hand) and commit the `baseline` artifact it
produces. CI's "The baseline still matches the migrations" fails until the
baseline is current.

The script applies the migrations to a throwaway local database, dumps the
result, loads that dump into a second clean database, and only succeeds if
both databases match (every function body and grant, column, policy,
index, constraint, trigger, realtime table, scheduled job and seeded row)
and every check in `supabase/tests` passes on the baseline.

The live project keeps its migrations: `supabase db push` still applies new
numbered files from `supabase/migrations`, and nothing there is deleted.
The header of `baseline.sql` shows how to start a new project from it.
