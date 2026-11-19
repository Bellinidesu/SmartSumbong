-- 0184: a sensitive case is never shown on the residents' map (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0184".
--
-- Sensitive cases (0130, the panel's ask) are kept out of the waiting line and handled by the Chairman, but nothing stopped one from
-- being published: set_report_public took any case the administrator could open, and public_incidents() lists every is_public case
-- with its category, status and coordinates to every signed-in resident. Proved on a copy built from the migrations: a super admin
-- publishes a sensitive resolved case and a resident's public_incidents() returns it. (On the live project no sensitive case is
-- public today: the one anonymous public case is not sensitive.)
--   * set_report_public refuses to publish a sensitive case (unpublishing is always allowed)
--   * public_incidents() leaves sensitive cases out, whatever their flag says (a case marked sensitive after it was published drops off)
--   * any sensitive case already public is taken off

set search_path = public, extensions;

create or replace function public.set_report_public(p_report uuid, p_public boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._scope_guard(p_report, true);
  if not public.admin_can_write() then
    raise exception 'Only an administrator may publish an incident';
  end if;
  if coalesce(p_public, false) and exists (select 1 from public.reports where id = p_report and is_sensitive) then
    raise exception 'A sensitive case is never shown on the residents'' map' using errcode = 'check_violation';
  end if;
  update public.reports set is_public = coalesce(p_public, false)
   where id = p_report and deleted_at is null;
  if not found then
    raise exception 'No such report';
  end if;
end $$;

create or replace function public.public_incidents()
returns table (id uuid, category public.complaint_category, status public.report_status, latitude double precision, longitude double precision, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.category, r.status, r.latitude, r.longitude, r.created_at
    from public.reports r
   where r.is_public
     and not r.is_sensitive
     and r.deleted_at is null
     and r.status not in ('rejected', 'cancelled')
     and auth.uid() is not null
   order by r.created_at desc
   limit 500
$$;

update public.reports set is_public = false where is_public and is_sensitive;
