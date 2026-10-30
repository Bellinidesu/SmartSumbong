-- =============================================================
-- SmartSumbong — 0151 Staff as moderators; positions set the tier
--
-- Roles and pages, step 2 (docs/ROLES_AND_PAGES.md, section 1; Ace,
-- 29-30 Oct 2026: "chairman is automatically super admin by logic, kagawad
-- is admin, staff is like ofc moderator, then tanod user").
--
--   moderator    a new administrator tier for staff. A super admin assigns
--                each one to a committee (at the Kagawad's request or from
--                the paperwork showing where they work). A moderator sees
--                and works that committee's cases, like its Kagawad, but
--                does not make the decisions that change who answers for a
--                case: approving or denying an escalation, escalating up
--                the ladder, handing a case to a higher official, or
--                referring it outside. Those stay with the Kagawad and the
--                super admins. (Sir Kiko confirms the exact powers.)
--   positions    set_official_role now sets the tier that goes with the
--                position: the Chairman is a super admin, a Kagawad a
--                committee admin, the secretary a moderator. Someone a
--                super admin has raised to super admin stays one.
--
-- Every access rule that let the committee tier in (30 of them, 0145) now
-- lets the moderator tier in the same way: the rules are rewritten from
-- their own text, so their scope stays exactly what 0145 made it.
-- =============================================================

set search_path = public, extensions;

alter table public.users drop constraint users_admin_tier_check;
alter table public.users add constraint users_admin_tier_check
  check (admin_tier = any (array['super', 'committee', 'moderator', 'captain']));
comment on column public.users.admin_tier is
  '0145/0151: super (everything), committee (a Kagawad: their committee), moderator (staff: their committee, without the decisions), captain (sees all, changes nothing). Null reads as super.';

/** Can this administrator change cases at all (a captain cannot)? */
create or replace function public.admin_can_write()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.admin_tier() in ('super', 'committee', 'moderator'), false) $$;

/** Does this administrator see only their committee (a Kagawad or a staff member)? */
create or replace function public.admin_scoped()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.admin_tier() in ('committee', 'moderator'), false) $$;
revoke all on function public.admin_scoped() from public, anon;
grant execute on function public.admin_scoped() to authenticated;

-- The access rules: wherever the committee tier was let in, the moderator tier is too.
do $$
declare p record; q text; w text; n integer := 0;
  pat constant text := $r$admin_tier\(\) AS admin_tier\) = 'committee'::text$r$;
  rep constant text := $r$admin_tier() AS admin_tier) = ANY (ARRAY['committee'::text, 'moderator'::text])$r$;
begin
  for p in select tablename, policyname, qual, with_check from pg_policies
            where schemaname = 'public' and (qual ~ pat or with_check ~ pat) loop
    q := regexp_replace(p.qual, pat, rep, 'g');
    w := regexp_replace(p.with_check, pat, rep, 'g');
    execute format('alter policy %I on public.%I', p.policyname, p.tablename)
         || case when q is not null then format(' using (%s)', q) else '' end
         || case when w is not null then format(' with check (%s)', w) else '' end;
    n := n + 1;
  end loop;
  if n < 20 then raise exception '0151: only % access rules let the committee tier in; expected about 30', n; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and (qual ~ pat or with_check ~ pat)) then
    raise exception '0151: an access rule still lets only the committee tier in';
  end if;
end $$;

-- A notification about a case outside the committee is not made, for a moderator as for a Kagawad.
create or replace function public._notifications_scope()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role text; v_tier text;
begin
  if new.report_id is null then return new; end if;
  select role::text, coalesce(admin_tier, 'super') into v_role, v_tier from public.users where id = new.user_id;
  if v_role = 'admin' and v_tier in ('committee', 'moderator')
     and not coalesce((select public._user_sees_case(new.user_id, r.id, r.category, r.handler_id) from public.reports r where r.id = new.report_id), false) then
    return null;
  end if;
  return new;
end $$;

/** An administrator's tier, committee and developer mark. A committee admin and a moderator need a committee. There is always a super admin. */
create or replace function public.set_admin_access(p_user uuid, p_tier text, p_committee text default null, p_dev boolean default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u public.users%rowtype;
begin
  if not public.is_super_admin() then raise exception 'Only a super admin changes an administrator''s access' using errcode = 'insufficient_privilege'; end if;
  if p_tier not in ('super', 'committee', 'moderator', 'captain') then raise exception 'Tier is super, committee, moderator or captain' using errcode = 'check_violation'; end if;
  select * into u from public.users where id = p_user;
  if not found or u.role <> 'admin' then raise exception 'That account is not an administrator' using errcode = 'check_violation'; end if;
  if p_tier in ('committee', 'moderator') and (p_committee is null or not exists (select 1 from public.committees where key = p_committee)) then
    raise exception 'Choose the committee' using errcode = 'check_violation';
  end if;
  if coalesce(u.admin_tier, 'super') = 'super' and p_tier <> 'super'
     and not exists (select 1 from public.users x where x.role = 'admin' and coalesce(x.admin_tier, 'super') = 'super' and not coalesce(x.is_suspended, false) and x.id <> p_user) then
    raise exception 'There must always be one super admin' using errcode = 'check_violation';
  end if;
  perform set_config('smartsumbong.admin_access', 'on', true);
  update public.users set admin_tier = p_tier, committee = case when p_tier in ('committee', 'moderator') then p_committee else committee end,
         is_dev = coalesce(p_dev, is_dev)
   where id = p_user;
  perform set_config('smartsumbong.admin_access', 'off', true);
  perform public._smart_event('access', null, format('%s is now %s%s', public.display_name(u.full_name), p_tier,
          case when p_tier in ('committee', 'moderator') then ' (' || public._committee_label(p_committee) || ')' else '' end),
          jsonb_build_object('user', p_user, 'tier', p_tier, 'committee', p_committee, 'dev', p_dev));
end $$;

/** A position (secretary, kagawad, chairman) and the tier that goes with it; a tanod's women-responder mark. */
create or replace function public.set_official_role(p_user uuid, p_role text, p_committee text default null, p_women boolean default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  u public.users%rowtype;
  v_tier text;
begin
  if not public.is_super_admin() then
    raise exception 'Only an administrator may set a position' using errcode = 'insufficient_privilege';
  end if;
  select * into u from public.users where id = p_user;
  if not found then raise exception 'No such account'; end if;
  if p_role is not null and p_role not in ('secretary', 'kagawad', 'chairman') then
    raise exception 'The position must be secretary, kagawad or chairman' using errcode = 'check_violation';
  end if;
  if p_role is not null and u.role <> 'admin' then
    raise exception 'Only an administrator account can hold a position' using errcode = 'check_violation';
  end if;
  if p_role = 'kagawad' and p_committee is null then
    raise exception 'A Kagawad chairs a committee: choose one' using errcode = 'check_violation';
  end if;
  if p_committee is not null and not exists (select 1 from public.committees where key = p_committee) then
    raise exception 'No such committee' using errcode = 'check_violation';
  end if;
  if p_role = 'chairman' and exists (select 1 from public.users x where x.official_role = 'chairman' and x.id <> p_user) then
    raise exception 'There is already a Chairman account' using errcode = 'check_violation';
  end if;
  if p_women is not null and p_women and u.role <> 'tanod' then
    raise exception 'Only a tanod can be a designated women responder' using errcode = 'check_violation';
  end if;
  -- 0151: the tier that goes with the position; a super admin stays one (Sir Kiko is staff by rank, super admin by choice)
  v_tier := case
    when u.role <> 'admin' or p_role is null then u.admin_tier
    when p_role = 'chairman' then 'super'
    when coalesce(u.admin_tier, 'super') = 'super' then 'super'
    when p_role = 'kagawad' then 'committee'
    else 'moderator' end;
  if v_tier = 'moderator' and coalesce(p_committee, u.committee) is null then
    raise exception 'A staff member works in a committee: choose one' using errcode = 'check_violation';
  end if;
  perform set_config('smartsumbong.admin_access', 'on', true);
  update public.users
     set official_role   = p_role,
         committee       = case when p_role = 'kagawad' then p_committee
                                when p_role = 'secretary' then coalesce(p_committee, committee)
                                when p_role is null then committee
                                else null end,
         admin_tier      = v_tier,
         women_responder = coalesce(p_women, women_responder)
   where id = p_user;
  perform set_config('smartsumbong.admin_access', 'off', true);
end $$;

-- The decisions that change who answers for a case stay with the Kagawad and the super admins.
do $$
declare f record; d text; guard constant text := E'\n  if public.admin_tier() = ''moderator'' then\n    raise exception ''Staff cannot make this decision. Ask your Kagawad.'' using errcode = ''insufficient_privilege'';\n  end if;';
  n integer := 0;
begin
  for f in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('approve_escalation', 'deny_escalation', 'escalate_in_barangay', 'hand_to_higher_official', 'refer_report') loop
    d := pg_get_functiondef(f.oid);
    if position('Staff cannot make this decision' in d) = 0 then
      d := regexp_replace(d, E'\nbegin\n', E'\nbegin' || guard || E'\n');
      if position('Staff cannot make this decision' in d) = 0 then raise exception '0151: % did not take the guard', f.oid::regprocedure; end if;
      execute d;
      n := n + 1;
    end if;
  end loop;
  if n <> 5 then raise exception '0151: guarded % of 5 decision functions', n; end if;
end $$;
