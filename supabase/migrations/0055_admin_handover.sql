-- =============================================================
-- SmartSumbong — 0055 Admin handover window
--
-- Grant Administrator Access (retirement-requests.php, renamed "Extra
-- Administrative Services" 15 Sep 2026) has shipped a "keep my own admin
-- access for a training/overlap period" checkbox, a handover-length field,
-- a revert-role field, a handover banner, and a Cancel Handover button
-- since that rename — all calling promote_to_admin() with p_handover_days/
-- p_revert_role, plus cancel_admin_handover() and my_admin_handover_status(),
-- none of which exist in the schema. This migration is the missing other
-- half: it was referenced by name in that page's own comments ("0055")
-- and in dashboard.php's ("0056", see the next migration) long before
-- either was actually written here — the database side never shipped
-- alongside the portal side that already assumed it.
--
-- What a real turnover needs and what the earlier succession work (0014)
-- did not: certification, oath-taking, the barangay's own bureaucracy take
-- time, so the outgoing admin needs to keep acting as administrator for a
-- bounded window while training their successor, rather than losing
-- access the instant the successor is appointed. This does not change who
-- is promoted or when — promote_to_admin() still hands the successor
-- admin access immediately, exactly as before. It adds a self-timer on the
-- OUTGOING admin: a date after which they are automatically returned to
-- an ordinary role, with no dependency on them remembering to step down
-- themselves, or on a developer being reachable to do it by hand.
--
-- Three rules, matching 0014's own reasoning:
--
-- 1. The timer is on the caller, never on the person being promoted. The
--    successor's own promotion is untouched by any of this.
-- 2. guard_last_admin (0014) already refuses to leave the barangay with
--    zero admins on any update to public.users, so the automatic revert
--    below inherits that protection for free — it can only ever fire
--    after the successor is already an admin.
-- 3. Every timer set, cancelled or fired is written to account_audit,
--    same ledger 0014 started for promotions and step-downs.
-- =============================================================

set search_path = public, extensions;

-- ---------- schema: the timer lives on the outgoing admin's own row ----

alter table public.users
  add column if not exists admin_handover_until      timestamptz,
  add column if not exists admin_handover_role       user_role,
  add column if not exists admin_handover_successor  uuid references public.users (id) on delete set null;

comment on column public.users.admin_handover_until is
  'Set by promote_to_admin() when the outgoing admin opts to keep access during training. sweep_admin_handovers() reverts the role once this passes.';
comment on column public.users.admin_handover_role is
  'The role this admin reverts to when their handover window ends.';
comment on column public.users.admin_handover_successor is
  'Who this admin is training during the handover window — display only.';

-- ---------- promote, extended -----------------------------------------
-- New parameter list, not just new defaults on the old one: PostgREST
-- resolves an rpc() call by matching the named parameters sent, and two
-- overloads of the same function name (the old 2-arg promote_to_admin and
-- a new 4-arg one) would make an ordinary p_user/p_reason-only call from
-- accounts.php's callers ambiguous. Dropped first, same fix as
-- account_directory's 0039/0040 collision.

drop function if exists public.promote_to_admin(uuid, text);

create or replace function public.promote_to_admin(
  p_user           uuid,
  p_reason         text default null,
  p_handover_days  integer default null,
  p_revert_role    user_role default null
)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_days   integer;
  v_revert user_role;
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

  -- Optional: the caller keeps their own admin access for a bounded
  -- training window instead of handing over everything at once. This
  -- writes only to the caller's own row -- it cannot be used to set a
  -- timer on anyone else, since auth.uid() is what is_admin() already
  -- verified above.
  if p_handover_days is not null then
    v_days := greatest(1, least(90, p_handover_days));
    v_revert := coalesce(p_revert_role, 'resident');
    if v_revert = 'admin' then
      raise exception 'Choose the role you will return to, not administrator';
    end if;

    update public.users
       set admin_handover_until     = now() + (v_days || ' days')::interval,
           admin_handover_role      = v_revert,
           admin_handover_successor = p_user
     where id = auth.uid();

    insert into public.account_audit (subject_id, actor_id, action, detail)
    values (auth.uid(), auth.uid(), 'handover_started',
            format('Training %s for %s day(s), then returning to %s',
                   v_user.full_name, v_days, v_revert));
  end if;

  return v_user.full_name;
end $$;

revoke execute on function public.promote_to_admin(uuid, text, integer, user_role) from public, anon;
grant  execute on function public.promote_to_admin(uuid, text, integer, user_role) to authenticated;

comment on function public.promote_to_admin(uuid, text, integer, user_role) is
  'Appoints a verified account as administrator. p_handover_days/p_revert_role optionally start a bounded self-revert timer on the CALLER, not on p_user.';

-- ---------- cancel: keep the successor, drop the timer -----------------
-- Cancelling never touches the successor's own admin access -- they were
-- promoted the moment promote_to_admin() ran, same as any other
-- appointment. This only clears the outgoing admin's own scheduled revert,
-- so they remain administrator until they step down themselves.

create or replace function public.cancel_admin_handover()
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may cancel a handover';
  end if;

  if not exists (
    select 1 from public.users
     where id = auth.uid() and admin_handover_until is not null
  ) then
    raise exception 'You do not have a handover in progress';
  end if;

  update public.users
     set admin_handover_until     = null,
         admin_handover_role      = null,
         admin_handover_successor = null
   where id = auth.uid();

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (auth.uid(), auth.uid(), 'handover_cancelled',
          'Handover cancelled; remains administrator until stepping down');
end $$;

revoke execute on function public.cancel_admin_handover() from public, anon;
grant  execute on function public.cancel_admin_handover() to authenticated;

-- ---------- status: what retirement-requests.php reads on load ---------
-- Always exactly one row for the calling admin, with null fields when no
-- handover is active -- retirement.php checks admin_handover_until on the
-- returned row rather than the row's mere existence, matching that.

create or replace function public.my_admin_handover_status()
returns table (
  admin_handover_until timestamptz,
  admin_handover_role  user_role,
  successor_name       text
)
language sql stable security definer set search_path = public, extensions as $$
  select u.admin_handover_until, u.admin_handover_role, s.full_name
    from public.users u
    left join public.users s on s.id = u.admin_handover_successor
   where u.id = auth.uid()
$$;

revoke execute on function public.my_admin_handover_status() from public, anon;
grant  execute on function public.my_admin_handover_status() to authenticated;

-- ---------- the timer firing --------------------------------------------
-- guard_last_admin (0014) fires on this UPDATE exactly as it would on any
-- other -- if reverting a given admin would leave zero active admins, that
-- one row's update is refused and the exception is caught here so the rest
-- of the sweep still runs. In ordinary use this never triggers, since a
-- handover cannot start until a successor is already an admin.

create or replace function public.sweep_admin_handovers()
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_row record;
begin
  for v_row in
    select id, full_name, admin_handover_role
      from public.users
     where admin_handover_until is not null
       and admin_handover_until <= now()
  loop
    begin
      update public.users
         set role                     = v_row.admin_handover_role,
             admin_handover_until     = null,
             admin_handover_role      = null,
             admin_handover_successor = null
       where id = v_row.id;

      insert into public.account_audit (subject_id, actor_id, action, detail)
      values (v_row.id, null, 'handover_expired',
              format('Handover window ended; returned to %s automatically', v_row.admin_handover_role));

      insert into public.notifications (user_id, kind, message)
      values (v_row.id, 'verification',
              format('Your administrator handover window has ended. You are now a %s.', v_row.admin_handover_role));
    exception when others then
      -- One admin's revert failing (most likely guard_last_admin refusing
      -- it) must never stop the rest of the sweep from running.
      raise notice 'sweep_admin_handovers: could not revert %: %', v_row.full_name, sqlerrm;
    end;
  end loop;
end $$;

revoke execute on function public.sweep_admin_handovers() from public, anon, authenticated;

select cron.schedule('sweep-admin-handovers', '*/15 * * * *',
                     $$select public.sweep_admin_handovers()$$);
