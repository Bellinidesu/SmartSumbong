-- 0102 — Cases accepted before case handlers existed (Rose, 7 Oct 2026).
--
-- 0087 started recording who handles a case, but complaints already
-- accepted before it showed "Nobody yet". Each one now gets the admin who
-- first acted on it after review (from the tamper-checked status log), as
-- if they had taken it then, and the take is logged like any other.

do $$
declare r record;
begin
  perform set_config('smartsumbong.handler_change', 'on', true);
  for r in
    select rp.id, f.changed_by, f.created_at
      from public.reports rp
      join lateral (
        select l.changed_by, l.created_at
          from public.status_logs l
          join public.users a on a.id = l.changed_by and a.role = 'admin'
         where l.report_id = rp.id and l.old_status is not null
         order by l.created_at
         limit 1) f on true
     where rp.handler_id is null
       and rp.deleted_at is null
       and rp.status not in ('pending_review', 'cancelled')
  loop
    update public.reports set handler_id = r.changed_by, handled_since = r.created_at where id = r.id;
    insert into public.case_handler_log (report_id, admin_id, action, reason, created_at)
    values (r.id, r.changed_by, 'take', 'Recorded from the case history (accepted before case handlers existed)', r.created_at);
  end loop;
  perform set_config('smartsumbong.handler_change', 'off', true);
end $$;
