-- SmartSumbong — the tanod's resolution note keeps the tanod's name (phone run, 7 Oct 2026).
--
-- approve_resolution (0073) logs the tanod's field report as the resolution
-- note, under the approving admin, so the resident read "BARANGAY: Found the
-- person burning trash…" — the tanod's words credited to the barangay.
-- The stored history stays as it is; the bylines the resident sees (0099)
-- name the tanod when the note is word for word their field report.

create or replace function public._resolution_tanod(p_report uuid, p_remark text, p_new_status report_status)
returns public.users language sql stable security definer set search_path = public as $$
  select u.*
    from public.dispatches d
    join public.users u on u.id = d.tanod_id
   where p_new_status = 'resolved'
     and d.report_id = p_report
     and d.state = 'resolved'
     and nullif(trim(d.field_report_text), '') is not null
     and trim(d.field_report_text) = trim(coalesce(p_remark, ''))
   order by d.resolved_at desc nulls last
   limit 1
$$;
revoke execute on function public._resolution_tanod(uuid, text, report_status) from public, anon, authenticated;

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
         coalesce(t.full_name, case when u.role = 'admin' then 'Barangay' else u.full_name end),
         sl.is_system,
         coalesce(t.role::text, u.role::text),
         public.resident_remark(sl.remark, sl.is_system)
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
    left join lateral (select * from public._resolution_tanod(sl.report_id, sl.remark, sl.new_status)) t on true
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
         coalesce(t.full_name, case when u.role = 'admin' then 'Barangay' else u.full_name end),
         sl.is_system,
         coalesce(t.role::text, u.role::text),
         public.resident_remark(sl.remark, sl.is_system)
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
    left join public.users u on u.id = sl.changed_by
    left join lateral (select * from public._resolution_tanod(sl.report_id, sl.remark, sl.new_status)) t on true
   where sl.new_status = 'resolved'
     and sl.report_id = any(p_report_ids)
     and r.resident_id = (select auth.uid())
   order by sl.report_id, sl.created_at desc
$$;
revoke execute on function public.my_resolution_authors(uuid[]) from public, anon;
grant  execute on function public.my_resolution_authors(uuid[]) to authenticated;
