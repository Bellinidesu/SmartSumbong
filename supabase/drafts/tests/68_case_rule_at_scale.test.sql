-- 68_case_rule_at_scale.sql (DRAFT test for 0189; move to supabase/tests/ when Ace says "apply 0189"). Rolled back.
-- Fails before 0189 (the policies still call the case rule once per row) and passes after it. The behaviour itself is pgTAP 67's.
do $sweep$
declare
  v_log text := 'setup ok';
  s text; n int;
begin
  -- 1. no read policy runs the case rule per row any more (the two INSERT checks run once per inserted row and are left as they were)
  begin
    select string_agg(tablename || '.' || policyname, ', ' order by 1) into s from pg_policies
     where schemaname = 'public' and cmd = 'SELECT'
       and (qual ~ '(admin_sees_report|admin_sees_case|admin_sees_dispatch|_admin_sees_user|_user_sees_case)\(');
    if s is not null then raise exception 'still per row: %', s; end if;
    v_log := v_log || E'\n' || 'ok  no read policy calls the per-row case functions (the caller''s facts are read once per query)';
  exception when others then v_log := v_log || E'\n' || 'FAIL per row: ' || sqlerrm; end;

  -- 2. the helpers: security definer, search_path pinned, stable, signed-in callers only; the per-case functions the guards use are still there
  begin
    select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('_my_committee', '_my_categories', '_my_concern_case_ids', '_my_handled_case_ids', '_my_scoped_case_ids', '_my_scoped_dispatch_ids', '_my_scoped_resident_ids')
       and p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=public']
       and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
    if n <> 7 then raise exception 'only % of 7 helpers are definer + stable + pinned + signed-in only', n; end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_user_sees_case', 'admin_sees_report', 'admin_sees_case', 'admin_sees_dispatch', '_admin_sees_user')) <> 5 then
      raise exception 'a per-case function the guards and notices use is gone'; end if;
    v_log := v_log || E'\n' || 'ok  the 7 helpers are security definer, stable, search_path pinned, for signed-in callers only; the per-case functions remain';
  exception when others then v_log := v_log || E'\n' || 'FAIL helpers: ' || sqlerrm; end;

  -- 3. a signed-out caller and a resident get nothing from the helpers (each returns only what the caller may already read)
  begin
    perform set_config('request.jwt.claim.sub', coalesce((select id::text from public.users where role = 'resident' limit 1), gen_random_uuid()::text), true);
    execute 'set local role authenticated';
    if exists (select 1 from public._my_scoped_case_ids()) or exists (select 1 from public._my_scoped_resident_ids())
       or cardinality(public._my_categories()) > 0 or public._my_committee() is not null then
      raise exception 'a resident got a case set'; end if;
    execute 'reset role';
    v_log := v_log || E'\n' || 'ok  a resident gets an empty case set, no committee and no categories';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL resident: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
