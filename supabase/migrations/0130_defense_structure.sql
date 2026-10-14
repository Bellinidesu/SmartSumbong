-- 0130 — What the capstone panel asked for (defense, 7 Sep 2026; docs/DEFENSE_ASKS.md).
--
-- 1. THE BARANGAY'S OWN STRUCTURE. "Dapat layered": the Tanod, then a Kagawad
--    (each Kagawad chairs a committee: peace and order, health, environment...),
--    then the Chairman. An administrator account can now carry an official role
--    (secretary, kagawad, chairman) and a committee; tanods can be marked as
--    designated women responders. committee_for_category says which committee
--    usually takes which kind of complaint (defaults, editable by an admin).
--
-- 2. THE LADDER. escalate_in_barangay hands an open case up one step: the
--    Kagawad of the right committee (the one with the fewest open cases), then
--    the Chairman. The official becomes the case's handler (one handler per
--    case, 0087), any tanod on it is stood down and told, the resident is told
--    who has it now, and every step is on the record. return_from_official
--    sends it back down. Nothing here moves a case by itself.
--
-- 3. SEVERAL CONCERNS IN ONE REPORT. "Dapat multiple": delayed response AND
--    duty negligence in one report. reports.category stays the main kind;
--    report_concerns holds one row per concern (the main one included), each
--    open or resolved on its own, with the admin's remark.
--
-- 4. SENSITIVE CASES. VAWC and the like must be elevated, not sent to the
--    nearest tanod. reports.is_sensitive is set on filing from the words used
--    (an admin can set or clear it, with a reason) and the waiting line
--    (sweep_awaiting_units) no longer sends a sensitive case to a tanod by
--    itself: the committee for it is Women and Family.
--
-- Adds: users.official_role, users.committee, users.women_responder;
-- committee_for_category; reports.tier, tier_path, escalated_at, is_sensitive;
-- report_concerns; case_handler_log actions escalate and return.

set search_path = public, extensions;

-- ---------- 1. positions -------------------------------------------------------------------

alter table public.users
  add column if not exists official_role   text check (official_role in ('secretary', 'kagawad', 'chairman')),
  add column if not exists committee       text check (committee in ('peace_order', 'health_sanitation', 'education', 'infrastructure',
                                                                     'environment', 'women_family', 'youth_sports', 'agriculture', 'appropriations')),
  add column if not exists women_responder boolean not null default false;

comment on column public.users.official_role is
  '0130: the barangay position of an administrator account: secretary, kagawad or chairman. Set only by set_official_role().';
comment on column public.users.committee is '0130: the committee a Kagawad chairs.';
comment on column public.users.women_responder is
  '0130: a tanod designated to respond to women and children cases (VAWC desk). Set only by set_official_role().';

create or replace function public._guard_official_fields()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.official_role is distinct from old.official_role
     or new.committee is distinct from old.committee
     or new.women_responder is distinct from old.women_responder then
    raise exception 'Only an administrator may change a position, a committee or a responder designation';
  end if;
  return new;
end $$;

drop trigger if exists guard_official_fields on public.users;
create trigger guard_official_fields before update on public.users
  for each row execute function public._guard_official_fields();

/** Admins: give an account its position. A Kagawad needs a committee; there is one Chairman.
    A tanod can only be marked as a women responder. Pass null to clear. */
create or replace function public.set_official_role(
  p_user uuid, p_role text, p_committee text default null, p_women boolean default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  u public.users%rowtype;
begin
  if not public.is_admin() then
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
  if p_role = 'chairman' and exists (select 1 from public.users x where x.official_role = 'chairman' and x.id <> p_user) then
    raise exception 'There is already a Chairman account' using errcode = 'check_violation';
  end if;
  if p_women is not null and p_women and u.role <> 'tanod' then
    raise exception 'Only a tanod can be a designated women responder' using errcode = 'check_violation';
  end if;
  update public.users
     set official_role   = p_role,
         committee       = case when p_role = 'kagawad' then p_committee else null end,
         women_responder = coalesce(p_women, women_responder)
   where id = p_user;
end $$;

revoke all on function public.set_official_role(uuid, text, text, boolean) from public, anon;
grant execute on function public.set_official_role(uuid, text, text, boolean) to authenticated;

-- ---------- which committee takes what -------------------------------------------------------

create table if not exists public.committee_for_category (
  category  public.complaint_category primary key,
  committee text not null check (committee in ('peace_order', 'health_sanitation', 'education', 'infrastructure',
                                               'environment', 'women_family', 'youth_sports', 'agriculture', 'appropriations'))
);
insert into public.committee_for_category (category, committee) values
  ('street_obstruction',           'peace_order'),
  ('public_safety_infrastructure', 'infrastructure'),
  ('environmental_waste_hazard',   'environment'),
  ('animal_welfare',               'health_sanitation'),
  ('traffic_violation',            'peace_order'),
  ('barangay_service',             'appropriations'),
  ('peace_order_nuisance',         'peace_order'),
  ('other',                        'peace_order')
on conflict (category) do nothing;
alter table public.committee_for_category enable row level security;
drop policy if exists committee_for_category_admin on public.committee_for_category;
create policy committee_for_category_admin on public.committee_for_category for all
  using ((select public.is_admin())) with check ((select public.is_admin()));
comment on table public.committee_for_category is
  '0130: the committee that usually takes each kind of complaint. Defaults to confirm with the barangay; an admin can change them.';

-- ---------- reports: the ladder and the sensitive flag ---------------------------------------

alter table public.reports
  add column if not exists tier         smallint    not null default 0 check (tier between 0 and 2),
  add column if not exists tier_path    uuid[]      not null default '{}',
  add column if not exists escalated_at timestamptz,
  add column if not exists is_sensitive boolean     not null default false;

comment on column public.reports.tier is '0130: 0 barangay staff and tanods, 1 a Kagawad, 2 the Chairman.';
comment on column public.reports.tier_path is '0130: who held the case on each step below, so a return goes back down the same way.';
comment on column public.reports.is_sensitive is '0130: VAWC and similar: elevated to a committee, not sent to the nearest tanod.';

alter table public.case_handler_log drop constraint if exists case_handler_log_action_check;
alter table public.case_handler_log add constraint case_handler_log_action_check
  check (action in ('take', 'release', 'take_over', 'escalate', 'return'));

/** The words that make a report sensitive, whole words only, English and Tagalog. */
create or replace function public._is_sensitive_text(p_text text)
returns boolean
language sql
immutable
parallel safe
set search_path = public, extensions
as $$
  select coalesce(lower(p_text) ~ '\y(vawc|domestic violence|child abuse|abuso|pang-?aabuso|rape|ginahasa|panggagahasa|molest|nang-?molestiya|sexual|harass(ed|ment)?|binubugbog|sinasaktan ng (asawa|mister|partner)|battered|incest)\y', false)
$$;

create or replace function public._flag_sensitive()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if not new.is_sensitive and public._is_sensitive_text(coalesce(new.subject, '') || ' ' || coalesce(new.description, '')) then
    new.is_sensitive := true;
  end if;
  return new;
end $$;

drop trigger if exists flag_sensitive on public.reports;
create trigger flag_sensitive before insert on public.reports
  for each row execute function public._flag_sensitive();

/** The handler sets or clears the flag, with a reason that goes on the record. */
create or replace function public.set_case_sensitive(p_report uuid, p_on boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  r public.reports%rowtype;
begin
  if not public.is_admin() then raise exception 'Only an administrator may change this' using errcode = 'insufficient_privilege'; end if;
  if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Say why, in a few words';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then raise exception 'No such report'; end if;
  perform public._case_guard(p_report);
  update public.reports set is_sensitive = coalesce(p_on, false) where id = p_report;
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), r.status, r.status,
          case when coalesce(p_on, false) then 'Marked sensitive: ' else 'Sensitive mark removed: ' end || v_reason);
end $$;

revoke all on function public.set_case_sensitive(uuid, boolean, text) from public, anon;
grant execute on function public.set_case_sensitive(uuid, boolean, text) to authenticated;

-- ---------- 2. the ladder ---------------------------------------------------------------------

create or replace function public._committee_label(p text)
returns text language sql immutable set search_path = public as $$
  select case p when 'peace_order' then 'Peace and Order' when 'health_sanitation' then 'Health and Sanitation'
                when 'education' then 'Education' when 'infrastructure' then 'Infrastructure'
                when 'environment' then 'Environment' when 'women_family' then 'Women and Family'
                when 'youth_sports' then 'Youth and Sports' when 'agriculture' then 'Agriculture'
                when 'appropriations' then 'Appropriations' else coalesce(p, '') end
$$;

/** The handler hands an open case up one step: a Kagawad (the committee for its kind of complaint, or p_committee),
    then the Chairman. The official becomes its handler. */
create or replace function public.escalate_in_barangay(p_report uuid, p_reason text, p_committee text default null)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r         public.reports%rowtype;
  v_reason  text := nullif(trim(coalesce(p_reason, '')), '');
  v_tier    smallint;
  v_off     uuid;
  v_comm    text;
  v_name    text;
  v_label   text;
  d         record;
  v_new_status public.report_status;
begin
  if not public.is_admin() then raise exception 'Only an administrator may escalate a case' using errcode = 'insufficient_privilege'; end if;
  if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Give a reason (3 to 300 characters)';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if r.status in ('resolved', 'closed', 'archived', 'rejected', 'cancelled') or r.referred_to is not null then
    raise exception 'Only an open case that is still with the barangay can be escalated';
  end if;
  if r.handler_id is not null and r.handler_id <> auth.uid() then
    raise exception 'Someone else is handling this case. Take it over to escalate it.';
  end if;
  v_tier := r.tier + 1;
  if v_tier > 2 then
    raise exception 'The case is already with the Chairman. Refer it to an outside office instead.';
  end if;

  v_comm := coalesce(p_committee, case when r.is_sensitive then 'women_family' end,
                     (select c.committee from public.committee_for_category c where c.category = r.category));

  if v_tier = 1 then
    select u.id into v_off
      from public.users u
     where u.role = 'admin' and u.official_role = 'kagawad' and not u.is_suspended and u.id <> auth.uid()
     order by (u.committee is not distinct from v_comm) desc,
              (select count(*) from public.reports x
                where x.handler_id = u.id and x.deleted_at is null
                  and x.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')) asc,
              u.full_name
     limit 1;
    if v_off is null then raise exception 'No Kagawad account is set up yet. Add one first (Settings, Barangay officials).'; end if;
    v_label := 'Kagawad';
  else
    select u.id into v_off from public.users u
     where u.role = 'admin' and u.official_role = 'chairman' and not u.is_suspended and u.id <> auth.uid() limit 1;
    if v_off is null then raise exception 'No Chairman account is set up yet. Add one first (Settings, Barangay officials).'; end if;
    v_label := 'Chairman';
  end if;
  select public.display_name(full_name), committee into v_name, v_comm from public.users where id = v_off;
  if v_tier = 1 then v_label := 'Kagawad (' || public._committee_label(v_comm) || ')'; end if;

  v_new_status := case when r.status in ('validated', 'assigned') then 'in_progress'::public.report_status else r.status end;

  perform set_config('smartsumbong.handler_change', 'on', true);

  -- whoever is on it in the field is stood down and told
  for d in select id, tanod_id from public.dispatches where report_id = p_report and state in ('assigned', 'accepted') loop
    update public.dispatches set state = 'rerouted', rerouted_at = now(), reroute_reason = 'Escalated to ' || v_name where id = d.id;
    insert into public.notifications (user_id, report_id, kind, message)
    values (d.tanod_id, p_report, 'reroute', r.tracking_id || ' was escalated to ' || v_name || '. You no longer need to act on it.');
  end loop;

  update public.reports
     set handler_id = v_off, handled_since = now(), tier = v_tier, escalated_at = now(),
         tier_path = tier_path || coalesce(r.handler_id, auth.uid()),
         higher_official = v_name || ' (' || v_label || ')', higher_official_note = v_reason, handed_up_at = now(),
         status = v_new_status
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), r.status, v_new_status, format('Escalated to %s, %s: %s', v_name, v_label, v_reason));
  insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
  values (p_report, auth.uid(), 'escalate', r.handler_id, v_reason);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_off, p_report, 'escalation', r.tracking_id || ' was escalated to you (' || v_label || '): ' || v_reason);
  insert into public.notifications (user_id, report_id, kind, message)
  values (r.resident_id, p_report, 'status_change',
          'Your complaint ' || r.tracking_id || ' has been passed up to ' || v_name || ', ' || v_label || ', who is now handling it.');

  perform set_config('smartsumbong.handler_change', 'off', true);
  return v_off;
end $$;

revoke all on function public.escalate_in_barangay(uuid, text, text) from public, anon;
grant execute on function public.escalate_in_barangay(uuid, text, text) to authenticated;

/** The official sends the case back down one step, to whoever held it there, with a remark. */
create or replace function public.return_from_official(p_report uuid, p_remark text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r        public.reports%rowtype;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
  v_back   uuid;
  v_me     text;
begin
  if not public.is_admin() then raise exception 'Only an administrator may return a case' using errcode = 'insufficient_privilege'; end if;
  if v_remark is null or char_length(v_remark) < 3 or char_length(v_remark) > 300 then
    raise exception 'Give a remark (3 to 300 characters)';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if r.tier = 0 then raise exception 'This case has not been escalated'; end if;
  if r.handler_id is distinct from auth.uid() then raise exception 'Only the official handling this case can return it'; end if;

  v_back := r.tier_path[coalesce(array_length(r.tier_path, 1), 0)];
  select public.display_name(full_name) into v_me from public.users where id = auth.uid();

  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports
     set handler_id = v_back, handled_since = now(), tier = tier - 1,
         tier_path = case when coalesce(array_length(tier_path, 1), 0) <= 1 then '{}'::uuid[] else tier_path[1:array_length(tier_path, 1) - 1] end,
         higher_official = case when tier - 1 = 0 then null else higher_official end,
         higher_official_note = case when tier - 1 = 0 then null else higher_official_note end,
         handed_up_at = case when tier - 1 = 0 then null else handed_up_at end
   where id = p_report;
  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), r.status, r.status, format('Returned by %s: %s', coalesce(v_me, 'the official'), v_remark));
  insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
  values (p_report, auth.uid(), 'return', auth.uid(), v_remark);
  if v_back is not null then
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_back, p_report, 'status_change', r.tracking_id || ' was returned to you by ' || coalesce(v_me, 'the official') || ': ' || v_remark);
  end if;
  perform set_config('smartsumbong.handler_change', 'off', true);
end $$;

revoke all on function public.return_from_official(uuid, text) from public, anon;
grant execute on function public.return_from_official(uuid, text) to authenticated;

-- ---------- 3. several concerns in one report -----------------------------------------------------

create table if not exists public.report_concerns (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  category    public.complaint_category not null,
  note        text check (char_length(note) <= 300),
  status      text not null default 'open' check (status in ('open', 'resolved')),
  resolved_at timestamptz,
  resolved_by uuid references public.users (id),
  remark      text check (char_length(remark) <= 300),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.users (id),
  unique (report_id, category)
);
create index if not exists report_concerns_report_idx on public.report_concerns (report_id);

alter table public.report_concerns enable row level security;
drop policy if exists report_concerns_admin_read on public.report_concerns;
create policy report_concerns_admin_read on public.report_concerns for select using ((select public.is_admin()));
drop policy if exists report_concerns_owner_read on public.report_concerns;
create policy report_concerns_owner_read on public.report_concerns for select
  using (exists (select 1 from public.reports r where r.id = report_concerns.report_id and r.resident_id = (select auth.uid())));
comment on table public.report_concerns is
  '0130: one row per concern in a report (the main category included), each open or resolved on its own. Written only through the functions below.';

-- the main concern, for every existing report and every new one
insert into public.report_concerns (report_id, category, status, resolved_at, created_at, created_by)
select r.id, r.category,
       case when r.status in ('resolved', 'closed', 'archived') then 'resolved' else 'open' end,
       case when r.status in ('resolved', 'closed', 'archived') then coalesce(r.resolved_at, r.closed_at, r.updated_at) end,
       r.created_at, r.resident_id
  from public.reports r
 where r.deleted_at is null
on conflict (report_id, category) do nothing;

create or replace function public._main_concern()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.report_concerns (report_id, category, created_by) values (new.id, new.category, new.resident_id)
  on conflict (report_id, category) do nothing;
  return new;
end $$;

drop trigger if exists main_concern on public.reports;
create trigger main_concern after insert on public.reports
  for each row execute function public._main_concern();

/** Finishing the case finishes every concern still open in it. */
create or replace function public._close_concerns()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status in ('resolved', 'closed') and old.status is distinct from new.status then
    update public.report_concerns set status = 'resolved', resolved_at = now() where report_id = new.id and status = 'open';
  end if;
  return new;
end $$;

drop trigger if exists close_concerns on public.reports;
create trigger close_concerns after update of status on public.reports
  for each row execute function public._close_concerns();

/** Add a concern to a report: the resident who filed it while it is still being reviewed, or the handling admin. */
create or replace function public.add_report_concern(p_report uuid, p_category public.complaint_category, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r public.reports%rowtype;
  v_id uuid;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then raise exception 'No such report'; end if;
  if public.is_admin() then
    perform public._case_guard(p_report);
  elsif r.resident_id = auth.uid() then
    if r.status not in ('pending_review', 'validated') then
      raise exception 'A concern can be added only while the report is being reviewed';
    end if;
  else
    raise exception 'Not allowed' using errcode = 'insufficient_privilege';
  end if;
  if v_note is not null and char_length(v_note) > 300 then raise exception 'The note can be at most 300 characters'; end if;
  if exists (select 1 from public.report_concerns where report_id = p_report and category = p_category) then
    raise exception 'This report already has that concern';
  end if;
  insert into public.report_concerns (report_id, category, note, created_by) values (p_report, p_category, v_note, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.add_report_concern(uuid, public.complaint_category, text) from public, anon;
grant execute on function public.add_report_concern(uuid, public.complaint_category, text) to authenticated;

/** The handling admin marks one concern resolved (or open again), with a remark; the resident is told. */
create or replace function public.set_concern_status(p_concern uuid, p_resolved boolean, p_remark text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c public.report_concerns%rowtype;
  r public.reports%rowtype;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
begin
  if not public.is_admin() then raise exception 'Only an administrator may do this' using errcode = 'insufficient_privilege'; end if;
  select * into c from public.report_concerns where id = p_concern;
  if not found then raise exception 'No such concern'; end if;
  if v_remark is not null and char_length(v_remark) > 300 then raise exception 'The remark can be at most 300 characters'; end if;
  select * into r from public.reports where id = c.report_id;
  perform public._case_guard(c.report_id);
  update public.report_concerns
     set status = case when p_resolved then 'resolved' else 'open' end,
         resolved_at = case when p_resolved then now() end,
         resolved_by = case when p_resolved then auth.uid() end,
         remark = v_remark
   where id = p_concern;
  if p_resolved then
    insert into public.notifications (user_id, report_id, kind, message)
    values (r.resident_id, r.id, 'status_change',
            'One concern in your complaint ' || r.tracking_id || ' (' || replace(c.category::text, '_', ' ') || ') was marked resolved.'
            || coalesce(' ' || v_remark, ''));
  end if;
end $$;

revoke all on function public.set_concern_status(uuid, boolean, text) from public, anon;
grant execute on function public.set_concern_status(uuid, boolean, text) to authenticated;

-- ---------- 4. the waiting line leaves sensitive cases to people ----------------------------------

create or replace function public.sweep_awaiting_units()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_hours smallint;
  v_smart boolean;
begin
  select awaiting_alert_hours into v_hours from public.operational_settings where id = 1;

  select coalesce((select smart_queue from public.smart_rules where id = 1), false) into v_smart;

  for r in
    select rp.id, rp.awaiting_unit_since
      from public.reports rp
      left join (select q.report_id, q.priority from public._smart_queue() q) q
        on v_smart and q.report_id = rp.id
     where rp.awaiting_unit_since is not null
       and rp.deleted_at is null
       and rp.status in ('pending_review', 'validated')
     order by q.priority desc nulls last, rp.awaiting_unit_since
  loop
    if r.awaiting_unit_since < now() - make_interval(hours => v_hours)
       and not exists (
         select 1 from public.notifications n
          where n.report_id = r.id and n.kind = 'escalation') then
      insert into public.notifications (user_id, report_id, kind, message)
      select u.id, r.id, 'escalation',
             format('A report has been waiting over %s hours with no tanod on duty in range.', v_hours)
        from public.users u where u.role = 'admin';
    end if;

    -- 0130: a sensitive case (VAWC and the like) is never sent to a tanod by the waiting line: a person decides
    if not exists (select 1 from public.reports s where s.id = r.id and s.is_sensitive) then
      perform public.auto_dispatch(r.id);
    end if;
  end loop;
end $$;
