-- 59_api_role_table_rights.sql: the API roles keep only the table rights they use (0181, backend sweep). Signed-out callers read the
-- reference data and nothing else; nobody signed in holds truncate, references or trigger. Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  t record; n integer; ref text[] := array['barangay_boundary', 'barangay_profile', 'complaint_categories', 'complaint_options', 'hazard_zones', 'hotline_groups', 'hotline_numbers', 'wording'];
begin
  -- 1. signed out: select on the reference tables only, no write right on any table (extension tables aside)
  begin
    for t in select c.relname from pg_class c
              where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p')
                and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e') loop
      if has_table_privilege('anon', 'public.' || quote_ident(t.relname), 'insert') or has_table_privilege('anon', 'public.' || quote_ident(t.relname), 'update')
         or has_table_privilege('anon', 'public.' || quote_ident(t.relname), 'delete') or has_table_privilege('anon', 'public.' || quote_ident(t.relname), 'truncate') then
        raise exception 'anon can write %', t.relname;
      end if;
      if has_table_privilege('anon', 'public.' || quote_ident(t.relname), 'select') and not (t.relname = any (ref)) then
        raise exception 'anon can read %', t.relname;
      end if;
    end loop;
    if (select count(*) from unnest(ref) r where has_table_privilege('anon', 'public.' || r, 'select')) <> array_length(ref, 1) then
      raise exception 'anon cannot read one of the reference tables';
    end if;
    execute 'set local role anon';
    select count(*) into n from public.complaint_categories;
    if n = 0 then raise exception 'the signed-out role reads no complaint types'; end if;
    begin perform 1 from public.users; raise exception 'anon read users';
    exception when insufficient_privilege then null; end;
    reset role;
    v_log := v_log || E'\n' || 'ok  signed-out callers read the reference tables and nothing else, and write nothing';
  exception when others then reset role; v_log := v_log || E'\n' || 'FAIL anon: ' || sqlerrm; end;

  -- 2. signed in: no truncate, references or trigger on any table; the ordinary rights are still there
  begin
    for t in select c.relname from pg_class c
              where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
                and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e') loop
      if has_table_privilege('authenticated', 'public.' || quote_ident(t.relname), 'truncate') or has_table_privilege('authenticated', 'public.' || quote_ident(t.relname), 'references')
         or has_table_privilege('authenticated', 'public.' || quote_ident(t.relname), 'trigger') then
        raise exception 'authenticated holds truncate, references or trigger on %', t.relname;
      end if;
    end loop;
    if not has_table_privilege('authenticated', 'public.notifications', 'select') or not has_table_privilege('authenticated', 'public.users', 'update') then
      raise exception 'authenticated lost an ordinary right';
    end if;
    v_log := v_log || E'\n' || 'ok  nobody signed in can truncate a table, reference it or add a trigger to it; select and update are untouched';
  exception when others then v_log := v_log || E'\n' || 'FAIL authenticated: ' || sqlerrm; end;

  -- 3. a table made later starts the same way
  begin
    create table public._sweep_new_table (id integer);
    if has_table_privilege('anon', 'public._sweep_new_table', 'select') or has_table_privilege('authenticated', 'public._sweep_new_table', 'truncate') then
      raise exception 'a new table starts with the wide rights';
    end if;
    drop table public._sweep_new_table;
    v_log := v_log || E'\n' || 'ok  a table made from now on starts without them';
  exception when others then v_log := v_log || E'\n' || 'FAIL new table: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
