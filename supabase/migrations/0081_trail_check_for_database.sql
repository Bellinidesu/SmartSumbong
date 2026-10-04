-- 0081 — 0080's check on who may verify a trail also refused the
-- database's own whole-system check, audit_integrity(), which runs with no
-- signed-in user. A call with no user (audit_integrity, the SQL editor,
-- the service role) is allowed again; a signed-in caller must still be an
-- admin or the complainant.

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
  -- No signed-in user means the database itself (audit_integrity(), the
  -- SQL editor, the service role): allowed, as before 0080.
  if auth.uid() is not null and not (public.is_admin()
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
