-- =============================================================
-- SmartSumbong — 0162 Seeing every rung of the ladder (the development team)
--
-- Ace, 2 Nov 2026: the development team must be able to see the portal as each rung sees it, super admin to staff, not as a
-- super admin pretending. Each developer (users.is_dev) gets a real test account for each rung, linked to them; the
-- level-switch Edge Function signs them into one with no password, and the portal keeps their own session to come back to.
-- Because the test account is a real account of that rung, the database shows it exactly what that rung may see and do.
--
--   users.is_test                   a test account: marked TEST in the portal; never taken for a committee's Kagawad when the
--                                   system asks one to pick a tanod (_reroute_ask, sweep_reroute_questions)
--   dev_test_accounts               which test account is a developer's, for which rung (super, captain, committee, moderator)
--   dev_level_switches              every switch, who and into which rung
--   dev_test_accounts_ensure(com)   a developer makes their missing test accounts (or moves the Kagawad and staff to another committee)
--   dev_levels()                    a developer's test accounts, for the switcher
-- =============================================================

set search_path = public, extensions;

alter table public.users add column if not exists is_test boolean not null default false;
comment on column public.users.is_test is '0162: a development team test account (one per rung per developer). Never chosen by routing.';

create table public.dev_test_accounts (
  owner   uuid not null references public.users (id) on delete cascade,
  level   text not null check (level in ('super', 'captain', 'committee', 'moderator')),
  account uuid not null unique references public.users (id) on delete cascade,
  primary key (owner, level)
);
alter table public.dev_test_accounts enable row level security;
create policy dev_test_accounts_own on public.dev_test_accounts for select using (owner = (select auth.uid()));
comment on table public.dev_test_accounts is '0162: a developer''s test account for each rung. Written only by dev_test_accounts_ensure().';

create table public.dev_level_switches (
  id     bigint generated always as identity primary key,
  owner  uuid not null references public.users (id) on delete cascade,
  level  text not null,
  at     timestamptz not null default now()
);
create index dev_level_switches_owner_idx on public.dev_level_switches (owner, at desc);
alter table public.dev_level_switches enable row level security;
create policy dev_level_switches_read on public.dev_level_switches for select using ((select public.is_super_admin()));
comment on table public.dev_level_switches is '0162: every switch into a rung by a developer (written by the level-switch Edge Function).';

create or replace function public.dev_test_accounts_ensure(p_committee text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, auth
as $$
declare
  me public.users; v_com text; v_level text; v_id uuid; v_email text; v_first text; v_mobile text; v_label text; n integer := 0;
begin
  select * into me from public.users where id = auth.uid();
  if me.id is null or not coalesce(me.is_dev, false) or coalesce(me.is_test, false) or coalesce(me.is_suspended, false) then
    raise exception 'Only a member of the development team can have test accounts' using errcode = '42501';
  end if;
  v_com := coalesce(nullif(p_committee, ''), (select key from public.committees where active order by sort, key limit 1));
  if v_com is null or not exists (select 1 from public.committees where key = v_com and active) then
    raise exception 'Pick a committee that is switched on' using errcode = 'check_violation';
  end if;
  v_first := coalesce(nullif(btrim(split_part(me.full_name, ',', 2)), ''), 'Dev');
  foreach v_level in array array['super', 'captain', 'committee', 'moderator'] loop
    select account into v_id from public.dev_test_accounts where owner = me.id and level = v_level;
    if v_id is null then
      v_id := gen_random_uuid();
      v_email := format('dev-%s-%s@test.smartsumbong.ph', left(replace(me.id::text, '-', ''), 10), v_level);
      v_label := case v_level when 'super' then 'Test Super admin' when 'captain' then 'Test Captain' when 'committee' then 'Test Kagawad' else 'Test Staff' end;
      loop   -- a number no real phone uses (09000), unique
        v_mobile := '+639000' || lpad((floor(random() * 1000000))::int::text, 6, '0');
        exit when not exists (select 1 from public.users where mobile_number = v_mobile);
      end loop;
      perform set_config('smartsumbong.provisioning_admin', 'on', true);
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                              raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                              confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
              extensions.crypt(encode(extensions.gen_random_bytes(24), 'hex'), extensions.gen_salt('bf')), now(),
              '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', v_label || ', ' || v_first), now(), now(), '', '', '', '');
      insert into auth.identities (id, provider_id, user_id, identity_data, provider, created_at, updated_at)
      values (gen_random_uuid(), v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now());
      perform set_config('smartsumbong.provisioning_admin', 'off', true);
      insert into public.users (id, full_name, email, mobile_number, role, verification_status, verified_at, verified_by, must_change_password, is_test)
      values (v_id, v_label || ', ' || v_first, v_email, v_mobile, 'admin', 'verified', now(), me.id, false, true);
      insert into public.dev_test_accounts (owner, level, account) values (me.id, v_level, v_id);
      insert into public.account_audit (subject_id, actor_id, action, detail)
      values (v_id, me.id, 'admin_created', format('Test account (%s) for the development team', v_level));
      n := n + 1;
    end if;
    perform set_config('smartsumbong.admin_access', 'on', true);   -- the access guard: this is the developer's own test account
    update public.users
       set admin_tier = v_level,
           committee = case when v_level in ('committee', 'moderator') then v_com else null end,
           official_role = case v_level when 'committee' then 'kagawad' else null end,
           is_dev = false, is_test = true, must_change_password = false
     where id = v_id;
  end loop;
  perform set_config('smartsumbong.admin_access', 'off', true);
  return jsonb_build_object('made', n, 'committee', v_com);
end $$;

create or replace function public.dev_levels()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('level', d.level, 'account', d.account, 'name', u.full_name, 'committee', u.committee)
                            order by array_position(array['super', 'captain', 'committee', 'moderator'], d.level)), '[]'::jsonb)
    from public.dev_test_accounts d join public.users u on u.id = d.account
   where d.owner = auth.uid() and exists (select 1 from public.users m where m.id = auth.uid() and coalesce(m.is_dev, false))
$$;

revoke all on function public.dev_test_accounts_ensure(text) from public, anon;
revoke all on function public.dev_levels() from public, anon;
grant execute on function public.dev_test_accounts_ensure(text) to authenticated;
grant execute on function public.dev_levels() to authenticated;

-- the two places the system picks a committee's Kagawad: never a test account
create or replace function public._reroute_ask(p_report uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
declare
  v_com text := public._reroute_committee(p_report);
  r public.reports%rowtype; v_min smallint; v_q bigint; v_label text; v_msg text;
begin
  if v_com is null then return false; end if;
  if exists (select 1 from public.reroute_questions where report_id = p_report and state = 'open') then return true; end if;
  if not exists (select 1 from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false) and not u.is_test) then
    return false;
  end if;
  select * into r from public.reports where id = p_report;
  select case when exists (select 1 from public.report_triage t where t.report_id = p_report and t.effective_level = 'urgent')
              then reroute_ask_urgent_minutes else reroute_ask_minutes end
    into v_min from public.operational_settings where id = 1;
  insert into public.reroute_questions (report_id, committee, attempt, due_at)
  values (p_report, v_com, r.dispatch_attempts, now() + make_interval(mins => v_min))
  returning id into v_q;
  v_label := public._committee_label(v_com);
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
  values (p_report, r.resident_id, r.status, r.status,
          format('No %s tanod is free: asking its Kagawad (%s min) before sending the nearest from any committee', v_label, v_min), true);
  v_msg := format('No %s tanod is free for case %s (%s). Pick a tanod within %s minutes, or the nearest tanod from any committee is sent.',
                  v_label, r.tracking_id, r.subject, v_min);
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, p_report, 'reroute_question', left(v_msg, 500)
    from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false) and not u.is_test;
  insert into public.inbox_messages (recipient, kind, subject, body, report_id, question_id)
  select u.id, 'system', left('Pick a tanod for ' || r.tracking_id, 140), v_msg, p_report, v_q
    from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false) and not u.is_test;
  return true;
end $$;

create or replace function public.sweep_reroute_questions() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
declare q record;
begin
  for q in
    select x.*, r.tracking_id, r.resident_id, r.status, r.deleted_at
      from public.reroute_questions x join public.reports r on r.id = x.report_id
     where x.state = 'open'
     order by x.due_at
  loop
    if q.deleted_at is not null or q.status not in ('pending_review', 'validated')
       or exists (select 1 from public.dispatches d where d.report_id = q.report_id and d.state in ('assigned', 'accepted')) then
      update public.reroute_questions set state = 'closed', answered_at = now() where id = q.id;
    elsif q.due_at < now() then
      update public.reroute_questions set state = 'timed_out', answered_at = now() where id = q.id;
      insert into public.status_logs (report_id, changed_by, old_status, new_status, remark, is_system)
      values (q.report_id, q.resident_id, q.status, q.status,
              format('Nobody answered in time: sending the nearest tanod from any committee'), true);
      perform set_config('smartsumbong.reroute_any', 'on', true);
      update public.reroute_questions set dispatch_id = public.auto_dispatch(q.report_id) where id = q.id;
      perform set_config('smartsumbong.reroute_any', 'off', true);
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, q.report_id, 'reroute_question',
             left(format('Nobody answered in time on case %s: the nearest tanod from any committee was sent, if one was free.', q.tracking_id), 500)
        from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = q.committee and not coalesce(u.is_suspended, false) and not u.is_test;
    end if;
  end loop;
end $$;
