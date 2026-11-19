-- 0179: an administrator reads only the accounts their rung needs (backend sweep, 19 Nov 2026).
-- DRAFT: not applied until Ace says "apply 0179". Click through the Kagawad and staff pages after it (see the sweep report).
--
-- Found by the sweep, proved on the live project with a development team staff account (counts only, no data read):
--   users_self_read said "your own row, or any administrator's". Every administrator tier therefore read EVERY account: 8 of 8
--   residents (mobile number, email, address, ID photo address, what OCR read from the ID) for a staff member, who is allowed no
--   cases but their own, and for a Kagawad, who is allowed no Residents page. sign-upload then signs a link to any stored ID photo
--   for "an administrator", so the address is enough to open the photo. The same wide reading applied to profile_requests (new
--   names and ID photos waiting for a decision: 3 of 3) and account_audit (every password reset, number and email change: 30 of 30),
--   and admin_candidates() (made for choosing a successor) listed verified residents with email and number to any administrator.
--   is_admin() was also true for a suspended or retired administrator, whose rows are otherwise closed to them.
--
-- After this, by rung:
--   super admin, captain  every account (as before)
--   Kagawad, staff        themselves; every administrator and tanod (names on cases, the roster: as before); a resident only through
--                         a case they may open (reports.resident_id of a case _user_sees_case says they see), so the reporter's
--                         name and number are there on the case page and nowhere else
--   resident, tanod       themselves
--   profile_requests      the requester, and the super admins (the Residents page that decides them is theirs alone)
--   account_audit         the super admins and the captain
-- is_admin() is now "an active administrator": not suspended, not retired (admin_tier() already said so).

set search_path = public, extensions;

-- ---------- an administrator is an active one ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.admin_tier() is not null
$$;

-- ---------- which accounts an administrator reads ----------
create or replace function public._admin_sees_user(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_user = auth.uid() then true
    when public.is_full_viewer() then true
    when not public.is_admin() then false
    else exists (select 1 from public.users t where t.id = p_user and t.role in ('admin', 'tanod'))
      or exists (select 1 from public.reports r
                  where r.resident_id = p_user and r.deleted_at is null
                    and public._user_sees_case(auth.uid(), r.id, r.category, r.handler_id))
  end
$$;
revoke all on function public._admin_sees_user(uuid) from public, anon;
grant execute on function public._admin_sees_user(uuid) to authenticated;
comment on function public._admin_sees_user(uuid) is
  '0179: does the signed-in administrator read this account? Super admins and the captain all; others themselves, administrators and tanods, and a resident only through a case they may open.';

alter policy users_self_read on public.users
  using ((id = (select auth.uid())) or (select public.is_full_viewer()) or public._admin_sees_user(id));

alter policy profile_requests_read on public.profile_requests
  using ((select public.is_full_viewer()) or (user_id = (select auth.uid())));

alter policy account_audit_read on public.account_audit
  using ((select public.is_full_viewer()));

-- ---------- the successor picker is the super admins' ----------
create or replace function public.admin_candidates(p_search text default null)
returns table (id uuid, full_name text, email text, role public.user_role, mobile_number text)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name, u.email, u.role, u.mobile_number
    from public.users u
   where (select public.is_super_admin())
     and u.verification_status = 'verified'
     and not u.is_suspended
     and u.role <> 'admin'
     and (p_search is null or trim(p_search) = ''
          or u.full_name ilike '%' || trim(p_search) || '%'
          or u.email     ilike '%' || trim(p_search) || '%')
   order by u.full_name
   limit 25
$$;
