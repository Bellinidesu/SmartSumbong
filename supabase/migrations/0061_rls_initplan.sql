-- =============================================================
-- SmartSumbong — 0061 Evaluate auth.uid() / is_admin() once per
--                     query in RLS, not once per row
--
-- Every policy in public (35 of them, 0003 onward) calls auth.uid() and
-- public.is_admin() bare. Postgres re-evaluates a bare function call for
-- each row the policy checks; is_admin() is a security definer SQL
-- function, so it cannot be inlined and costs a users lookup per row.
-- Wrapped as a scalar subquery — (select auth.uid()) — the planner runs
-- it once as an initplan and reuses the value. Same result, since both
-- are stable within a statement; this is Supabase's own documented
-- pattern (advisor lint 0003_auth_rls_initplan).
--
-- HOW. Not a hand-written drop/create of 35 policies: that would restate
-- every policy from the migration files, and any drift between those
-- files and the live database would be silently written back. Instead
-- this reads pg_policies at apply time and rewrites each policy's own
-- deparsed USING / WITH CHECK text in place with ALTER POLICY, which
-- keeps the name, command (select/insert/update/all), roles and
-- permissive/restrictive setting exactly as they are. Only two textual
-- forms change:
--
--   auth.uid()                     -> ( SELECT auth.uid() AS uid)
--   is_admin() / public.is_admin() -> ( SELECT public.is_admin() AS is_admin)
--
-- A call already wrapped (preceded by "SELECT ") or part of a longer
-- name (preceded by a word character or a dot) is left alone, so this is
-- safe to run twice. The block raises — rolling the whole migration
-- back — if any bare call is left afterwards.
-- =============================================================

set search_path = public, extensions;

do $$
declare
  p          record;
  v_qual     text;
  v_check    text;
  v_changed  int := 0;
  v_left     int;
  c_uid  constant text := '(?<!SELECT )(?<![\w.])auth\.uid\(\)';
  c_adm  constant text := '(?<!SELECT )(?<![\w.])(public\.)?is_admin\(\)';
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
  loop
    v_qual  := regexp_replace(
                 regexp_replace(p.qual, c_uid, '( SELECT auth.uid() AS uid)', 'g'),
                 c_adm, '( SELECT public.is_admin() AS is_admin)', 'g');
    v_check := regexp_replace(
                 regexp_replace(p.with_check, c_uid, '( SELECT auth.uid() AS uid)', 'g'),
                 c_adm, '( SELECT public.is_admin() AS is_admin)', 'g');

    if v_qual is distinct from p.qual then
      execute format('alter policy %I on %I.%I using (%s)',
                     p.policyname, p.schemaname, p.tablename, v_qual);
    end if;
    if v_check is distinct from p.with_check then
      execute format('alter policy %I on %I.%I with check (%s)',
                     p.policyname, p.schemaname, p.tablename, v_check);
    end if;
    if v_qual is distinct from p.qual or v_check is distinct from p.with_check then
      v_changed := v_changed + 1;
    end if;
  end loop;

  select count(*) into v_left
    from pg_policies
   where schemaname = 'public'
     and (   (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ c_uid
          or (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ c_adm);
  if v_left > 0 then
    raise exception '0061: % policies still call auth.uid()/is_admin() per row', v_left;
  end if;

  raise notice '0061: rewrote % policies', v_changed;
end $$;

-- Verification. Run separately.
--
--   -- 1. Nothing bare left; expect 0.
--   select count(*) as bare_calls_left
--     from pg_policies
--    where schemaname = 'public'
--      and (coalesce(qual, '') || ' ' || coalesce(with_check, ''))
--          ~ '(?<!SELECT )(?<![\w.])(auth\.uid|(public\.)?is_admin)\(\)';
--
--   -- 2. Same number of policies as before; expect 35 (the count
--   --    through 0060), and eyeball that each reads as it did.
--   select tablename, policyname, cmd, roles, qual, with_check
--     from pg_policies where schemaname = 'public'
--    order by tablename, policyname;
--
--   -- 3. The planner now uses an initplan; expect "InitPlan" in the plan
--   --    and no per-row is_admin() in the filter. Run as a signed-in
--   --    resident (or `set local role authenticated` with a jwt claim):
--   explain select id from public.reports;
