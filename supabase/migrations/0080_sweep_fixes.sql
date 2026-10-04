-- 0080 — Two functions the system sweep (5 Oct 2026) found broken on the
-- live database.
--
-- 1. verify_report_trail() has never worked for anyone. It runs with the
--    caller's privileges, but 0016 revoked EXECUTE on
--    status_log_fingerprint() from authenticated, so every call failed with
--    "permission denied". The portal treats the check as optional, so the
--    case page's tamper badge simply never appeared. It is now SECURITY
--    DEFINER (the fingerprint helper resolves as the owner, which is what
--    0016's comment intended) and checks who is asking itself: an admin,
--    or the resident whose complaint it is.
--
-- 2. my_status_log_authors() (0049) is missing from the live database
--    although 0049 is recorded as applied, so the resident app's report
--    page could never show who wrote a timeline note. Recreated as 0049
--    defined it.

set search_path = public, extensions;

create or replace function public.verify_report_trail(p_report uuid)
returns table (
  entry_no   integer,
  logged_at  timestamptz,
  change     text,
  intact     boolean,
  problem    text)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  l       public.status_logs%rowtype;
  v_prev  text := repeat('0', 64);
  v_calc  text;
  n       integer := 0;
begin
  -- Definer (0080) so the revoked fingerprint helper resolves as the
  -- owner, as 0016 intended; who may look is checked here instead.
  if not (public.is_admin()
          or exists (select 1 from public.reports r
                      where r.id = p_report and r.resident_id = auth.uid())) then
    raise exception 'Only an administrator or the complainant may verify this trail';
  end if;

  for l in select * from public.status_logs
            where report_id = p_report
            order by created_at, id loop
    n := n + 1;
    v_calc := encode(
      extensions.digest(v_prev || '|' || public.status_log_fingerprint(l), 'sha256'), 'hex');

    entry_no  := n;
    logged_at := l.created_at;
    change    := coalesce(l.old_status::text, 'filed') || ' → ' || l.new_status::text;
    intact    := (l.entry_hash = v_calc and l.prev_hash = v_prev);
    problem   := case
                   when l.entry_hash is null      then 'No hash recorded'
                   when l.prev_hash  <> v_prev    then 'Chain broken — an earlier entry was changed or removed'
                   when l.entry_hash <> v_calc    then 'This entry was altered after it was written'
                 end;

    return next;
    v_prev := l.entry_hash;
  end loop;
end $$;

revoke execute on function public.verify_report_trail(uuid) from public, anon;
grant  execute on function public.verify_report_trail(uuid) to authenticated;

create or replace function public.my_status_log_authors(p_report_id uuid)
returns table (
  status_log_id uuid,
  author_name   text,
  is_system     boolean)
language sql stable security definer set search_path = public, extensions as $$
  select sl.id,
         u.full_name,
         sl.is_system
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
   where sl.report_id = p_report_id
     and r.resident_id = auth.uid()
$$;

revoke execute on function public.my_status_log_authors(uuid) from public, anon;
grant  execute on function public.my_status_log_authors(uuid) to authenticated;
