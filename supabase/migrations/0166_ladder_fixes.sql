-- 0166: the ladder, as Barangay 183 runs it (Ace's answers to the flow check, 7 Nov 2026).
--
-- 1. Staff get the five decisions (Ace: "Staff get all 5"): approving and denying a tanod's escalation request, escalating up
--    the ladder, handing a case to a higher official and referring it outside. 0151 had kept them for the Kagawad.
-- 2. Escalation follows the case and the ladder (escalation_target):
--    - a case goes to the Kagawad of the committee it is WITH NOW (0152: forwarded, or its category's), not the category's old
--      map (committee_for_category);
--    - a Kagawad escalating, a sensitive case (VAWC, domestic violence; 183 has no Women and Family committee), or a committee
--      with no Kagawad account goes straight to the Chairman ("chairman and superadmin"): the super admins are told too;
--    - the development team's test accounts (0162) never receive a real escalation.
-- 3. Staff can ask to retire (Ace: "build"): the staff member asks in the portal, their Kagawad can endorse it, a super admin
--    decides. A retired staff member's portal access ends and the cases they held are released, so none is left stuck.

-- ---------- 1. the five decisions: the 0151 guard comes off ----------
do $$
declare f record; d text; n integer := 0;
  guard constant text := E'\n  if public.admin_tier() = ''moderator'' then\n    raise exception ''Staff cannot make this decision. Ask your Kagawad.'' using errcode = ''insufficient_privilege'';\n  end if;';
begin
  for f in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('approve_escalation', 'deny_escalation', 'hand_to_higher_official', 'refer_report') loop
    d := replace(pg_get_functiondef(f.oid), E'\r', '');
    if position(guard in d) > 0 then
      execute replace(d, guard, '');
      n := n + 1;
    end if;
  end loop;
  if n <> 4 then raise exception '0166: took the staff guard off % of 4 decision functions', n; end if;
end $$;

-- ---------- 2. who a case is escalated to ----------
/**
 * The next official up the ladder for a case: one row (official, name, the tier the case reaches, the label shown, the committee,
 * why), or none when nobody can take it (no Chairman account, or the case is already with the Chairman). The case page shows it
 * before anyone presses Escalate, and escalate_in_barangay() uses the same answer, so what is shown is what happens.
 *   why: 'next' the Kagawad of the case's committee (tier 0) or the Chairman (tier 1); 'kagawad' a Kagawad escalates, so the
 *        Chairman; 'sensitive' a sensitive case goes to the Chairman; 'no_kagawad' the committee has no Kagawad account.
 */
create or replace function public.escalation_target(p_report uuid, p_committee text default null)
returns table (official uuid, official_name text, to_tier smallint, label text, committee text, why text)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  r      public.reports%rowtype;
  v_comm text;
  v_kag  boolean;
  v_off  uuid;
  v_why  text := 'next';
begin
  if not public.is_admin() then return; end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found or r.tier >= 2 then return; end if;
  if r.tier = 0 then
    v_comm := coalesce(nullif(trim(coalesce(p_committee, '')), ''), public._case_committee(p_report));
    v_kag := exists (select 1 from public.users u where u.id = auth.uid() and (u.official_role = 'kagawad' or u.admin_tier = 'committee'));
    if r.is_sensitive then
      v_why := 'sensitive';
    elsif v_kag then
      v_why := 'kagawad';
    else
      select u.id into v_off
        from public.users u
       where u.role = 'admin' and u.official_role = 'kagawad' and u.committee = v_comm and u.id <> auth.uid()
         and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false) and not coalesce(u.is_test, false)
       order by (select count(*) from public.reports x
                  where x.handler_id = u.id and x.deleted_at is null
                    and x.status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')) asc,
                u.full_name
       limit 1;
      if v_off is not null then
        return query select u.id, public.display_name(u.full_name), 1::smallint, 'Kagawad (' || public._committee_label(v_comm) || ')', v_comm, 'next'::text
                       from public.users u where u.id = v_off;
        return;
      end if;
      v_why := 'no_kagawad';
    end if;
  end if;
  return query select u.id, public.display_name(u.full_name), 2::smallint, 'Chairman'::text, null::text, v_why
                 from public.users u
                where u.role = 'admin' and u.official_role = 'chairman' and u.id <> auth.uid()
                  and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false) and not coalesce(u.is_test, false)
                limit 1;
end $$;
comment on function public.escalation_target(uuid, text) is
  'The next official up the ladder for a case (0166): the Kagawad of the committee it is with now, else the Chairman (a Kagawad escalating, a sensitive case, a committee with no Kagawad). escalate_in_barangay uses the same answer.';
revoke all on function public.escalation_target(uuid, text) from public, anon;
grant execute on function public.escalation_target(uuid, text) to authenticated;

create or replace function public.escalate_in_barangay(p_report uuid, p_reason text, p_committee text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  r            public.reports%rowtype;
  v_reason     text := nullif(trim(coalesce(p_reason, '')), '');
  t            record;
  d            record;
  v_new_status public.report_status;
  v_by         text;
begin
  perform public._scope_guard(p_report, true);
  if not public.admin_can_write() then raise exception 'Only an administrator may escalate a case' using errcode = 'insufficient_privilege'; end if;
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
  if r.tier >= 2 then
    raise exception 'The case is already with the Chairman. Refer it to an outside office instead.';
  end if;

  select * into t from public.escalation_target(p_report, p_committee) limit 1;
  if t.official is null then
    raise exception 'No Chairman account is set up yet. Give someone the Chairman position first (Administrative Services, Roles).';
  end if;

  v_new_status := case when r.status in ('validated', 'assigned') then 'in_progress'::public.report_status else r.status end;
  select public.display_name(full_name) into v_by from public.users where id = auth.uid();

  perform set_config('smartsumbong.handler_change', 'on', true);

  -- whoever is on it in the field is stood down and told
  for d in select id, tanod_id from public.dispatches where report_id = p_report and state in ('assigned', 'accepted') loop
    update public.dispatches set state = 'rerouted', rerouted_at = now(), reroute_reason = 'Escalated to ' || t.official_name where id = d.id;
    insert into public.notifications (user_id, report_id, kind, message)
    values (d.tanod_id, p_report, 'reroute', r.tracking_id || ' was escalated to ' || t.official_name || '. You no longer need to act on it.');
  end loop;

  update public.reports
     set handler_id = t.official, handled_since = now(), tier = t.to_tier, escalated_at = now(),
         tier_path = tier_path || coalesce(r.handler_id, auth.uid()),
         higher_official = t.official_name || ' (' || t.label || ')', higher_official_note = v_reason, handed_up_at = now(),
         status = v_new_status
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status, remark)
  values (p_report, auth.uid(), r.status, v_new_status,
          format('Escalated to %s, %s%s: %s', t.official_name, t.label,
                 case t.why when 'sensitive' then ' (a sensitive case)' when 'no_kagawad' then ' (the committee has no Kagawad account)' else '' end, v_reason));
  insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
  values (p_report, auth.uid(), 'escalate', r.handler_id, v_reason);

  insert into public.notifications (user_id, report_id, kind, message)
  values (t.official, p_report, 'escalation', r.tracking_id || ' was escalated to you (' || t.label || '): ' || v_reason);
  -- to the Chairman: the super admins are told as well (Ace: "chairman and superadmin")
  if t.to_tier = 2 then
    insert into public.notifications (user_id, report_id, kind, message)
    select u.id, p_report, 'escalation',
           left(format('%s was escalated to the Chairman (%s) by %s%s: %s', r.tracking_id, t.official_name, coalesce(v_by, 'an administrator'),
                       case when t.why = 'sensitive' then ', a sensitive case' else '' end, v_reason), 500)
      from public.users u
     where u.role = 'admin' and coalesce(u.admin_tier, 'super') = 'super' and u.id not in (t.official, auth.uid())
       and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false) and not coalesce(u.is_test, false);
  end if;
  insert into public.notifications (user_id, report_id, kind, message)
  values (r.resident_id, p_report, 'status_change',
          'Your complaint ' || r.tracking_id || ' has been passed up to ' || t.official_name || ', ' || t.label || ', who is now handling it.');

  perform set_config('smartsumbong.handler_change', 'off', true);
  return t.official;
end $$;
comment on function public.escalate_in_barangay(uuid, text, text) is
  'Pass a case up one rung (0130; 0166: to escalation_target(): the Kagawad of the committee it is with now, else the Chairman, with the super admins told). Staff may escalate too (0166).';

-- A return goes back to whoever held the case before (tier_path), and to their rung: a case that went straight from staff to the
-- Chairman (a sensitive case, a Kagawad's, a committee with no Kagawad) comes straight back down, not to a Kagawad's rung.
create or replace function public.return_from_official(p_report uuid, p_remark text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  r        public.reports%rowtype;
  v_remark text := nullif(trim(coalesce(p_remark, '')), '');
  v_back   uuid;
  v_me     text;
  v_len    integer;
  v_tier   smallint;
begin
  perform public._scope_guard(p_report, true);
  if not public.admin_can_write() then raise exception 'Only an administrator may return a case' using errcode = 'insufficient_privilege'; end if;
  if v_remark is null or char_length(v_remark) < 3 or char_length(v_remark) > 300 then
    raise exception 'Give a remark (3 to 300 characters)';
  end if;
  select * into r from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if r.tier = 0 then raise exception 'This case has not been escalated'; end if;
  if r.handler_id is distinct from auth.uid() then raise exception 'Only the official handling this case can return it'; end if;

  v_len  := coalesce(array_length(r.tier_path, 1), 0);
  v_back := r.tier_path[v_len];
  v_tier := greatest(0, least(r.tier - 1, v_len - 1));
  select public.display_name(full_name) into v_me from public.users where id = auth.uid();

  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports
     set handler_id = v_back, handled_since = now(), tier = v_tier,
         tier_path = case when v_len <= 1 then '{}'::uuid[] else tier_path[1:v_len - 1] end,
         higher_official = case when v_tier = 0 then null else higher_official end,
         higher_official_note = case when v_tier = 0 then null else higher_official_note end,
         handed_up_at = case when v_tier = 0 then null else handed_up_at end
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

-- ---------- 3. staff can ask to retire ----------
/** May the signed-in Kagawad see this staff member's requests? The staff member is in their committee. */
create or replace function public._kagawad_of_staff(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.admin_tier() = 'committee' and exists (
    select 1 from public.users s
     where s.id = p_user and s.role = 'admin' and coalesce(s.admin_tier, 'super') = 'moderator'
       and s.committee = (select committee from public.users where id = auth.uid()))
$$;
revoke all on function public._kagawad_of_staff(uuid) from public, anon;
grant execute on function public._kagawad_of_staff(uuid) to authenticated;

alter policy retirement_requests_read on public.retirement_requests using (
  tanod_id = (select auth.uid())
  or ((select public.is_admin()) and not (select public.admin_scoped()))
  or (select public._kagawad_of_tanod(tanod_id))
  or (select public._kagawad_of_staff(tanod_id)));
comment on column public.retirement_requests.tanod_id is 'Who asks to retire: a tanod, or (0166) a staff member. The name is kept from 0052.';

create or replace function public.request_retirement()
returns public.retirement_requests
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user  public.users%rowtype;
  v_req   public.retirement_requests%rowtype;
  v_staff boolean;
begin
  select * into v_user from public.users where id = auth.uid() for update;
  if not found then
    raise exception 'No such account';
  end if;
  v_staff := v_user.role = 'admin' and coalesce(v_user.admin_tier, 'super') = 'moderator';
  if v_user.role <> 'tanod' and not v_staff then
    raise exception 'Only a tanod or a staff member may request retirement';
  end if;
  if v_user.is_retired then
    raise exception 'This account has already retired';
  end if;
  if exists (select 1 from public.retirement_requests where tanod_id = v_user.id and status = 'pending') then
    raise exception 'A retirement request for this account is already waiting on the barangay';
  end if;

  insert into public.retirement_requests (tanod_id) values (v_user.id) returning * into v_req;

  -- the super admins decide; the Kagawad of the person's committee (a staff member's, or a tanod's approved committees) can endorse
  insert into public.notifications (user_id, kind, message, subject_user_id)
  select u.id, 'retirement', format('%s%s has requested retirement.', v_user.full_name, case when v_staff then ' (staff)' else '' end), v_user.id
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id <> v_user.id
     and (coalesce(u.admin_tier, 'super') = 'super'
          or (u.admin_tier = 'committee' and (
                (v_staff and u.committee = v_user.committee)
                or (not v_staff and exists (select 1 from public.tanod_committees tc
                                             where tc.tanod_id = v_user.id and tc.status = 'approved' and tc.committee = u.committee)))));
  return v_req;
end $$;
comment on function public.request_retirement() is
  'A tanod (0052) or a staff member (0166) asks to retire. Tells the super admins, who decide, and the Kagawad of the person''s committee, who can endorse. Never changes users.is_retired itself (finalize_retirement).';

/** A Kagawad endorses a pending request of their committee's tanod or staff member; the super admins are told and still decide. */
create or replace function public.endorse_retirement(p_request uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r public.retirement_requests%rowtype; v_note text := nullif(trim(coalesce(p_note, '')), ''); v_by text; v_t text;
begin
  select * into r from public.retirement_requests where id = p_request for update;
  if not found then raise exception 'No such request' using errcode = 'check_violation'; end if;
  if not (public._kagawad_of_tanod(r.tanod_id) or public._kagawad_of_staff(r.tanod_id)) then
    raise exception 'Only the Kagawad of their committee endorses this' using errcode = 'insufficient_privilege';
  end if;
  if r.status <> 'pending' then raise exception 'This request was already decided' using errcode = 'check_violation'; end if;
  if r.endorsed_at is not null then raise exception 'This request is already endorsed' using errcode = 'check_violation'; end if;
  update public.retirement_requests set endorsed_by = auth.uid(), endorsed_at = now(), endorse_note = left(v_note, 500) where id = p_request;
  select public.display_name(full_name) into v_by from public.users where id = auth.uid();
  select public.display_name(full_name) into v_t from public.users where id = r.tanod_id;
  insert into public.notifications (user_id, kind, message, subject_user_id)
  select u.id, 'retirement', left(format('%s endorses %s''s request to retire%s', coalesce(v_by, 'A Kagawad'), coalesce(v_t, 'a member'), coalesce(': ' || v_note, '.')), 500), r.tanod_id
    from public.users u where u.role = 'admin' and coalesce(u.admin_tier, 'super') = 'super' and not coalesce(u.is_suspended, false);
end $$;

create or replace function public.finalize_retirement(p_request uuid, p_decision text, p_reason text default null)
returns public.retirement_status
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_req    public.retirement_requests%rowtype;
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_new    retirement_status;
  d        record;
begin
  if not public.is_super_admin() then
    raise exception 'Only an administrator may decide a retirement request';
  end if;
  if p_decision not in ('approve', 'deny') then
    raise exception 'Unknown decision: %', p_decision;
  end if;
  select * into v_req from public.retirement_requests where id = p_request for update;
  if not found then
    raise exception 'No such retirement request';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'This request has already been decided (current status: %)', v_req.status;
  end if;
  if p_decision = 'deny' and v_reason is null then
    raise exception 'A reason is required when denying a retirement request';
  end if;
  select * into v_user from public.users where id = v_req.tanod_id for update;
  if not found then
    raise exception 'That account no longer exists';
  end if;

  v_new := case p_decision when 'approve' then 'approved' else 'denied' end::retirement_status;
  update public.retirement_requests
     set status = v_new, decided_at = now(), decided_by = auth.uid(), denial_reason = v_reason
   where id = p_request;

  if v_new = 'approved' then
    update public.users set is_retired = true, retired_at = now(), duty_status = null where id = v_user.id;
    if v_user.role = 'tanod' then
      -- Same protection set_account_suspension gives a suspended tanod (0013): a live dispatch cannot be left on a phone that
      -- is about to stop being checked.
      for d in
        update public.dispatches set state = 'expired'
         where tanod_id = v_user.id and state in ('assigned', 'accepted')
        returning report_id
      loop
        perform public.redispatch_report(d.report_id, 'assigned tanod has retired');
      end loop;
    else
      -- a staff member (0166): the cases they held go back to their committee, nobody's yet, and the release is logged
      perform set_config('smartsumbong.handler_change', 'on', true);
      for d in
        update public.reports set handler_id = null, handled_since = null
         where handler_id = v_user.id and deleted_at is null
           and status not in ('resolved', 'closed', 'archived', 'rejected', 'cancelled')
        returning id
      loop
        insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
        values (d.id, auth.uid(), 'release', v_user.id, 'Retired');
      end loop;
      perform set_config('smartsumbong.handler_change', 'off', true);
    end if;
  end if;

  insert into public.notifications (user_id, kind, message)
  values (v_user.id, 'retirement',
          case v_new
            when 'approved' then 'Your retirement has been approved. Thank you for your service — this account can no longer sign in.'
            else format('Your retirement request was not approved. Reason: %s', v_reason)
          end);
  return v_new;
end $$;

-- A retired staff member holds no tier: every page and function that asks admin_tier() treats them as signed out of the portal.
create or replace function public.admin_tier() returns text
language sql stable security definer set search_path = public as $$
  select case when u.role = 'admin' and not coalesce(u.is_suspended, false) and not coalesce(u.is_retired, false) then coalesce(u.admin_tier, 'super') end
    from public.users u where u.id = auth.uid()
$$;

-- The queue says who asks (role: 'tanod' or 'staff'; Administrative Services' Tanods/Staff chooser reads it).
drop function public.retirement_requests_queue();
create function public.retirement_requests_queue()
returns table (id uuid, tanod_id uuid, full_name text, email text, mobile_number text, status public.retirement_status, requested_at timestamptz,
               decided_at timestamptz, decided_by uuid, decided_by_name text, denial_reason text,
               endorsed_at timestamptz, endorsed_by_name text, endorse_note text, role text)
language sql stable set search_path = public, extensions as $$
  select r.id, r.tanod_id, u.full_name, u.email, u.mobile_number,
         r.status, r.requested_at, r.decided_at, r.decided_by, d.full_name,
         r.denial_reason, r.endorsed_at, k.full_name, r.endorse_note,
         case when u.role = 'admin' then 'staff' else 'tanod' end
    from public.retirement_requests r
    join public.users u on u.id = r.tanod_id
    left join public.users d on d.id = r.decided_by
    left join public.users k on k.id = r.endorsed_by
   order by (r.status = 'pending') desc, r.requested_at desc
$$;
comment on function public.retirement_requests_queue() is 'Retirement Requests queue. Pending first, newest first within that; with the Kagawad''s endorsement (0157) and who asks, tanod or staff (0166).';
revoke all on function public.retirement_requests_queue() from public, anon;
grant execute on function public.retirement_requests_queue() to authenticated, service_role;
