-- =============================================================
-- SmartSumbong — 0153 Personnel by committee, and the punch card
--
-- Roles and pages, step 4 (docs/ROLES_AND_PAGES.md, "Personnel"; decided
-- with Ace on 30 Oct 2026).
--
-- Tanods are assigned to committees by what they know and who they work
-- with: a committee's Kagawad proposes, a super admin approves (a super
-- admin's own assignment is approved at once). A tanod can be in several
-- committees, each with its own role inside it ("lead on flooding"), which
-- only that committee and the super admins see. A tanod with no committee
-- is seen by the super admins only.
--
--   tanod_committees        one row per tanod and committee: proposed or
--                           approved, the committee's role for them
--   tanod_committee_log     every proposal, approval, denial and removal;
--                           append-only
--   propose_tanod_committee()  a Kagawad for their committee (proposed), a
--                              super admin for any (approved)
--   decide_tanod_committee()   a super admin approves or denies a proposal
--   remove_tanod_committee()   a super admin, or the committee's Kagawad
--   tanod_pick_list()          names only, so a Kagawad can propose a tanod
--                              they cannot otherwise see
--   personnel_committees()     each tanod's committees as the caller may see
--                              them, and the committee of the case they are
--                              on (the case itself stays hidden)
--
-- Kagawads and staff get an automatic punch card: when they signed in and
-- out of the portal (admin_punches, written by the portal at sign-in and
-- sign-out) and the cases they touched that day, built from what the case
-- history already records (status changes, takes and releases, forwards,
-- messages). Super admins see every card; a Kagawad sees their staff's and
-- their own; staff see their own.
--
-- account_directory() now shows a committee's admins only the tanods of
-- their committee, and no residents (Residents is a super admin page).
-- =============================================================

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'tanod_committee';

create table public.tanod_committees (
  tanod_id    uuid not null references public.users (id) on delete cascade,
  committee   text not null references public.committees (key) on update cascade on delete cascade,
  status      text not null check (status in ('proposed', 'approved')),
  role_label  text check (role_label is null or char_length(role_label) <= 60),
  note        text check (note is null or char_length(note) <= 300),
  proposed_by uuid references public.users (id) on delete set null,
  proposed_at timestamptz not null default now(),
  decided_by  uuid references public.users (id) on delete set null,
  decided_at  timestamptz,
  primary key (tanod_id, committee)
);
create index tanod_committees_committee_idx on public.tanod_committees (committee, status);
comment on table public.tanod_committees is '0153: the committees a tanod belongs to (a Kagawad proposes, a super admin approves), with the committee''s own role for them. Written only by the functions below.';
alter table public.tanod_committees enable row level security;
create policy tanod_committees_read on public.tanod_committees for select using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and committee = (select u.committee from public.users u where u.id = (select auth.uid())))
  or (tanod_id = (select auth.uid()) and status = 'approved'));
grant select on public.tanod_committees to authenticated;

create table public.tanod_committee_log (
  id         bigint generated always as identity primary key,
  tanod_id   uuid not null references public.users (id) on delete cascade,
  committee  text not null,
  action     text not null check (action in ('proposed', 'approved', 'denied', 'removed', 'role_changed')),
  role_label text,
  note       text,
  actor      uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index tanod_committee_log_tanod_idx on public.tanod_committee_log (tanod_id, created_at);
comment on table public.tanod_committee_log is '0153: every change to a tanod''s committees and who made it; append-only.';
alter table public.tanod_committee_log enable row level security;
create policy tanod_committee_log_read on public.tanod_committee_log for select using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and committee = (select u.committee from public.users u where u.id = (select auth.uid()))));
grant select on public.tanod_committee_log to authenticated;

/** Tell the super admins (p_to null) or one person about a tanod's committees. */
create or replace function public._notify_tanod_committee(p_to uuid, p_tanod uuid, p_message text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, kind, message, subject_user_id)
  select u.id, 'tanod_committee', left(p_message, 500), p_tanod
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_to is null then coalesce(u.admin_tier, 'super') = 'super' else u.id = p_to end;
end $$;

/**
 * Put a tanod in a committee, with that committee's role for them. A super admin's is approved at once; a Kagawad proposes for
 * their own committee and the super admins are told. On a tanod already in the committee, it changes the role (logged).
 * Returns the row's status.
 */
create or replace function public.propose_tanod_committee(p_tanod uuid, p_committee text, p_role text default null, p_note text default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tier text := public.admin_tier();
  v_my text; v_t public.users%rowtype; v_row public.tanod_committees%rowtype;
  v_role text := nullif(trim(coalesce(p_role, '')), ''); v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_status text; v_by text;
begin
  select committee into v_my from public.users where id = auth.uid();
  if v_tier is distinct from 'super' and not (v_tier = 'committee' and v_my = p_committee) then
    raise exception 'A Kagawad proposes tanods for their own committee; a super admin assigns them' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.committees where key = p_committee and active) then
    raise exception 'No such committee' using errcode = 'check_violation';
  end if;
  select * into v_t from public.users where id = p_tanod;
  if not found or v_t.role <> 'tanod' or v_t.removed_at is not null or coalesce(v_t.is_retired, false) then
    raise exception 'That is not an active tanod' using errcode = 'check_violation';
  end if;
  if char_length(v_role) > 60 then raise exception 'Keep the role under 60 characters' using errcode = 'check_violation'; end if;
  select display_name(full_name) into v_by from public.users where id = auth.uid();

  select * into v_row from public.tanod_committees where tanod_id = p_tanod and committee = p_committee;
  if found then
    update public.tanod_committees set role_label = v_role, note = coalesce(v_note, note) where tanod_id = p_tanod and committee = p_committee;
    insert into public.tanod_committee_log (tanod_id, committee, action, role_label, note, actor)
    values (p_tanod, p_committee, 'role_changed', v_role, v_note, auth.uid());
    if v_tier = 'committee' and v_row.status = 'approved' then
      perform public._notify_tanod_committee(null, p_tanod, format('%s changed %s''s role in %s to %s.', coalesce(v_by, 'A Kagawad'),
              display_name(v_t.full_name), public._committee_label(p_committee), coalesce(v_role, 'none')));
    end if;
    return v_row.status;
  end if;

  v_status := case when v_tier = 'super' then 'approved' else 'proposed' end;
  insert into public.tanod_committees (tanod_id, committee, status, role_label, note, proposed_by, decided_by, decided_at)
  values (p_tanod, p_committee, v_status, v_role, v_note, auth.uid(),
          case when v_status = 'approved' then auth.uid() end, case when v_status = 'approved' then now() end);
  insert into public.tanod_committee_log (tanod_id, committee, action, role_label, note, actor)
  values (p_tanod, p_committee, v_status, v_role, v_note, auth.uid());
  if v_status = 'proposed' then
    perform public._notify_tanod_committee(null, p_tanod, format('%s proposes %s for %s%s. Approve it in Personnel.', coalesce(v_by, 'A Kagawad'),
            display_name(v_t.full_name), public._committee_label(p_committee), coalesce(' as ' || v_role, '')));
  end if;
  return v_status;
end $$;

/** A super admin approves or denies a Kagawad's proposal; the Kagawad who proposed it is told. */
create or replace function public.decide_tanod_committee(p_tanod uuid, p_committee text, p_approve boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_row public.tanod_committees%rowtype; v_note text := nullif(trim(coalesce(p_note, '')), ''); v_name text;
begin
  if public.admin_tier() is distinct from 'super' then
    raise exception 'A super admin approves a tanod''s committee' using errcode = 'insufficient_privilege';
  end if;
  select * into v_row from public.tanod_committees where tanod_id = p_tanod and committee = p_committee and status = 'proposed';
  if not found then raise exception 'There is no proposal waiting for that tanod and committee' using errcode = 'check_violation'; end if;
  if p_approve then
    update public.tanod_committees set status = 'approved', decided_by = auth.uid(), decided_at = now()
     where tanod_id = p_tanod and committee = p_committee;
  else
    delete from public.tanod_committees where tanod_id = p_tanod and committee = p_committee;
  end if;
  insert into public.tanod_committee_log (tanod_id, committee, action, role_label, note, actor)
  values (p_tanod, p_committee, case when p_approve then 'approved' else 'denied' end, v_row.role_label, v_note, auth.uid());
  select display_name(full_name) into v_name from public.users where id = p_tanod;
  if v_row.proposed_by is not null then
    perform public._notify_tanod_committee(v_row.proposed_by, p_tanod, format('%s for %s was %s%s', v_name, public._committee_label(p_committee),
            case when p_approve then 'approved' else 'not approved' end, coalesce(': ' || v_note, '.')));
  end if;
end $$;

/** Take a tanod out of a committee (or withdraw a proposal): a super admin, or that committee's Kagawad (the super admins are told). */
create or replace function public.remove_tanod_committee(p_tanod uuid, p_committee text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_tier text := public.admin_tier(); v_my text; v_row public.tanod_committees%rowtype; v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  select committee into v_my from public.users where id = auth.uid();
  if v_tier is distinct from 'super' and not (v_tier = 'committee' and v_my = p_committee) then
    raise exception 'Only a super admin or this committee''s Kagawad can do that' using errcode = 'insufficient_privilege';
  end if;
  delete from public.tanod_committees where tanod_id = p_tanod and committee = p_committee returning * into v_row;
  if not found then raise exception 'That tanod is not in that committee' using errcode = 'check_violation'; end if;
  insert into public.tanod_committee_log (tanod_id, committee, action, role_label, note, actor)
  values (p_tanod, p_committee, 'removed', v_row.role_label, v_note, auth.uid());
  if v_tier = 'committee' and v_row.status = 'approved' then
    perform public._notify_tanod_committee(null, p_tanod, format('%s was taken out of %s by its Kagawad%s',
            (select display_name(full_name) from public.users where id = p_tanod), public._committee_label(p_committee), coalesce(': ' || v_note, '.')));
  end if;
end $$;

/** Names only: every active tanod, so a Kagawad can propose one they cannot otherwise see. */
create or replace function public.tanod_pick_list()
returns table (id uuid, full_name text)
language sql stable security definer set search_path = public as $$
  select u.id, u.full_name from public.users u
   where public.admin_tier() in ('super', 'committee')
     and u.role = 'tanod' and u.removed_at is null and not coalesce(u.is_retired, false)
     and u.verification_status = 'verified' and not coalesce(u.is_suspended, false)
   order by u.full_name
$$;

/**
 * Each tanod's committees as the caller may see them (a committee's admins: only their own committee's row, with its role),
 * and the committee of the case the tanod is on now, if any: other committees see that pill, never the case.
 */
create or replace function public.personnel_committees()
returns table (tanod_id uuid, committees jsonb, busy_committee text)
language sql stable security definer set search_path = public as $$
  with me as (select public.admin_tier() as tier, (select committee from public.users where id = auth.uid()) as com),
  t as (
    select u.id from public.users u, me
     where u.role = 'tanod' and u.removed_at is null and me.tier is not null
       and (me.tier in ('super', 'captain')
            or exists (select 1 from public.tanod_committees tc where tc.tanod_id = u.id and tc.committee = me.com))
  )
  select t.id,
         coalesce((select jsonb_agg(jsonb_build_object('key', tc.committee, 'status', tc.status, 'role', tc.role_label) order by c.sort, c.key)
                     from public.tanod_committees tc join public.committees c on c.key = tc.committee, me
                    where tc.tanod_id = t.id and (me.tier in ('super', 'captain') or tc.committee = me.com)), '[]'::jsonb),
         (select public._case_committee(d.report_id) from public.dispatches d
           where d.tanod_id = t.id and d.state in ('assigned', 'accepted') order by d.assigned_at desc limit 1)
    from t
$$;

-- Personnel and Residents: a committee's admins see only their committee's tanods, and no residents.
create or replace function public.account_directory(p_role public.user_role)
returns table (id uuid, full_name text, email text, mobile_number text, role public.user_role, verification_status public.verification_state,
               is_suspended boolean, duty_status public.duty_state, id_image_url text, selfie_url text, rejection_reason text,
               submitted_at timestamptz, due_at timestamptz, minutes_left integer, is_overdue boolean, holding_incident boolean,
               created_at timestamptz, ocr_detected_type public.id_document_type, ocr_flags text[], ocr_extracted_name text,
               ocr_extracted_number text, abuse_strike_count integer, ocr_processed_at timestamptz, ocr_rescan_requested_at timestamptz,
               id_type public.id_document_type, suspended_reason text, is_retired boolean, retired_at timestamptz, avatar_url text)
language sql stable set search_path = public, extensions as $$
  select u.id, u.full_name, u.email, u.mobile_number, u.role,
         u.verification_status, u.is_suspended, u.duty_status,
         u.id_image_url, u.selfie_url, u.rejection_reason,
         u.verification_submitted_at,
         u.verification_due_at,
         case when u.verification_status = 'pending' and u.verification_due_at is not null
              then (extract(epoch from (u.verification_due_at - now())) / 60)::integer
         end,
         u.verification_status = 'pending'
           and u.verification_due_at is not null
           and u.verification_due_at < now(),
         exists (select 1 from public.dispatches d
                  where d.tanod_id = u.id and d.state in ('assigned', 'accepted')),
         u.created_at,
         u.ocr_detected_type,
         u.ocr_flags,
         u.ocr_extracted_name,
         u.ocr_extracted_number,
         (select count(*)::integer from public.status_logs sl
           join public.reports r2 on r2.id = sl.report_id
          where r2.resident_id = u.id
            and sl.is_abusive = true
            and sl.new_status = 'rejected'),
         u.ocr_processed_at,
         u.ocr_rescan_requested_at,
         u.id_type,
         u.suspended_reason,
         u.is_retired,
         u.retired_at,
         u.avatar_url
    from public.users u
   where u.role = p_role
     and u.removed_at is null
     and (not public.admin_scoped()
          or (u.role = 'tanod' and exists (select 1 from public.tanod_committees tc
                                            where tc.tanod_id = u.id
                                              and tc.committee = (select me.committee from public.users me where me.id = auth.uid()))))
   order by (u.verification_status = 'pending') desc,
            cardinality(u.ocr_flags) > 0 desc,
            u.verification_due_at nulls last,
            u.full_name
$$;

-- ---------- the punch card ----------

create table public.admin_punches (
  id      bigint generated always as identity primary key,
  user_id uuid not null references public.users (id) on delete cascade,
  kind    text not null check (kind in ('in', 'out')),
  at      timestamptz not null default now()
);
create index admin_punches_user_idx on public.admin_punches (user_id, at);
comment on table public.admin_punches is '0153: when an administrator signed in to and out of the portal, for the punch card. Written by punch() at sign-in and sign-out; append-only.';
alter table public.admin_punches enable row level security;
/** May the signed-in administrator see this person's punch card? Super admins and captains: everyone's; a Kagawad: their own and their staff's; staff: their own. */
create or replace function public._sees_punch_card(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
      or coalesce(public.is_full_viewer(), false)
      or (public.admin_tier() = 'committee' and exists (
            select 1 from public.users t, public.users me
             where t.id = p_user and me.id = auth.uid() and t.role = 'admin' and t.admin_tier = 'moderator' and t.committee = me.committee))
$$;
create policy admin_punches_read on public.admin_punches for select using ((select public._sees_punch_card(user_id)));
grant select on public.admin_punches to authenticated;

/**
 * The portal punches the signed-in administrator in or out. Only a Kagawad or staff member has a card, so nothing is kept for a
 * super admin or a captain. A repeat within a minute is ignored.
 */
create or replace function public.punch(p_kind text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has a punch card' using errcode = 'insufficient_privilege'; end if;
  if p_kind not in ('in', 'out') then raise exception 'In or out' using errcode = 'check_violation'; end if;
  if public.admin_tier() not in ('committee', 'moderator') then return; end if;
  if exists (select 1 from public.admin_punches where user_id = auth.uid() and kind = p_kind and at > now() - interval '1 minute') then return; end if;
  insert into public.admin_punches (user_id, kind) values (auth.uid(), p_kind);
end $$;

/**
 * The punch cards the signed-in administrator may see (p_user: one person's), over the last p_days days in Manila time: per day,
 * the first sign-in, the last sign-out (null while still signed in or when the session lapsed), and the cases they touched.
 */
create or replace function public.punch_cards(p_days integer default 7, p_user uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  with span as (select greatest(1, least(coalesce(p_days, 7), 31)) as n),
  people as (
    select u.id, u.full_name, u.admin_tier, u.committee, u.official_role from public.users u
     where u.role = 'admin' and u.removed_at is null and coalesce(u.admin_tier, 'super') in ('committee', 'moderator')
       and (p_user is null or u.id = p_user) and public._sees_punch_card(u.id)
  ),
  days as (
    select d::date as day from span, generate_series((now() at time zone 'Asia/Manila')::date - (span.n - 1), (now() at time zone 'Asia/Manila')::date, interval '1 day') d
  ),
  touches as (
    select x.who, (x.at at time zone 'Asia/Manila')::date as day, x.report_id
      from (select changed_by as who, created_at as at, report_id from public.status_logs
            union all select admin_id, created_at, report_id from public.case_handler_log
            union all select actor, created_at, report_id from public.case_forwards
            union all select author_id, created_at, report_id from public.report_messages) x, span
     where x.who in (select id from people) and x.at > now() - make_interval(days => span.n + 1)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.full_name, 'tier', p.admin_tier, 'committee', p.committee, 'position', p.official_role,
           'days', (select jsonb_agg(jsonb_build_object(
                      'day', d.day,
                      'first_in', (select min(a.at) from public.admin_punches a where a.user_id = p.id and a.kind = 'in' and (a.at at time zone 'Asia/Manila')::date = d.day),
                      'last_out', (select max(a.at) from public.admin_punches a where a.user_id = p.id and a.kind = 'out' and (a.at at time zone 'Asia/Manila')::date = d.day),
                      'touched', (select count(distinct t.report_id) from touches t where t.who = p.id and t.day = d.day),
                      'cases', coalesce((select jsonb_agg(r.tracking_id order by r.tracking_id) from public.reports r
                                          where r.id in (select t.report_id from touches t where t.who = p.id and t.day = d.day)), '[]'::jsonb))
                      order by d.day desc) from days d))
         order by p.committee nulls first, p.admin_tier, p.full_name), '[]'::jsonb)
    from people p
$$;

revoke all on function public.propose_tanod_committee(uuid, text, text, text), public.decide_tanod_committee(uuid, text, boolean, text),
                       public.remove_tanod_committee(uuid, text, text), public.tanod_pick_list(), public.personnel_committees(),
                       public.punch(text), public.punch_cards(integer, uuid), public._sees_punch_card(uuid),
                       public._notify_tanod_committee(uuid, uuid, text) from public, anon;
grant execute on function public.propose_tanod_committee(uuid, text, text, text), public.decide_tanod_committee(uuid, text, boolean, text),
                          public.remove_tanod_committee(uuid, text, text), public.tanod_pick_list(), public.personnel_committees(),
                          public.punch(text), public.punch_cards(integer, uuid), public._sees_punch_card(uuid) to authenticated;
