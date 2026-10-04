-- 0082 — The complaint trail's hash chain, made exact (system sweep,
-- 5 Oct 2026).
--
-- audit_integrity() reported 16 "broken" entries out of 23,800. None was
-- tampering; no migration has ever deleted a trail row. Two flaws made
-- honest entries look broken:
--
-- 1. Entries written in the same transaction share created_at (now() is
--    fixed per transaction). The chain trigger picked "the latest entry" by
--    created_at, then id, and the id is random, so the next entry could
--    link to the wrong one. The checker walked in the same random order.
--
-- 2. Two transactions writing to the same complaint at once (the dispatch
--    retry sweep against an admin action, for instance) both read the same
--    latest entry and linked to it, forking the chain.
--
-- From now on each complaint's trail is written one entry at a time (a
-- transaction-scoped advisory lock), and a new entry links to the head of
-- the chain: the entry nothing links to yet. Existing entries cannot be
-- rewritten (the table is immutable by design), so the checker now asks
-- the questions that matter for tampering, in any order:
--   * does this entry's hash still match its own content and link? (an
--     edited entry fails), and
--   * does the entry it links to still exist? (a deleted entry breaks
--     its successor's link).
-- Same-moment entries and old forks no longer read as broken.

set search_path = public, extensions;

create index if not exists status_logs_prev_idx on public.status_logs (report_id, prev_hash);

create or replace function public.chain_status_log()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_prev text;
begin
  -- One writer per complaint trail at a time.
  perform pg_advisory_xact_lock(hashtextextended('status_logs:' || new.report_id::text, 0));

  -- The head: the newest entry no other entry links to yet.
  select s.entry_hash into v_prev
    from public.status_logs s
   where s.report_id = new.report_id
     and not exists (select 1 from public.status_logs t
                      where t.report_id = s.report_id and t.prev_hash = s.entry_hash)
   order by s.created_at desc, s.id desc
   limit 1;

  new.prev_hash  := coalesce(v_prev, repeat('0', 64));
  new.entry_hash := encode(
    extensions.digest(new.prev_hash || '|' || public.status_log_fingerprint(new), 'sha256'), 'hex');
  return new;
end $$;

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
  v_calc  text;
  v_known boolean;
  n       integer := 0;
begin
  -- No signed-in user is the database itself (audit_integrity(), the SQL
  -- editor, the service role); a signed-in caller must be an admin or the
  -- complainant (0080/0081).
  if auth.uid() is not null and not (public.is_admin()
          or exists (select 1 from public.reports r
                      where r.id = p_report and r.resident_id = auth.uid())) then
    raise exception 'Only an administrator or the complainant may verify this trail';
  end if;

  for l in select * from public.status_logs
            where report_id = p_report
            order by created_at, id loop
    n := n + 1;
    v_calc := case when l.prev_hash is null then null
                   else encode(digest(l.prev_hash || '|' || public.status_log_fingerprint(l), 'sha256'), 'hex') end;
    v_known := l.prev_hash = repeat('0', 64)
               or exists (select 1 from public.status_logs p
                           where p.report_id = p_report and p.entry_hash = l.prev_hash);

    entry_no  := n;
    logged_at := l.created_at;
    change    := coalesce(l.old_status::text, 'filed') || ' → ' || l.new_status::text;
    intact    := l.entry_hash is not null and l.entry_hash = v_calc and v_known;
    problem   := case
                   when l.entry_hash is null then 'No hash recorded'
                   when l.entry_hash <> v_calc then 'This entry was altered after it was written'
                   when not v_known then 'Chain broken — the entry before this one was changed or removed'
                 end;
    return next;
  end loop;
end $$;

revoke execute on function public.verify_report_trail(uuid) from public, anon;
grant  execute on function public.verify_report_trail(uuid) to authenticated;

comment on function public.verify_report_trail(uuid) is
  'Checks one complaint''s hash chain (0082): every entry''s hash matches '
  'its content and link, and the entry it links to still exists. Admins, '
  'the complainant, or the database itself.';
