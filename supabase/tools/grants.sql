-- What a signed-out caller (anon) and a signed-in one (authenticated) may do with every function, table, view and sequence in
-- public: one line each. supabase/tools/grants.sh prints this for a database, and compares it with supabase/grants.txt.
-- Effective rights (a grant to PUBLIC counts), so the lines say what the API will actually allow.
select line from (
  select 'fn ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
         || ' anon=' || case when has_function_privilege('anon', p.oid, 'execute') then 'call' else '-' end
         || ' authenticated=' || case when has_function_privilege('authenticated', p.oid, 'execute') then 'call' else '-' end as line
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select case c.relkind when 'v' then 'view ' when 'm' then 'view ' else 'table ' end || c.relname
         || ' anon=' || coalesce(nullif(concat_ws(',',
              case when has_table_privilege('anon', c.oid, 'select') then 'select' end,
              case when has_table_privilege('anon', c.oid, 'insert') then 'insert' end,
              case when has_table_privilege('anon', c.oid, 'update') then 'update' end,
              case when has_table_privilege('anon', c.oid, 'delete') then 'delete' end,
              case when has_table_privilege('anon', c.oid, 'truncate') then 'truncate' end,
              case when has_table_privilege('anon', c.oid, 'references') then 'references' end,
              case when has_table_privilege('anon', c.oid, 'trigger') then 'trigger' end), ''), '-')
         || ' authenticated=' || coalesce(nullif(concat_ws(',',
              case when has_table_privilege('authenticated', c.oid, 'select') then 'select' end,
              case when has_table_privilege('authenticated', c.oid, 'insert') then 'insert' end,
              case when has_table_privilege('authenticated', c.oid, 'update') then 'update' end,
              case when has_table_privilege('authenticated', c.oid, 'delete') then 'delete' end,
              case when has_table_privilege('authenticated', c.oid, 'truncate') then 'truncate' end,
              case when has_table_privilege('authenticated', c.oid, 'references') then 'references' end,
              case when has_table_privilege('authenticated', c.oid, 'trigger') then 'trigger' end), ''), '-')
         || ' rls=' || case when c.relrowsecurity then 'on' else 'off' end
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p')
     and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e')
  union all
  select 'seq ' || c.relname
         || ' anon=' || coalesce(nullif(concat_ws(',',
              case when has_sequence_privilege('anon', c.oid, 'usage') then 'usage' end,
              case when has_sequence_privilege('anon', c.oid, 'select') then 'select' end,
              case when has_sequence_privilege('anon', c.oid, 'update') then 'update' end), ''), '-')
         || ' authenticated=' || coalesce(nullif(concat_ws(',',
              case when has_sequence_privilege('authenticated', c.oid, 'usage') then 'usage' end,
              case when has_sequence_privilege('authenticated', c.oid, 'select') then 'select' end,
              case when has_sequence_privilege('authenticated', c.oid, 'update') then 'update' end), ''), '-')
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'S'
     and not exists (select 1 from pg_depend e where e.objid = c.oid and e.deptype = 'e')
) x
