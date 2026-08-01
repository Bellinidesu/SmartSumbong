-- =============================================================
-- SmartSumbong — 0009 Admin manual dispatch
--
-- The admin overrides WHO is sent, not how many jobs a tanod holds.
-- Proximity picks the nearest available unit; the admin may pick a
-- different available unit, because they know things the database does
-- not — who has the tricycle, who knows the street, who the
-- complainant will talk to.
--
-- What the admin cannot do is stack a second live incident on someone.
-- That rule holds for automatic routing, tanod-to-tanod reroutes and
-- admin assignment alike, so a tanod on scene is never interrupted by
-- a ticket they did not ask for.
--
-- The acceptance window is unchanged: set_accept_deadline derives it
-- from sla_policies by category however the dispatch was created, so a
-- manually assigned noise complaint still runs on the noise-complaint
-- clock.
-- =============================================================

set search_path = public, extensions;

create or replace function public.admin_dispatch(
  p_report uuid, p_tanod uuid, p_instructions text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    public.users%rowtype;
  v_busy     text;
  v_dispatch uuid;
  v_metres   double precision;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may assign a dispatch manually';
  end if;

  select * into v_report from public.reports where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;

  select * into v_tanod from public.users where id = p_tanod;
  if not found or v_tanod.role <> 'tanod' then
    raise exception 'That account is not a tanod';
  end if;

  -- Available means on duty, verified and not suspended.
  if not v_tanod.is_dispatchable then
    raise exception '% is not available for dispatch (duty status: %)',
      v_tanod.full_name, coalesce(v_tanod.duty_status::text, 'not set');
  end if;

  select r.subject into v_busy
    from public.dispatches d
    join public.reports r on r.id = d.report_id
   where d.tanod_id = p_tanod and d.state in ('assigned', 'accepted')
   limit 1;

  if v_busy is not null then
    raise exception
      '% is already handling an active incident. Choose another available tanod.',
      v_tanod.full_name;
  end if;

  -- Distance is recorded for the trail, not used as a gate. The point
  -- of a manual assignment is that the admin has overruled proximity.
  select st_distance(v_tanod.last_geom, v_report.geom) into v_metres;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, p_tanod, auth.uid(),
          coalesce(nullif(trim(p_instructions), ''), 'Manually assigned by the barangay admin.'))
  returning id into v_dispatch;

  update public.reports
     set status = 'assigned', awaiting_unit_since = null
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), v_report.status, 'assigned',
          case when v_metres is null
            then format('Manually assigned to %s by admin', v_tanod.full_name)
            else format('Manually assigned to %s by admin (%s m from the incident)',
                        v_tanod.full_name, round(v_metres))
          end);

  insert into public.notifications (user_id, report_id, kind, message)
  values (p_tanod, p_report, 'assignment',
          format('Assigned by the barangay admin: %s', v_report.subject));

  return v_dispatch;
end $$;

revoke execute on function public.admin_dispatch(uuid, uuid, text) from public, anon;
grant  execute on function public.admin_dispatch(uuid, uuid, text) to authenticated;

-- ---------- who can the admin actually pick? -----------------
-- Backs the assignment dropdown in the web portal. Ordered by
-- distance so the proximity suggestion is still visible, but every
-- available tanod is listed and selectable.

create or replace function public.assignable_tanods(p_report uuid)
returns table (tanod_id uuid, full_name text, metres double precision,
               location_fresh boolean)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name,
         st_distance(u.last_geom, r.geom),
         public.location_is_fresh(u.last_location_at)
    from public.reports r
    cross join public.users u
   where r.id = p_report
     and u.is_dispatchable
     and not exists (
       select 1 from public.dispatches d
        where d.tanod_id = u.id and d.state in ('assigned', 'accepted'))
   order by st_distance(u.last_geom, r.geom) nulls last, u.full_name
$$;
