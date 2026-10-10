# Baseline: the whole schema in one file

`baseline.sql` is what applying every migration in `supabase/migrations`
produces, as a single file: about 10,300 lines instead of 109 files, with
the history between them gone. Use it to read the current schema, or to
start a **new** Supabase project without replaying every migration.

It is generated, never edited. After adding a migration:

    bash supabase/baseline/build.sh

The script applies the migrations to a throwaway local database, dumps the
result, loads that dump into a second clean database, and only succeeds if
both databases match (every function body and grant, column, policy,
index, constraint, trigger, realtime table, scheduled job and seeded row)
and every check in `supabase/tests` passes on the baseline.

The live project keeps its migrations: `supabase db push` still applies new
numbered files from `supabase/migrations`, and nothing there is deleted.
The header of `baseline.sql` shows how to start a new project from it.
