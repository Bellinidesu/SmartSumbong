-- =============================================================
-- SmartSumbong — 0055 Bounded admin handover window
--
-- Transfer Administration is moving off Residents/Personnel and onto
-- what was the standalone Retirement Requests page (now "Extra
-- Administrative Services" -- the portal side of the same password-
-- gated section the tanod app already has). Alongside that move: a
-- real barangay succession (an election result, a resignation) is not
-- instant -- certification, oath-taking, and the barangay's own
-- bureaucracy take time -- so promote_to_admin (0014) being all-or-
-- nothing forced a choice between the outgoing admin keeping full,
-- untracked access indefinitely, or giving it up before the incoming
-- one actually knows the system.
--
-- This adds a bounded middle ground: promoting a successor can also
-- schedule the OUTGOING admin's own return to their prior role, up to
-- 90 days out. Both accounts hold admin access during that window --
-- nothing here takes access away from the successor or the outgoing
-- admin early -- and it ends itself on schedule via the same pg_cron
-- sweep pattern 0002 already established, rather than depending on
-- someone remembering to click Step Down.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists admin_handover_until        timestamptz,
  add column if not exists admin_handover_role         user_role,
  add column if not exists admin_handover_successor_id uuid
    references public.users (id) on delete set null;

comment on column public.users.admin_handover_until is
  'Set by promote_to_admin()''s optional handover window (0055). When '
  'reached, run_admin_handover_expirations() reverts this admin back to '
  'admin_handover_role automatically. Null outside an active handover.';
comment on column public.users.admin_handover_role is
  'Role this admin returns to when admin_handover_until passes -- '
  'captured at scheduling time, since an unattended sweep has no one to '
  'ask once the window actually ends.';
comment on column public.users.admin_handover_successor_id is
  'Who this admin is training during the handover window. Display only '
  '-- the successor already has full, independent admin access from the '
  'moment they are promoted; this is not a permission gate.';

-- ---------- promote_to_admin, extended ---------------------------
-- Same function (0014), now with two optional trailing parameters.
-- Existing callers passing only (p_user, p_reason) are unaffected --
-- both default to null, meaning "no handover window, step down
-- manually whenever," exactly today's behaviour.

create or replace function public.promote_to_admin(
  p_user          uuid,
  p_reason        text default null,
  p_handover_days integer default null,
  p_revert_role   user_role default null)
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

  if p_handover_days is not null then
    if p_handover_days < 1 or p_handover_days > 90 then
      raise exception 'A handover window must be between 1 and 90 days';
    end if;
    if p_revert_role is null or p_revert_role = 'admin' then
      raise exception 'Choose the role you will return to when the handover ends';
    end if;
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

  if p_handover_days is not null then
    update public.users
       set admin_handover_until        = now() + (p_handover_days || ' days')::interval,
           admin_handover_role         = p_revert_role,
           admin_handover_successor_id = p_user
     where id = auth.uid();
  end if;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'promoted_to_admin',
          coalesce(v_reason, format('Appointed by %s',
            (select full_name from public.users where id = auth.uid()))));

  if p_handover_days is not null then
    insert into public.account_audit (subject_id, actor_id, action, detail)
    values (auth.uid(), auth.uid(), 'handover_scheduled',
            format('Training %s for up to %s day(s); returns to %s on %s',
              v_user.full_name, p_handover_days, p_revert_role,
              to_char(now() + (p_handover_days || ' days')::interval, 'Mon dd, yyyy')));
  end if;

  insert into public.notifications (user_id, kind, message)
  values (p_user, 'verification',
          'You have been given barangay administrator access to Smart Sumbong.'
          || case when p_handover_days is not null
               then format(' The outgoing administrator will continue to help for up to %s day(s).', p_handover_days)
               else '' end);

  return v_user.full_name;
end $$;

-- Drop the old 2-argument signature -- Postgres treats a different
-- parameter count as a distinct overload, and PostgREST would otherwise
-- have two functions named promote_to_admin to pick between.
drop function if exists public.promote_to_admin(uuid, text);

revoke execute on function public.promote_to_admin(uuid, text, integer, user_role) from public, anon;
grant  execute on function public.promote_to_admin(uuid, text, integer, user_role) to authenticated;

comment on function public.promote_to_admin(uuid, text, integer, user_role) is
  'Grants admin access. p_handover_days/p_revert_role (0055) are both '
  'optional -- when given, also schedules the CALLING admin''s own '
  'return to p_revert_role once p_handover_days elapse (max 90).';

-- ---------- cancel a scheduled handover ---------------------------
-- Lets the outgoing admin end the overlap early -- the successor is
-- ready sooner than planned -- without waiting the full window out.

create or replace function public.cancel_admin_handover()
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may cancel a handover';
  end if;

  update public.users
     set admin_handover_until        = null,
         admin_handover_role         = null,
         admin_handover_successor_id = null
   where id = auth.uid();
end $$;

revoke execute on function public.cancel_admin_handover() from public, anon;
grant  execute on function public.cancel_admin_handover() to authenticated;

comment on function public.cancel_admin_handover() is
  'Ends the caller''s own in-progress handover window immediately. Does '
  'not touch the successor''s admin access either way -- they keep it.';

-- ---------- my_admin_handover_status() ----------------------------
-- What Extra Administrative Services shows the current admin about
-- their own in-progress handover, if any. No security definer needed --
-- a plain select on your own row needs nothing RLS does not already
-- allow.

create or replace function public.my_admin_handover_status()
returns table (
  admin_handover_until timestamptz,
  admin_handover_role  user_role,
  successor_name       text)
language sql stable set search_path = public, extensions as $$
  select u.admin_handover_until, u.admin_handover_role, s.full_name
    from public.users u
    left join public.users s on s.id = u.admin_handover_successor_id
   where u.id = auth.uid()
$$;

revoke execute on function public.my_admin_handover_status() from public, anon;
grant  execute on function public.my_admin_handover_status() to authenticated;

-- ---------- scheduled sweep ----------------------------------------
-- Same idiom as 0002's sweep_overdue_reports() etc: security definer,
-- called by pg_cron, no caller-supplied input. One admin's handover
-- failing (e.g. guard_last_admin refusing to revert the barangay's
-- only remaining admin, if the successor lost admin status in the
-- meantime) must not block every other admin's handover in the same
-- sweep, hence the per-row exception guard -- a failed row just tries
-- again next run rather than aborting the whole function.

create or replace function public.run_admin_handover_expirations()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  for r in
    select id, full_name, admin_handover_role
      from public.users
     where role = 'admin'
       and admin_handover_until is not null
       and admin_handover_until <= now()
  loop
    begin
      update public.users
         set role                         = r.admin_handover_role,
             admin_handover_until         = null,
             admin_handover_role          = null,
             admin_handover_successor_id  = null
       where id = r.id;

      insert into public.account_audit (subject_id, actor_id, action, detail)
      values (r.id, null, 'stepped_down',
              format('Handover window ended automatically. Returned to %s.', r.admin_handover_role));

      insert into public.notifications (user_id, kind, message)
      values (r.id, 'verification',
              'Your administrator handover period has ended. You have been returned to your prior role.');
    exception when others then
      -- Leave this one's handover in place; the next hourly run tries
      -- again rather than losing the barangay's only administrator.
      continue;
    end;
  end loop;
end $$;

revoke execute on function public.run_admin_handover_expirations() from public, anon, authenticated;

-- Schedule (safe to re-run, same as 0002's sweeps).
select cron.schedule('sweep-admin-handovers', '0 * * * *',
                     $$select public.run_admin_handover_expirations()$$);

-- ---------------------------------------------------------------
-- VERIFY.
--
-- 1. Schedule a short handover and confirm both fields land:
--    select public.promote_to_admin('<verified-account-id>', 'test',
--                                    1, 'resident');
--    select id, role, admin_handover_until, admin_handover_role
--      from public.users where id = auth.uid();
--
-- 2. Force the sweep without waiting a day:
--    update public.users set admin_handover_until = now() - interval '1 minute'
--     where id = auth.uid();
--    select public.run_admin_handover_expirations();
--    -- Expect: role reverted to 'resident', handover columns null again.
-- ---------------------------------------------------------------
