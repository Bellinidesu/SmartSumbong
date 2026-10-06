-- 0099 — What a resident's timeline says (7 Oct 2026, found testing on a phone).
--
-- The resident app labelled every entry by an admin "TANOD <name>", and
-- showed staff-only notes word for word: which tanod was sent, how many
-- metres away, "SLA breach", "Re-dispatching ... (offer 1 of 3)". Residents
-- see the barangay as one body (as in the chat), so both functions now
-- also return the author's role and a resident_remark: the same note with
-- staff details replaced by plain wording. The stored history is unchanged
-- (it is tamper-checked); only what is shown to the resident differs.

create or replace function public.resident_remark(p_remark text, p_is_system boolean)
returns text language sql immutable set search_path = public as $$
  select case
    when p_remark is null or btrim(p_remark) = '' then null
    when p_remark ~* '^(auto-dispatched|manually assigned)' then 'A tanod was assigned to your report.'
    when p_remark ~* '^(re-dispatching|rerouted)' then 'The barangay is sending another available tanod.'
    when p_remark ~* '^no tanod' then 'Waiting for an available tanod.'
    when p_remark ~* '^sla breach' then 'Past the expected date. The barangay has been alerted.'
    when p_remark ~* '^resolution target moved from' then 'The barangay changed the expected resolution date.'
    when p_is_system then p_remark
    else p_remark
  end
$$;
comment on function public.resident_remark(text, boolean) is
  'A status-log note as a resident should read it: assignment, re-dispatch and SLA notes (tanod names, distances, system jargon) become plain wording. 0099.';

drop function if exists public.my_status_log_authors(uuid);
create function public.my_status_log_authors(p_report_id uuid)
returns table (
  status_log_id   uuid,
  author_name     text,
  is_system       boolean,
  author_role     text,
  resident_remark text)
language sql stable security definer set search_path = public, extensions as $$
  select sl.id,
         case when u.role = 'admin' then 'Barangay' else u.full_name end,
         sl.is_system,
         u.role::text,
         public.resident_remark(sl.remark, sl.is_system)
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
   where sl.report_id = p_report_id
     and r.resident_id = (select auth.uid())
$$;
revoke execute on function public.my_status_log_authors(uuid) from public, anon;
grant  execute on function public.my_status_log_authors(uuid) to authenticated;

drop function if exists public.my_resolution_authors(uuid[]);
create function public.my_resolution_authors(p_report_ids uuid[])
returns table (
  report_id       uuid,
  author_name     text,
  is_system       boolean,
  author_role     text,
  resident_remark text)
language sql stable security definer set search_path = public, extensions as $$
  select distinct on (sl.report_id)
         sl.report_id,
         case when u.role = 'admin' then 'Barangay' else u.full_name end,
         sl.is_system,
         u.role::text,
         public.resident_remark(sl.remark, sl.is_system)
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
   where sl.new_status = 'resolved'
     and sl.report_id = any(p_report_ids)
     and r.resident_id = (select auth.uid())
   order by sl.report_id, sl.created_at desc
$$;
revoke execute on function public.my_resolution_authors(uuid[]) from public, anon;
grant  execute on function public.my_resolution_authors(uuid[]) to authenticated;
