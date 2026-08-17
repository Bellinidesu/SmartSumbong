-- 0027_dispatch_rpc_grants.sql
--
-- Closes a gap left by 0016.
--
-- 0016 went through the dispatch helpers and revoked EXECUTE from
-- public and anon, then re-granted to authenticated — my_role(),
-- nearest_available_tanod(), assignable_tanods(), location_is_fresh(),
-- is_within_barangay(). Its stated reason was defence in depth: if a
-- later migration or a console session weakens a caller check, the
-- grant should not already be sitting there waiting.
--
-- The three functions a tanod actually calls to change a dispatch were
-- not in that pass, so they still carry Postgres's default of EXECUTE
-- to PUBLIC:
--
--   accept_dispatch(uuid)
--   reroute_dispatch(uuid, text, uuid)
--   submit_field_report(uuid, text)
--
-- Nothing is exploitable today. All three are security definer and
-- every one scopes its write to `tanod_id = auth.uid()`, so an
-- anonymous call finds no row and raises. But that is one check
-- standing between anon and three dispatch mutators, and it is the same
-- shape of reliance 0016 was written to remove.
--
-- No behaviour changes for any legitimate caller. A tanod holds the
-- authenticated role and keeps EXECUTE.

begin;

revoke execute on function public.accept_dispatch(uuid)
  from public, anon;
revoke execute on function public.reroute_dispatch(uuid, text, uuid)
  from public, anon;
revoke execute on function public.submit_field_report(uuid, text)
  from public, anon;

grant execute on function public.accept_dispatch(uuid)
  to authenticated;
grant execute on function public.reroute_dispatch(uuid, text, uuid)
  to authenticated;
grant execute on function public.submit_field_report(uuid, text)
  to authenticated;

commit;

-- ---------------------------------------------------------------
-- VERIFY. "Success. No rows returned" proves nothing here: a revoke on
-- a grant that was never explicit succeeds silently either way. Run
-- this and read the result.
--
--   select p.proname,
--          coalesce(has_function_privilege('anon', p.oid, 'execute'),
--                   false) as anon_can_execute,
--          coalesce(has_function_privilege('authenticated', p.oid,
--                                          'execute'), false)
--            as authenticated_can_execute
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('accept_dispatch', 'reroute_dispatch',
--                        'submit_field_report')
--    order by p.proname;
--
-- Expect three rows, anon_can_execute false, authenticated_can_execute
-- true. If anon still reads true, the signature in the revoke does not
-- match the deployed function — check pg_get_function_identity_arguments
-- for the real argument list rather than assuming this file is right.
-- ---------------------------------------------------------------
