-- 0181: the API roles keep only the table rights they use (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0181". Regenerate supabase/grants.txt after it (grants.sh write): about 100 lines change.
--
-- Supabase grants anon and authenticated ALL rights (select, insert, update, delete, truncate, references, trigger) on every table
-- made in public, and row level security is the only guard. The live project agrees with supabase/grants.txt, so this is what the
-- migrations built, not drift. It works because every table has RLS on and the signed-out role has no policy beyond the reference
-- tables, but it leaves two things wider than the system needs:
--   * signed-out callers hold write rights on ~100 tables (a mis-written policy for `public` would be enough to open one);
--   * both roles hold TRUNCATE (which ignores RLS), REFERENCES and TRIGGER. PostgREST never issues them, so nothing uses them.
--
-- After this:
--   anon           select on the tables that have a policy for the signed-out role (the reference data: the barangay profile and
--                  boundary, complaint types and options, hazard zones, hotlines, wording), nothing else, no sequences
--   authenticated  select, insert, update, delete as before (later migrations narrow those table by table: 0177, 0178);
--                  no truncate, references or trigger

set search_path = public, extensions;

do $$
declare t record;
begin
  -- the tables the signed-out role reads: whatever has a policy for it (a policy for PUBLIC counts)
  create temporary table _anon_reads on commit drop as
    select distinct c.relname
      from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relnamespace = 'public'::regnamespace and p.polcmd in ('r', '*')
       and (p.polroles = '{0}'::oid[] or exists (select 1 from pg_roles r where r.oid = any (p.polroles) and r.rolname = 'anon'));

  for t in select c.relname, c.relkind from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') loop
    execute format('revoke all on public.%I from anon', t.relname);
    execute format('revoke truncate, references, trigger on public.%I from authenticated', t.relname);
    if exists (select 1 from _anon_reads a where a.relname = t.relname) then
      execute format('grant select on public.%I to anon', t.relname);
    end if;
  end loop;
end $$;

revoke all on all sequences in schema public from anon;

-- tables made from now on start without the signed-out role's rights and without truncate, references and trigger for the signed-in one
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
