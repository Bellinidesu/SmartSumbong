-- =============================================================
-- SmartSumbong — 0145 Who sees what: super admins, committees, captains
--
-- Ready for Barangay 183 (the barangay's requests, 26 Oct; Ace's decisions,
-- 29 Oct 2026). Every administrator now has a tier:
--
--   super      sees and changes everything; sets up committees and access.
--              At 183: Sir Kiko (the barangay's IT admin), Chairperson Zuniga,
--              and the development team (marked is_dev).
--   committee  sees only the categories its committee has ticked (and any
--              case it handles), and works those cases. Analytics and settings
--              are for super admins.
--   captain    sees everything, changes nothing ("more on overviewing").
--
-- Committees become a table the super admin edits (create, rename, switch
-- off), replacing the fixed list of nine. Each committee ticks the categories
-- it sees. For 183 only the committees the barangay asked for are on: Peace and
-- Order, Environment and Disaster Risk, Health and Sanitation, and the Anti-Drug
-- Abuse Council; the others stay in the table switched off ("not created").
--
-- Enforced in the database, not only on the screen:
--   - reports and the 18 tables that hang off a report are read through
--     admin_sees_report() / admin_sees_case();
--   - every write to a case passes _scope_guard() (the one-handler rule's
--     _case_guard calls it too, so status changes, messages, tanod updates and
--     evidence are covered), and a trigger on reports catches the rest;
--   - the functions are grouped: settings and accounts for super admins only,
--     the analytics for super admins and captains, the case actions for those
--     who can write the case, the case readers for those who can see it;
--   - a notification about a case outside a committee admin's scope is never
--     made for them (so it is never pushed either).
-- is_admin() keeps its meaning (any administrator): only what each tier may
-- do changes.
-- =============================================================

set search_path = public, extensions;

-- ---------- the committees -------------------------------------------------

create table public.committees (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  name_en    text not null check (char_length(name_en) between 3 and 120),
  name_fil   text not null check (char_length(name_fil) between 3 and 120),
  sort       smallint not null default 100,
  active     boolean not null default true,
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.committees (key, name_en, name_fil, sort, active) values
  ('peace_order',       'Peace and Order, Human Rights, Transportation and Communication', 'Kapayapaan at Kaayusan, Karapatang Pantao, Transportasyon at Komunikasyon', 1, true),
  ('environment',       'Environmental Protection and Disaster Risk Reduction',            'Pangangalaga sa Kapaligiran at Pagbabawas sa Panganib ng Sakuna',       2, true),
  ('health_sanitation', 'Health and Sanitation',                                           'Kalusugan at Kalinisan',                                                  3, true),
  ('anti_drug',         'Barangay Anti-Drug Abuse Council',                                'Konseho ng Barangay Laban sa Pang-aabuso sa Droga',                       4, true),
  -- in the table so earlier cases and the sensitive-case route (women_family) keep their meaning; switched off for 183
  ('women_family',      'Women, Family and Social Services',                               'Kababaihan, Pamilya at Serbisyong Panlipunan',                            10, false),
  ('appropriations',    'Appropriations, Senior Citizens and PWD',                         'Apropriasyon, Senior Citizen at PWD',                                     11, false),
  ('infrastructure',    'Infrastructure',                                                  'Imprastraktura',                                                          12, false),
  ('youth_sports',      'Youth, Sports and Education',                                     'Kabataan, Palakasan at Edukasyon',                                        13, false),
  ('education',         'Education',                                                       'Edukasyon',                                                               14, false),
  ('agriculture',       'Agriculture',                                                     'Agrikultura',                                                             15, false);

alter table public.users drop constraint if exists users_committee_check;
alter table public.users add constraint users_committee_fkey foreign key (committee) references public.committees (key) on update cascade;
alter table public.committee_for_category drop constraint if exists committee_for_category_committee_check;
alter table public.committee_for_category add constraint committee_for_category_committee_fkey foreign key (committee) references public.committees (key) on update cascade;

-- which categories each committee sees (the super admin's ticks)
create table public.committee_categories (
  committee text not null references public.committees (key) on delete cascade on update cascade,
  category  public.complaint_category not null,
  primary key (committee, category)
);
insert into public.committee_categories (committee, category)
select c.committee, c.category from public.committee_for_category c join public.committees k on k.key = c.committee and k.active;

alter table public.committees enable row level security;
alter table public.committee_categories enable row level security;
create policy committees_read on public.committees for select using ((select public.is_admin()));
create policy committee_categories_read on public.committee_categories for select using ((select public.is_admin()));
comment on table public.committees is '0145: the barangay''s committees, made and edited by a super admin (committee_save). Switched off = not created.';
comment on table public.committee_categories is '0145: the categories each committee sees (committee_set_categories).';

create or replace function public._committee_label(p text)
returns text
language sql stable set search_path = public as $$
  select coalesce((select name_en from public.committees where key = p), p, '')
$$;

-- ---------- the tier of each administrator ----------------------------------

alter table public.users
  add column if not exists admin_tier text check (admin_tier in ('super', 'committee', 'captain')),
  add column if not exists is_dev boolean not null default false;
comment on column public.users.admin_tier is '0145: super (everything), committee (its ticked categories), captain (sees all, changes nothing). Null on an administrator reads as committee. Set only by set_admin_access().';
comment on column public.users.is_dev is '0145: a member of the development team (Group 12). Marked in the portal; the same powers as a super admin.';

-- the administrators that exist today (the development team) keep doing everything
update public.users set admin_tier = 'super' where role = 'admin';
update public.users set is_dev = true where role = 'admin';

-- the tier, the committee and the developer mark change only through set_admin_access() or by a super admin (set_official_role
-- sets a kagawad's committee): an administrator can update their own row, and must not be able to widen their own scope
create or replace function public._guard_admin_access()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.admin_tier is distinct from old.admin_tier or new.is_dev is distinct from old.is_dev or new.committee is distinct from old.committee)
     and auth.uid() is not null
     and coalesce(current_setting('smartsumbong.admin_access', true), 'off') <> 'on'
     and not public.is_super_admin() then
    raise exception 'An administrator''s access is changed in Settings, by a super admin' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
revoke all on function public._guard_admin_access() from public, anon, authenticated;
create trigger users_guard_admin_access before update on public.users for each row execute function public._guard_admin_access();

-- ---------- the helpers -------------------------------------------------------

/** The tier of the signed-in administrator, or null for anyone else (and a suspended administrator). */
create or replace function public.admin_tier()
returns text
language sql stable security definer set search_path = public as $$
  select case when u.role = 'admin' and not coalesce(u.is_suspended, false) then coalesce(u.admin_tier, 'committee') end
    from public.users u where u.id = auth.uid()
$$;
create or replace function public.is_super_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.admin_tier() = 'super', false) $$;
create or replace function public.is_full_viewer() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.admin_tier() in ('super', 'captain'), false) $$;
create or replace function public.admin_can_write() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.admin_tier() in ('super', 'committee'), false) $$;

/** Whether this user (an administrator) sees a category: super and captain see all, a committee admin what its active committee ticked. */
create or replace function public._user_sees_category(p_user uuid, p_cat public.complaint_category)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when u.role <> 'admin' or coalesce(u.is_suspended, false) then false
    when coalesce(u.admin_tier, 'committee') in ('super', 'captain') then true
    else exists (select 1 from public.committees c join public.committee_categories cc on cc.committee = c.key
                  where c.key = u.committee and c.active and cc.category = p_cat)
  end
    from public.users u where u.id = p_user
$$;

/** Whether this user sees a case: its category, any of its concerns' categories, or because they handle it. */
create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public._user_sees_category(p_user, p_cat), false)
      or (p_handler is not null and p_handler = p_user)
      or exists (select 1 from public.report_concerns rc where rc.report_id = p_report and public._user_sees_category(p_user, rc.category))
$$;

create or replace function public.admin_sees_category(p_cat public.complaint_category) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public._user_sees_category(auth.uid(), p_cat), false) $$;
create or replace function public.admin_sees_case(p_report uuid, p_cat public.complaint_category, p_handler uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public._user_sees_case(auth.uid(), p_report, p_cat, p_handler), false) $$;
/** A case by its id; for a row with no case (null), only super admins and captains. */
create or replace function public.admin_sees_report(p_report uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_report is null then public.is_full_viewer()
              else coalesce((select public._user_sees_case(auth.uid(), r.id, r.category, r.handler_id) from public.reports r where r.id = p_report), false) end $$;
create or replace function public.admin_sees_dispatch(p_dispatch uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.admin_sees_report((select d.report_id from public.dispatches d where d.id = p_dispatch)) $$;

/** At the top of everything an administrator does to a case: a captain changes nothing, a committee admin only its own cases.
    Residents, tanods and the system's own jobs pass (the function's own rules apply to them). */
create or replace function public._scope_guard(p_report uuid, p_write boolean)
returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin() then return; end if;
  if p_write and not public.admin_can_write() then
    raise exception 'This account can look at cases but not change them.' using errcode = 'insufficient_privilege';
  end if;
  if p_report is not null and not public.admin_sees_report(p_report) then
    raise exception 'This case is outside your committee.' using errcode = 'insufficient_privilege';
  end if;
end $$;

revoke all on function public._user_sees_category(uuid, public.complaint_category), public._user_sees_case(uuid, uuid, public.complaint_category, uuid),
  public._scope_guard(uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_tier(), public.is_super_admin(), public.is_full_viewer(), public.admin_can_write(),
  public.admin_sees_category(public.complaint_category), public.admin_sees_case(uuid, public.complaint_category, uuid),
  public.admin_sees_report(uuid), public.admin_sees_dispatch(uuid) from public, anon;
grant execute on function public.admin_tier(), public.is_super_admin(), public.is_full_viewer(), public.admin_can_write(),
  public.admin_sees_category(public.complaint_category), public.admin_sees_case(uuid, public.complaint_category, uuid),
  public.admin_sees_report(uuid), public.admin_sees_dispatch(uuid) to authenticated;

-- ---------- reading: reports and what hangs off them ---------------------------

do $$
declare
  p record; v_using text; v_check text; v_new text; v_tok text;
  -- what replaces "is the user an administrator" in each read policy
  t_map jsonb := jsonb_build_object(
    'reports',              'public.admin_sees_case(reports.id, reports.category, reports.handler_id)',
    'case_handler_log',     'public.admin_sees_report(case_handler_log.report_id)',
    'detail_requests',      'public.admin_sees_report(detail_requests.report_id)',
    'dispatches',           'public.admin_sees_report(dispatches.report_id)',
    'dispatch_media',       'public.admin_sees_dispatch(dispatch_media.dispatch_id)',
    'dispatch_updates',     'public.admin_sees_dispatch(dispatch_updates.dispatch_id)',
    'escalation_requests',  'public.admin_sees_report(escalation_requests.report_id)',
    'feedback',             'public.admin_sees_report(feedback.report_id)',
    'report_concerns',      'public.admin_sees_report(report_concerns.report_id)',
    'report_evidence',      'public.admin_sees_report(report_evidence.report_id)',
    'report_media',         'public.admin_sees_report(report_media.report_id)',
    'report_messages',      'public.admin_sees_report(report_messages.report_id)',
    'report_triage',        'public.admin_sees_report(report_triage.report_id)',
    'resolution_checks',    'public.admin_sees_report(resolution_checks.report_id)',
    'sla_extensions',       'public.admin_sees_report(sla_extensions.report_id)',
    'status_logs',          'public.admin_sees_report(status_logs.report_id)',
    'smart_events',         'public.admin_sees_report(smart_events.report_id)',
    'smart_overrides',      'public.admin_sees_report(smart_overrides.report_id)');
begin
  for p in select c.relname::text t, p.polname::text pol, pg_get_expr(p.polqual, p.polrelid) u
             from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relnamespace = 'public'::regnamespace and p.polcmd = 'r' and t_map ? c.relname::text
              and pg_get_expr(p.polqual, p.polrelid) like '%is_admin()%' loop
    v_tok := t_map ->> p.t;
    v_new := replace(replace(replace(replace(p.u, '( SELECT public.is_admin() AS is_admin)', v_tok), '( SELECT is_admin() AS is_admin)', v_tok), 'public.is_admin()', 'is_admin()'), 'is_admin()', v_tok);
    if v_new = p.u or v_new like '%is_admin()%' then raise exception 'read policy % on % not rewritten', p.pol, p.t; end if;
    execute format('alter policy %I on public.%I using (%s)', p.pol, p.t, v_new);
  end loop;
end $$;

-- a notification about a case outside a committee admin's scope is never made for them (nor pushed)
create or replace function public._notifications_scope()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_role text; v_tier text;
begin
  if new.report_id is null then return new; end if;
  select role::text, coalesce(admin_tier, 'committee') into v_role, v_tier from public.users where id = new.user_id;
  if v_role = 'admin' and v_tier = 'committee'
     and not coalesce((select public._user_sees_case(new.user_id, r.id, r.category, r.handler_id) from public.reports r where r.id = new.report_id), false) then
    return null;
  end if;
  return new;
end $$;
revoke all on function public._notifications_scope() from public, anon, authenticated;
create trigger notifications_scope before insert on public.notifications for each row execute function public._notifications_scope();

-- ---------- writing --------------------------------------------------------------

-- the case tables: a read policy stays as above; the writes need write access and the case in scope
alter policy reports_admin_update on public.reports
  using ((select public.admin_can_write()) and public.admin_sees_case(reports.id, reports.category, reports.handler_id))
  with check ((select public.admin_can_write()) and public.admin_sees_case(reports.id, reports.category, reports.handler_id));
alter policy status_logs_insert on public.status_logs
  with check ((select public.admin_can_write()) and public.admin_sees_report(status_logs.report_id) and changed_by = (select auth.uid()) and is_system = false);

do $$
declare t text; f text; cmd text; v_cond text;
begin
  -- "for all" policies that mixed reading and writing: split, so a captain keeps reading and loses writing
  foreach t in array array['dispatches', 'look_shares', 'sla_extensions'] loop
    v_cond := format('(select public.admin_can_write()) and public.admin_sees_report(%I.report_id)', t);
    execute format('drop policy if exists %I on public.%I', case t when 'dispatches' then 'dispatches_admin_write' when 'look_shares' then 'look_shares_admin_all' else 'sla_extensions_admin' end, t);
    execute format('create policy %I on public.%I for insert with check (%s)', t || '_admin_insert', t, v_cond || case t when 'look_shares' then ' and sent_by = (select auth.uid())' else '' end);
    execute format('create policy %I on public.%I for update using (%s) with check (%s)', t || '_admin_update', t, v_cond, v_cond);
    execute format('create policy %I on public.%I for delete using (%s)', t || '_admin_delete', t, v_cond);
  end loop;
  -- look_shares lost its only admin read with "for all": read in scope
  execute 'create policy look_shares_admin_read on public.look_shares for select using (public.admin_sees_report(look_shares.report_id))';

  -- settings and accounts: written by super admins only, still read by every administrator
  foreach t in array array['committee_for_category', 'hotline_groups', 'hotline_numbers', 'sla_policies', 'retirement_requests', 'users', 'smart_lexicon'] loop
    f := case t when 'committee_for_category' then 'committee_for_category_admin' when 'hotline_groups' then 'hotline_groups_write'
                when 'hotline_numbers' then 'hotline_numbers_write' when 'sla_policies' then 'sla_policies_admin'
                when 'retirement_requests' then 'retirement_requests_admin_write' when 'users' then 'users_admin_all' else 'smart_lexicon_admin_write' end;
    execute format('drop policy if exists %I on public.%I', f, t);
    if t in ('committee_for_category', 'sla_policies') then
      execute format('create policy %I on public.%I for select using ((select public.is_admin()))', t || '_admin_read', t);
    end if;
    execute format('create policy %I on public.%I for insert with check ((select public.is_super_admin()))', t || '_super_insert', t);
    execute format('create policy %I on public.%I for update using ((select public.is_super_admin())) with check ((select public.is_super_admin()))', t || '_super_update', t);
    execute format('create policy %I on public.%I for delete using ((select public.is_super_admin()))', t || '_super_delete', t);
  end loop;
  -- hotlines are also read by everyone through their own read policies; retirement_requests, users and smart_lexicon keep theirs
  alter policy settings_write on public.operational_settings using ((select public.is_super_admin())) with check ((select public.is_super_admin()));
  alter policy smart_rules_admin_write on public.smart_rules using ((select public.is_super_admin())) with check ((select public.is_super_admin()));
end $$;

-- the other writes: the staff records to super admins, the operational ones to anyone who can write (not a captain)
do $$
declare p record; v_tok text; v_u text; v_c text;
begin
  for p in select c.relname::text t, p.polname::text pol, p.polcmd cmd, pg_get_expr(p.polqual, p.polrelid) u, pg_get_expr(p.polwithcheck, p.polrelid) c
             from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relnamespace = 'public'::regnamespace and p.polcmd in ('a', 'w', 'd')
              and c.relname in ('staff_credentials', 'staff_dates', 'staff_leave', 'checkpoint_scans', 'duty_roster', 'patrol_checkpoints',
                                'poll_votes', 'polls', 'relief_tally', 'shift_checkins', 'team_posts', 'team_post_reads')
              and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')) like '%is_admin()%' loop
    v_tok := case when p.t like 'staff\_%' then '(select public.is_super_admin())' else '(select public.admin_can_write())' end;
    v_u := replace(replace(p.u, '( SELECT public.is_admin() AS is_admin)', v_tok), '( SELECT is_admin() AS is_admin)', v_tok);
    v_c := replace(replace(p.c, '( SELECT public.is_admin() AS is_admin)', v_tok), '( SELECT is_admin() AS is_admin)', v_tok);
    if p.cmd = 'a' then execute format('alter policy %I on public.%I with check (%s)', p.pol, p.t, v_c);
    elsif p.cmd = 'd' then execute format('alter policy %I on public.%I using (%s)', p.pol, p.t, v_u);
    elsif p.c is null then execute format('alter policy %I on public.%I using (%s)', p.pol, p.t, v_u);
    else execute format('alter policy %I on public.%I using (%s) with check (%s)', p.pol, p.t, v_u, v_c);
    end if;
  end loop;
end $$;

-- a trigger on reports for what changes a case without going through a policy (the functions run as their owner)
create or replace function public._reports_scope_row()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._scope_guard(new.id, true);
  return new;
end $$;
revoke all on function public._reports_scope_row() from public, anon, authenticated;
create trigger reports_scope before update on public.reports for each row execute function public._reports_scope_row();

-- ---------- the functions, by group ------------------------------------------------

do $$
declare
  g record; f record; v_def text; v_new text; v_pos integer; n integer := 0;
  -- chosen before anything is rewritten: the group step below changes the very text this looks for
  v_case_fns oid[] := array(select p.oid from pg_proc p join pg_language l on l.oid = p.prolang
                             where p.pronamespace = 'public'::regnamespace and p.prosecdef and l.lanname = 'plpgsql' and 'p_report' = any (p.proargnames)
                               and pg_get_functiondef(p.oid) ilike '%is_admin()%' and p.proname <> '_scope_guard');
begin
  for g in select * from (values
    -- settings, accounts, the engine's rules: super admins
    ('super', array['admin_reset_password', 'admin_update_user', 'create_admin_account', 'decide_profile_request', 'feature_set', 'finalize_retirement',
                    'place_remove', 'place_save', 'promote_to_admin', 'request_ocr_rescan', 'reset_admin_password', 'set_account_suspension',
                    'set_official_role', 'smart_rollback', 'smart_save_rules', 'smart_storm_mode', 'smart_teach_word', 'smart_workorder_create',
                    'smart_workorder_set', 'verify_user_account', 'smart_verify', 'smart_verify_queue', 'command_set_auto',
                    'command_display_link_create', 'command_display_link_revoke', 'command_dismiss']),
    -- the barangay-wide numbers and analytics: super admins and captains
    ('viewer', array['smart_calibration', 'smart_deadline_risk', 'smart_digest_preview', 'smart_engine_health', 'smart_factor_stats', 'smart_fairness',
                     'smart_fix_stats', 'smart_forecast', 'smart_patterns', 'smart_pick_stats', 'smart_replay', 'smart_roster_suggestion',
                     'smart_rule_history', 'smart_sla_scorecard', 'smart_spikes', 'smart_stuck_cases', 'smart_summary', 'smart_time_patterns',
                     'smart_word_suggestions', 'engine_status', 'portal_uptime_summary', 'system_usage', 'workspace_activity', 'workspace_alarm_db',
                     'workspace_find', 'workspace_numbers', 'workspace_photos', 'workspace_risk', 'workspace_team', 'command_board', 'command_feed',
                     'command_suggest']),
    -- the case actions: those who can write (not a captain); the case itself is checked by the scope guard below
    ('writer', array['admin_barangay_update', 'admin_dispatch', 'admin_reroute_dispatch', 'admin_set_status', 'appeal_report', 'approve_escalation',
                     'approve_resolution', 'deny_escalation', 'escalate_in_barangay', 'hand_to_higher_official', 'refer_report', 'reject_resolution',
                     'release_case', 'reopen_report', 'return_from_official', 'review_report', 'set_case_sensitive', 'set_concern_status',
                     'set_report_public', 'set_resolution_target', 'smart_override', 'smart_retriage', 'take_case', 'take_over_case',
                     'cancel_admin_handover', 'command_start', 'command_end', 'command_handover', 'command_check', 'command_place_check'])
  ) as t(grp, names) loop
    if (select count(distinct p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (g.names)) <> array_length(g.names, 1) then
      raise exception 'missing functions in group %: %', g.grp,
        (select string_agg(x, ', ') from unnest(g.names) x where not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = x));
    end if;
    for f in select p.oid, p.proname::text nm from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (g.names) loop
      v_def := replace(pg_get_functiondef(f.oid), E'\r', '');
      v_new := replace(v_def, 'not public.is_admin()', 'not public.' || case g.grp when 'super' then 'is_super_admin' when 'viewer' then 'is_full_viewer' else 'admin_can_write' end || '()');
      if v_new = v_def then raise exception 'no admin check to change in %', f.nm; end if;
      execute v_new; n := n + 1;
    end loop;
  end loop;

  -- every function that works on one case checks the case is in scope (and, for a change, that the account may write)
  if coalesce(array_length(v_case_fns, 1), 0) < 25 then raise exception 'only % case functions found', coalesce(array_length(v_case_fns, 1), 0); end if;
  for f in select p.oid, p.proname::text nm from pg_proc p where p.oid = any (v_case_fns) loop
    v_def := replace(pg_get_functiondef(f.oid), E'\r', '');
    v_pos := position(E'\nbegin\n' in v_def);
    if v_pos = 0 then raise exception 'no begin in %', f.nm; end if;
    v_new := substr(v_def, 1, v_pos + 6)
             || format(E'  perform public._scope_guard(p_report, %s);\n',
                       case when f.nm in ('smart_case_card', 'smart_duplicates', 'smart_similar_cases', 'smart_tanod_ranking', 'smart_why_order', 'verify_report_trail') then 'false' else 'true' end)
             || substr(v_def, v_pos + 7);
    execute v_new; n := n + 1;
  end loop;

  -- the actions that take a dispatch or an escalation request rather than a case
  for f in select * from (values
    ('public.admin_reroute_dispatch(uuid,text,uuid)'::regprocedure, '(select d.report_id from public.dispatches d where d.id = p_dispatch)'),
    ('public.approve_escalation(uuid,text,text)'::regprocedure,     '(select e.report_id from public.escalation_requests e where e.id = p_request)'),
    ('public.deny_escalation(uuid,text)'::regprocedure,             '(select e.report_id from public.escalation_requests e where e.id = p_request)')
  ) as x(fn, expr) loop
    v_def := replace(pg_get_functiondef(f.fn), E'\r', '');
    v_pos := position(E'\nbegin\n' in v_def);
    if v_pos = 0 then raise exception 'no begin in %', f.fn; end if;
    execute substr(v_def, 1, v_pos + 6) || format(E'  perform public._scope_guard(%s, true);\n', f.expr) || substr(v_def, v_pos + 7);
    n := n + 1;
  end loop;

  -- the queue lists only the cases in scope
  v_def := replace(pg_get_functiondef('public.smart_queue(text,integer)'::regprocedure), E'\r', '');
  v_new := replace(v_def, 'where p_stage is null or q.stage = p_stage', 'where (p_stage is null or q.stage = p_stage) and public.admin_sees_category(q.category)');
  if v_new = v_def then raise exception 'smart_queue not patched'; end if;
  execute v_new;
  raise notice '0145: % functions given their tier or scope check', n;
end $$;

-- ---------- what a super admin does here ----------------------------------------------

/** Make a committee (p_key null) or change one: its names, whether it is on. Returns its key. */
create or replace function public.committee_save(p_key text, p_name_en text, p_name_fil text, p_active boolean default true)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_key text := nullif(trim(coalesce(p_key, '')), ''); v_en text := nullif(trim(coalesce(p_name_en, '')), ''); v_fil text := nullif(trim(coalesce(p_name_fil, '')), '');
begin
  if not public.is_super_admin() then raise exception 'Only a super admin sets up committees' using errcode = 'insufficient_privilege'; end if;
  if v_en is null or char_length(v_en) < 3 then raise exception 'Name the committee' using errcode = 'check_violation'; end if;
  v_fil := coalesce(v_fil, v_en);
  if v_key is null then
    v_key := left(trim(both '_' from regexp_replace(lower(translate(v_en, 'ñÑáéíóúÁÉÍÓÚ', 'nNaeiouAEIOU')), '[^a-z0-9]+', '_', 'g')), 40);
    if v_key !~ '^[a-z]' then v_key := 'c_' || v_key; end if;
    if exists (select 1 from public.committees where key = v_key) then v_key := left(v_key, 34) || '_' || substr(md5(random()::text), 1, 5); end if;
    insert into public.committees (key, name_en, name_fil, active, sort, updated_by)
    values (v_key, left(v_en, 120), left(v_fil, 120), coalesce(p_active, true), coalesce((select max(sort) + 1 from public.committees where active), 1), auth.uid());
  else
    update public.committees set name_en = left(v_en, 120), name_fil = left(v_fil, 120), active = coalesce(p_active, active), updated_by = auth.uid(), updated_at = now()
     where key = v_key;
    if not found then raise exception 'No such committee' using errcode = 'check_violation'; end if;
  end if;
  perform public._smart_event('access', null, format('Committee saved: %s', left(v_en, 120)), jsonb_build_object('committee', v_key, 'active', coalesce(p_active, true)));
  return v_key;
end $$;

/** Tick the categories a committee sees (the list replaces the old one). */
create or replace function public.committee_set_categories(p_key text, p_categories public.complaint_category[])
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_super_admin() then raise exception 'Only a super admin sets what a committee sees' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.committees where key = p_key) then raise exception 'No such committee' using errcode = 'check_violation'; end if;
  delete from public.committee_categories where committee = p_key;
  insert into public.committee_categories (committee, category) select p_key, c from unnest(coalesce(p_categories, '{}')) c group by c;
  perform public._smart_event('access', null, format('What %s sees: %s categories', p_key, coalesce(array_length(p_categories, 1), 0)), jsonb_build_object('committee', p_key, 'categories', to_jsonb(p_categories)));
end $$;

/** An administrator's tier, committee and developer mark. There is always at least one super admin. */
create or replace function public.set_admin_access(p_user uuid, p_tier text, p_committee text default null, p_dev boolean default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u public.users%rowtype;
begin
  if not public.is_super_admin() then raise exception 'Only a super admin changes an administrator''s access' using errcode = 'insufficient_privilege'; end if;
  if p_tier not in ('super', 'committee', 'captain') then raise exception 'Tier is super, committee or captain' using errcode = 'check_violation'; end if;
  select * into u from public.users where id = p_user;
  if not found or u.role <> 'admin' then raise exception 'That account is not an administrator' using errcode = 'check_violation'; end if;
  if p_tier = 'committee' and (p_committee is null or not exists (select 1 from public.committees where key = p_committee)) then
    raise exception 'Choose the committee' using errcode = 'check_violation';
  end if;
  if coalesce(u.admin_tier, 'committee') = 'super' and p_tier <> 'super'
     and not exists (select 1 from public.users x where x.role = 'admin' and x.admin_tier = 'super' and not coalesce(x.is_suspended, false) and x.id <> p_user) then
    raise exception 'There must always be one super admin' using errcode = 'check_violation';
  end if;
  perform set_config('smartsumbong.admin_access', 'on', true);
  update public.users set admin_tier = p_tier, committee = case when p_tier = 'committee' then p_committee else committee end,
         is_dev = coalesce(p_dev, is_dev)
   where id = p_user;
  perform set_config('smartsumbong.admin_access', 'off', true);
  perform public._smart_event('access', null, format('%s is now %s%s', public.display_name(u.full_name), p_tier,
          case when p_tier = 'committee' then ' (' || public._committee_label(p_committee) || ')' else '' end), jsonb_build_object('user', p_user, 'tier', p_tier, 'committee', p_committee, 'dev', p_dev));
end $$;

revoke all on function public.committee_save(text, text, text, boolean), public.committee_set_categories(text, public.complaint_category[]),
  public.set_admin_access(uuid, text, text, boolean) from public, anon;
grant execute on function public.committee_save(text, text, text, boolean), public.committee_set_categories(text, public.complaint_category[]),
  public.set_admin_access(uuid, text, text, boolean) to authenticated;
