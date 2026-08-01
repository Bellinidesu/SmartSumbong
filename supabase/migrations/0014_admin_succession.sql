-- =============================================================
-- SmartSumbong — 0014 Administration handover
--
-- Barangay officials change on a schedule. Elections are every three
-- years, staff leave mid-term, and by then nobody involved in building
-- this will be answering messages. So handover has to be something the
-- barangay does for itself, in the portal, without a developer and
-- without the Supabase dashboard.
--
-- Three rules hold it together.
--
-- 1. Only a verified account may be promoted. Verification is the step
--    where an admin checked a government ID against barangay records and
--    confirmed the person lives in 183 — so "verified" already means "of
--    this barangay". No separate membership field is needed, and an
--    outsider cannot be promoted because an outsider cannot be verified.
--
-- 2. The last administrator cannot be removed. Not by stepping down, not
--    by suspension, not by rejection. Without this, one wrong click locks
--    the barangay out of its own system and the only way back is the
--    Supabase project dashboard — which is exactly the dependency
--    turnover is supposed to end.
--
-- 3. Every role change is written down. status_logs is per-report; there
--    was nowhere recording that someone became an administrator, on what
--    date, at whose hand. For a system whose argument is accountability,
--    that was a hole — and it is the first thing a DILG handover review
--    would ask for.
--
-- The portal additionally requires the outgoing admin to re-enter their
-- password before either call. That is enforced in PHP rather than here,
-- because the database has no way to check a password; what this layer
-- guarantees is that only an authenticated admin can call these at all.
-- =============================================================

set search_path = public, extensions;

-- ---------- audit trail for role and status changes ----------

create table if not exists public.account_audit (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.users (id) on delete restrict,
  actor_id    uuid          references public.users (id) on delete restrict,
  action      text not null,
  detail      text,
  created_at  timestamptz not null default now()
);

create index if not exists account_audit_subject_idx
  on public.account_audit (subject_id, created_at desc);

comment on table public.account_audit is
  'Append-only record of promotions, step-downs and other account state changes. Deliberately outside status_logs, which is per-report.';

alter table public.account_audit enable row level security;

-- Same shape as status_logs: admins read it, nobody writes it directly.
-- The functions below are definer and bypass this.
create policy account_audit_read on public.account_audit
  for select using (public.is_admin());

-- ---------- who may be handed the portal ---------------------

create or replace function public.admin_candidates(p_search text default null)
returns table (id uuid, full_name text, email text, role user_role, mobile_number text)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name, u.email, u.role, u.mobile_number
    from public.users u
   where u.verification_status = 'verified'
     and not u.is_suspended
     and u.role <> 'admin'
     and (p_search is null or trim(p_search) = ''
          or u.full_name ilike '%' || trim(p_search) || '%'
          or u.email     ilike '%' || trim(p_search) || '%')
   order by u.full_name
   limit 25
$$;

revoke execute on function public.admin_candidates(text) from public, anon;
grant  execute on function public.admin_candidates(text) to authenticated;

comment on function public.admin_candidates(text) is
  'Verified, unsuspended, non-admin accounts. Verified means the barangay confirmed they live in 183.';

-- ---------- promote ------------------------------------------

create or replace function public.promote_to_admin(p_user uuid, p_reason text default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may appoint another administrator';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.role = 'admin' then
    raise exception '% is already an administrator', v_user.full_name;
  end if;

  if v_user.verification_status <> 'verified' then
    raise exception
      '% is not a verified account. Only a verified resident or tanod of Barangay 183 may be appointed.',
      v_user.full_name;
  end if;

  if v_user.is_suspended then
    raise exception '% is suspended and cannot be appointed', v_user.full_name;
  end if;

  -- A tanod who becomes an admin stops being dispatchable: they are no
  -- longer on the roster, and leaving them in it would send incidents to
  -- someone sitting at a desk. sync_dispatchable does this on its own
  -- once the role changes, but the duty status is cleared here so the
  -- Personnel screen does not still show them as On Duty.
  update public.users
     set role        = 'admin',
         duty_status = null
   where id = p_user;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'promoted_to_admin',
          coalesce(v_reason, format('Appointed by %s',
            (select full_name from public.users where id = auth.uid()))));

  insert into public.notifications (user_id, kind, message)
  values (p_user, 'verification',
          'You have been given barangay administrator access to Smart Sumbong.');

  return v_user.full_name;
end $$;

revoke execute on function public.promote_to_admin(uuid, text) from public, anon;
grant  execute on function public.promote_to_admin(uuid, text) to authenticated;

-- ---------- step down ----------------------------------------

create or replace function public.step_down_as_admin(p_new_role user_role default 'resident')
returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_left integer;
  v_me   public.users%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may step down';
  end if;

  if p_new_role = 'admin' then
    raise exception 'Choose the role you are returning to, not administrator';
  end if;

  select * into v_me from public.users where id = auth.uid() for update;

  select count(*) into v_left from public.users
   where role = 'admin' and id <> auth.uid() and not is_suspended;

  -- The guard. Appoint your successor first; then this will let you go.
  if v_left = 0 then
    raise exception
      'You are the only administrator. Appoint your successor before stepping down, or the barangay will be locked out of its own system.';
  end if;

  update public.users set role = p_new_role where id = auth.uid();

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (v_me.id, v_me.id, 'stepped_down',
          format('Returned to %s. %s administrator(s) remain.', p_new_role, v_left));

  insert into public.notifications (user_id, kind, message)
  select id, 'verification',
         format('%s has stepped down as barangay administrator.', v_me.full_name)
    from public.users where role = 'admin' and id <> v_me.id;

  return v_left;
end $$;

revoke execute on function public.step_down_as_admin(user_role) from public, anon;
grant  execute on function public.step_down_as_admin(user_role) to authenticated;

-- ---------- the same guard, from the other directions ---------
-- Stepping down is not the only way to lose the last admin. Suspending
-- one, or a future screen demoting one, would do it just as well. The
-- trigger catches every path rather than trusting each caller.

create or replace function public.guard_last_admin()
returns trigger language plpgsql as $$
declare v_left integer;
begin
  if old.role = 'admin'
     and (new.role <> 'admin' or new.is_suspended) then
    select count(*) into v_left from public.users
     where role = 'admin' and not is_suspended and id <> old.id;
    if v_left = 0 then
      raise exception
        'This is the last active administrator. Appoint another before removing this one.';
    end if;
  end if;
  return new;
end $$;

create trigger users_guard_last_admin
  before update on public.users
  for each row execute function public.guard_last_admin();

comment on function public.guard_last_admin() is
  'Refuses any update that would leave Barangay 183 with no active administrator.';
