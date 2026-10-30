-- =============================================================
-- SmartSumbong — 0152 Forwarding a case between committees
--
-- Roles and pages, step 3 (docs/ROLES_AND_PAGES.md, "Case Reports:
-- forwarding"; decided with Ace on 30 Oct 2026).
--
-- Until now a case's committee came only from its category (the ticks a
-- super admin set, 0145). A case now has its own committee once it is
-- forwarded:
--
--   reports.committee           the committee a forwarded case is with; it
--                               alone sees it (with whoever handles it)
--   reports.awaiting_placement  forwarded to the super admins, waiting for
--                               one of them to place it with a committee
--   case_forwards               every forward and every flag, append-only:
--                               nobody can change or delete a row
--
--   forward_case()          a super admin forwards to a committee; a Kagawad
--                           forwards to another committee or to the super
--                           admins. Forwarding to the super admins is not an
--                           escalation (that asks the Chairman to decide):
--                           it hands the case over to be placed.
--   flag_case_for_forward() a staff member (moderator) cannot forward; they
--                           flag the case with the reason, and their Kagawad
--                           decides: forward it, or dismiss the flag
--   dismiss_forward_flag()
--
-- A forwarded case leaves whoever was handling it (the release is in the
-- handler log), and the receiving committee's Kagawad is notified. Only the
-- forwarding functions can change a case's committee.
-- =============================================================

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'case_forwarded';
alter type public.notification_kind add value if not exists 'forward_flag';

alter table public.reports
  add column committee text references public.committees (key) on update cascade,
  add column awaiting_placement boolean not null default false;
comment on column public.reports.committee is '0152: the committee a forwarded case is with (it alone sees it); null: its category decides, as before.';
comment on column public.reports.awaiting_placement is '0152: forwarded to the super admins, waiting to be placed with a committee; no committee sees it meanwhile.';
create index reports_committee_idx on public.reports (committee) where committee is not null;

create table public.case_forwards (
  id             bigint generated always as identity primary key,
  report_id      uuid not null references public.reports (id) on delete cascade,
  kind           text not null check (kind in ('forward', 'flag', 'flag_dismissed')),
  from_committee text references public.committees (key) on update cascade,
  to_committee   text references public.committees (key) on update cascade,
  to_super       boolean not null default false,
  flag_id        bigint references public.case_forwards (id),
  note           text check (note is null or char_length(note) <= 500),
  actor          uuid references public.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  check (kind <> 'flag_dismissed' or flag_id is not null)
);
create index case_forwards_report_idx on public.case_forwards (report_id, created_at);
create index case_forwards_flag_idx on public.case_forwards (flag_id) where flag_id is not null;
comment on table public.case_forwards is '0152: every forward of a case between committees (or to the super admins) and every staff flag asking for one; append-only, written by forward_case, flag_case_for_forward and dismiss_forward_flag.';
alter table public.case_forwards enable row level security;
-- read: the super admins and captains; a committee's admins for the cases they see, and for what left their committee
create policy case_forwards_read on public.case_forwards for select using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and (public.admin_sees_report(report_id)
        or from_committee = (select u.committee from public.users u where u.id = (select auth.uid())))));
grant select on public.case_forwards to authenticated;
-- no insert, update or delete policy: rows come only from the functions below, and stay

/** The open staff flags: a flag nobody has forwarded or dismissed yet. */
create view public.case_forward_flags with (security_invoker = true) as
  select f.id, f.report_id, f.from_committee, f.to_committee, f.to_super, f.note, f.actor, f.created_at
    from public.case_forwards f
   where f.kind = 'flag' and not exists (select 1 from public.case_forwards x where x.flag_id = f.id);
grant select on public.case_forward_flags to authenticated;

/** The committee a case is with now: its own once forwarded, none while waiting for the super admins, else the first committee its category is ticked for. */
create or replace function public._case_committee(p_report uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when r.awaiting_placement then null
              else coalesce(r.committee, (select cc.committee from public.committee_categories cc join public.committees c on c.key = cc.committee and c.active
                                            where cc.category = r.category order by c.sort, c.key limit 1)) end
    from public.reports r where r.id = p_report
$$;

-- Who sees a case: a forwarded case belongs to its committee alone (and whoever handles it); one waiting for the super admins,
-- to no committee; otherwise, as before, the category's committees, a concern's, and whoever handles it.
create or replace function public._user_sees_case(p_user uuid, p_report uuid, p_cat public.complaint_category, p_handler uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when r.awaiting_placement then false
    when r.committee is not null then
         coalesce((select u.committee = r.committee and u.role = 'admin' and not coalesce(u.is_suspended, false) from public.users u where u.id = p_user), false)
      or (p_handler is not null and p_handler = p_user)
    else coalesce(public._user_sees_category(p_user, p_cat), false)
      or (p_handler is not null and p_handler = p_user)
      or exists (select 1 from public.report_concerns rc where rc.report_id = p_report and public._user_sees_category(p_user, rc.category))
  end
    from (select coalesce((select committee from public.reports where id = p_report), null) as committee,
                 coalesce((select awaiting_placement from public.reports where id = p_report), false) as awaiting_placement) r
$$;

-- Only the forwarding functions change a case's committee.
create or replace function public._guard_case_committee()
returns trigger
language plpgsql set search_path = public as $$
begin
  if (new.committee is distinct from old.committee or new.awaiting_placement is distinct from old.awaiting_placement)
     and auth.uid() is not null and coalesce(current_setting('smartsumbong.forwarding', true), '') <> 'on' then
    raise exception 'A case changes committee only by forwarding it' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger reports_committee_guard before update on public.reports
  for each row execute function public._guard_case_committee();

/** Tell a committee's Kagawad (or, with no committee, the super admins) about a case. */
create or replace function public._notify_committee_heads(p_committee text, p_report uuid, p_kind text, p_message text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, p_report, p_kind::public.notification_kind, left(p_message, 500)
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_committee is null then coalesce(u.admin_tier, 'super') = 'super'
              else u.admin_tier = 'committee' and u.committee = p_committee end;
end $$;

/**
 * Forward a case. A super admin forwards to a committee (p_to); a Kagawad forwards to another committee, or to the super admins
 * (p_to null) to place it. p_flag closes the staff flag the forward answers. Staff flag instead (flag_case_for_forward).
 */
create or replace function public.forward_case(p_report uuid, p_to text, p_note text default null, p_flag bigint default null)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tier text := public.admin_tier();
  r public.reports%rowtype;
  v_from text; v_id bigint; v_note text := nullif(trim(coalesce(p_note, '')), ''); v_by text; v_to_name text;
begin
  if v_tier is null then raise exception 'Only an administrator forwards a case' using errcode = 'insufficient_privilege'; end if;
  if v_tier = 'moderator' then raise exception 'Staff flag a case for forwarding; their Kagawad decides.' using errcode = 'insufficient_privilege'; end if;
  if v_tier = 'captain' then raise exception 'This account can look at cases but not change them.' using errcode = 'insufficient_privilege'; end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then raise exception 'No such case' using errcode = 'check_violation'; end if;
  if v_tier = 'committee' and not public.admin_sees_report(p_report) then
    raise exception 'This case is outside your committee.' using errcode = 'insufficient_privilege';
  end if;
  if p_to is null and v_tier <> 'committee' then
    raise exception 'Choose the committee to forward it to' using errcode = 'check_violation';
  end if;
  if p_to is not null and not exists (select 1 from public.committees where key = p_to and active) then
    raise exception 'No such committee' using errcode = 'check_violation';
  end if;
  v_from := public._case_committee(p_report);
  if v_tier = 'committee' then v_from := coalesce(r.committee, (select committee from public.users where id = auth.uid())); end if;
  if p_to is not null and p_to = v_from and r.committee is not null then
    raise exception 'The case is already with that committee' using errcode = 'check_violation';
  end if;
  if p_flag is not null and not exists (select 1 from public.case_forward_flags f where f.id = p_flag and f.report_id = p_report) then
    raise exception 'That flag is not open on this case' using errcode = 'check_violation';
  end if;

  perform set_config('smartsumbong.forwarding', 'on', true);
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports
     set committee = p_to, awaiting_placement = (p_to is null), handler_id = null, handled_since = null
   where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  perform set_config('smartsumbong.forwarding', 'off', true);
  if r.handler_id is not null then
    insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
    values (p_report, auth.uid(), 'release', r.handler_id, left('Forwarded to ' || case when p_to is null then 'the super admins' else public._committee_label(p_to) end, 300));
  end if;
  insert into public.case_forwards (report_id, kind, from_committee, to_committee, to_super, flag_id, note, actor)
  values (p_report, 'forward', v_from, p_to, p_to is null, p_flag, left(v_note, 500), auth.uid())
  returning id into v_id;

  select public.display_name(full_name) into v_by from public.users where id = auth.uid();
  v_to_name := case when p_to is null then 'the super admins' else public._committee_label(p_to) end;
  perform public._notify_committee_heads(p_to, p_report, 'case_forwarded',
    format('Case %s was forwarded to %s by %s%s', r.tracking_id, case when p_to is null then 'the super admins to place' else 'your committee' end,
           coalesce(v_by, 'an administrator'), coalesce(': ' || v_note, '.')));
  perform public._smart_event('forward', p_report, format('%s forwarded to %s', r.tracking_id, v_to_name),
          jsonb_build_object('from', v_from, 'to', p_to, 'flag', p_flag));
  return v_id;
end $$;

/** A staff member asks their Kagawad to forward a case, saying why (p_to: a committee to suggest, or none). */
create or replace function public.flag_case_for_forward(p_report uuid, p_reason text, p_to text default null)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me public.users%rowtype; r public.reports%rowtype; v_id bigint; v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  select * into v_me from public.users where id = auth.uid();
  if not found or v_me.role <> 'admin' or coalesce(v_me.admin_tier, 'super') <> 'moderator' then
    raise exception 'Only staff flag a case for forwarding; a Kagawad or a super admin forwards it' using errcode = 'insufficient_privilege';
  end if;
  if v_reason is null or char_length(v_reason) < 5 then raise exception 'Say why it should be forwarded' using errcode = 'check_violation'; end if;
  select * into r from public.reports where id = p_report and deleted_at is null;
  if not found then raise exception 'No such case' using errcode = 'check_violation'; end if;
  if not public.admin_sees_report(p_report) then raise exception 'This case is outside your committee.' using errcode = 'insufficient_privilege'; end if;
  if p_to is not null and not exists (select 1 from public.committees where key = p_to and active) then
    raise exception 'No such committee' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.case_forward_flags f where f.report_id = p_report and f.from_committee = v_me.committee) then
    raise exception 'This case is already flagged; your Kagawad has it' using errcode = 'check_violation';
  end if;
  insert into public.case_forwards (report_id, kind, from_committee, to_committee, to_super, note, actor)
  values (p_report, 'flag', v_me.committee, p_to, false, left(v_reason, 500), auth.uid())
  returning id into v_id;
  perform public._notify_committee_heads(v_me.committee, p_report, 'forward_flag',
    format('%s flagged case %s for forwarding%s: %s', public.display_name(v_me.full_name), r.tracking_id,
           case when p_to is null then '' else ' to ' || public._committee_label(p_to) end, v_reason));
  return v_id;
end $$;

/** The Kagawad (or a super admin) keeps the case where it is; the staff member who flagged it is told. */
create or replace function public.dismiss_forward_flag(p_flag bigint, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare f record; v_tier text := public.admin_tier(); v_my text;
begin
  select * into f from public.case_forward_flags where id = p_flag;
  if not found then raise exception 'That flag is not open' using errcode = 'check_violation'; end if;
  select committee into v_my from public.users where id = auth.uid();
  if not (v_tier = 'super' or (v_tier = 'committee' and v_my = f.from_committee)) then
    raise exception 'The Kagawad of the committee decides on a flag' using errcode = 'insufficient_privilege';
  end if;
  insert into public.case_forwards (report_id, kind, from_committee, flag_id, note, actor)
  values (f.report_id, 'flag_dismissed', f.from_committee, p_flag, left(nullif(trim(coalesce(p_note, '')), ''), 500), auth.uid());
  insert into public.notifications (user_id, report_id, kind, message)
  select f.actor, f.report_id, 'forward_flag', left(format('Your flag on case %s was dismissed%s', r.tracking_id, coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '.')), 500)
    from public.reports r where r.id = f.report_id and f.actor is not null;
end $$;

revoke all on function public.forward_case(uuid, text, text, bigint), public.flag_case_for_forward(uuid, text, text),
                       public.dismiss_forward_flag(bigint, text), public._case_committee(uuid), public._notify_committee_heads(text, uuid, text, text) from public, anon;
grant execute on function public.forward_case(uuid, text, text, bigint), public.flag_case_for_forward(uuid, text, text),
                          public.dismiss_forward_flag(bigint, text), public._case_committee(uuid) to authenticated;
