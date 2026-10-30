-- =============================================================
-- SmartSumbong — 0155 The Inbox, and asking the Kagawad before a reroute
--
-- Roles and pages, step 5 (docs/ROLES_AND_PAGES.md, "Inbox" and
-- "Personnel: automatic reroute"; decided with Ace on 30 Oct 2026).
--
-- The Inbox is an intranet mail inside the portal. Mail runs along the
-- ladder: staff write to their own Kagawad; a Kagawad to their staff, other
-- Kagawads and the super admins; a super admin to anyone; a captain to the
-- super admins. A message can carry a case. The system writes there too:
-- forwards, staff flags and reroute questions arrive as system messages.
--
--   inbox_messages       one row per recipient (a message to three people
--                        is three rows with one batch id); read by its
--                        sender and its recipient only
--   send_mail()          checks the ladder and that the sender sees the case
--   mail_recipients()    who the signed-in administrator may write to
--   mark_mail_read()
--
-- The reroute question. When a tanod does not accept in time, the case is
-- offered again (redispatch_report, auto_dispatch). Now, if the case's
-- committee has tanods of its own (0153), only they are picked. If none of
-- them is free, the system asks that committee's Kagawad instead of going
-- straight to anyone: a pinned notification (with web push) and an Inbox
-- message with the question. The Kagawad picks a tanod, or lets the system
-- send the nearest from any committee. Nobody answering within the wait
-- (5 minutes for an urgent case, 15 for the rest; Control Room > Rules)
-- sends the nearest from any committee, and says so. A committee with no
-- tanods of its own, or no Kagawad, reroutes as before.
--
--   reroute_questions          one per case and offer, open until answered,
--                              timed out, or no longer needed
--   answer_reroute_question()  the Kagawad (or a super admin) picks
--   sweep_reroute_questions()  every minute: time out, or close
-- =============================================================

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'reroute_question';

alter table public.operational_settings
  add column reroute_ask_urgent_minutes smallint not null default 5 check (reroute_ask_urgent_minutes between 1 and 60),
  add column reroute_ask_minutes smallint not null default 15 check (reroute_ask_minutes between 1 and 120);
comment on column public.operational_settings.reroute_ask_urgent_minutes is '0155: how long a Kagawad has to answer a reroute question on an urgent case before the nearest tanod from any committee is sent.';
comment on column public.operational_settings.reroute_ask_minutes is '0155: the same, for every other case.';

-- ---------- the reroute question ----------

create table public.reroute_questions (
  id          bigint generated always as identity primary key,
  report_id   uuid not null references public.reports (id) on delete cascade,
  committee   text not null references public.committees (key) on update cascade on delete cascade,
  attempt     smallint not null,
  asked_at    timestamptz not null default now(),
  due_at      timestamptz not null,
  state       text not null default 'open' check (state in ('open', 'picked', 'any', 'timed_out', 'closed')),
  answered_by uuid references public.users (id) on delete set null,
  answered_at timestamptz,
  dispatch_id uuid references public.dispatches (id) on delete set null
);
create unique index reroute_questions_one_open on public.reroute_questions (report_id) where state = 'open';
create index reroute_questions_due_idx on public.reroute_questions (due_at) where state = 'open';
comment on table public.reroute_questions is '0155: a reroute that found none of the case''s committee''s tanods free asks that committee''s Kagawad; open until answered, timed out (the nearest from any committee is sent) or no longer needed.';
alter table public.reroute_questions enable row level security;
create policy reroute_questions_read on public.reroute_questions for select using (
  (select public.is_full_viewer())
  or ((select public.admin_scoped()) and committee = (select u.committee from public.users u where u.id = (select auth.uid()))));
grant select on public.reroute_questions to authenticated;

-- ---------- the Inbox ----------

create table public.inbox_messages (
  id          bigint generated always as identity primary key,
  batch       uuid not null default gen_random_uuid(),
  sender      uuid references public.users (id) on delete set null,
  recipient   uuid not null references public.users (id) on delete cascade,
  kind        text not null default 'mail' check (kind in ('mail', 'system')),
  subject     text not null check (char_length(subject) between 1 and 140),
  body        text not null check (char_length(body) between 1 and 4000),
  report_id   uuid references public.reports (id) on delete set null,
  question_id bigint references public.reroute_questions (id) on delete set null,
  reply_to    bigint references public.inbox_messages (id) on delete set null,
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  check (kind = 'system' or sender is not null)
);
create index inbox_messages_recipient_idx on public.inbox_messages (recipient, created_at desc);
create index inbox_messages_sender_idx on public.inbox_messages (sender, created_at desc) where sender is not null;
create index inbox_messages_batch_idx on public.inbox_messages (batch);
comment on table public.inbox_messages is '0155: the portal''s Inbox, one row per recipient (one batch per message sent). sender null: the system. Read by its sender and its recipient only; written by send_mail and the system.';
alter table public.inbox_messages enable row level security;
create policy inbox_messages_read on public.inbox_messages for select using (
  recipient = (select auth.uid()) or sender = (select auth.uid()));
grant select on public.inbox_messages to authenticated;

/** May p_from write to p_to? Along the ladder: staff to their Kagawad; a Kagawad to their staff, other Kagawads and the super admins; a super admin to anyone; a captain to the super admins. */
create or replace function public._mail_may_send(p_from uuid, p_to uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case coalesce(f.admin_tier, 'super')
             when 'super'     then true
             when 'committee' then coalesce(t.admin_tier, 'super') in ('super', 'committee') or (t.admin_tier = 'moderator' and t.committee = f.committee)
             when 'moderator' then t.admin_tier = 'committee' and t.committee = f.committee
             when 'captain'   then coalesce(t.admin_tier, 'super') = 'super'
             else false end
      from public.users f, public.users t
     where f.id = p_from and t.id = p_to and f.id <> t.id
       and f.role = 'admin' and not coalesce(f.is_suspended, false)
       and t.role = 'admin' and not coalesce(t.is_suspended, false) and t.removed_at is null), false)
$$;

/** Who the signed-in administrator may write to. */
create or replace function public.mail_recipients()
returns table (id uuid, full_name text, tier text, committee text, official_role text)
language sql stable security definer set search_path = public as $$
  select u.id, u.full_name, coalesce(u.admin_tier, 'super'), u.committee, u.official_role
    from public.users u
   where u.role = 'admin' and public._mail_may_send(auth.uid(), u.id)
   order by case coalesce(u.admin_tier, 'super') when 'super' then 0 when 'committee' then 1 when 'moderator' then 2 else 3 end, u.committee nulls first, u.full_name
$$;

/** Send a message to one or more people along the ladder, optionally about a case the sender can see. Returns the batch id. */
create or replace function public.send_mail(p_to uuid[], p_subject text, p_body text, p_report uuid default null, p_reply_to bigint default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_batch uuid := gen_random_uuid(); v_to uuid;
  v_subject text := nullif(trim(coalesce(p_subject, '')), ''); v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_ids uuid[] := array(select distinct x from unnest(coalesce(p_to, '{}')) x where x is not null);
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has an Inbox' using errcode = 'insufficient_privilege'; end if;
  if cardinality(v_ids) = 0 then raise exception 'Choose who it is for' using errcode = 'check_violation'; end if;
  if cardinality(v_ids) > 30 then raise exception 'Thirty people at most' using errcode = 'check_violation'; end if;
  if v_subject is null or v_body is null then raise exception 'Write a subject and a message' using errcode = 'check_violation'; end if;
  foreach v_to in array v_ids loop
    if not public._mail_may_send(auth.uid(), v_to) then
      raise exception 'You cannot write to % (mail runs along the ladder)', coalesce((select public.display_name(full_name) from public.users where id = v_to), 'that person')
        using errcode = 'insufficient_privilege';
    end if;
  end loop;
  if p_report is not null and not (public.is_full_viewer() or public.admin_sees_report(p_report)) then
    raise exception 'You can only attach a case you can see' using errcode = 'insufficient_privilege';
  end if;
  if p_reply_to is not null and not exists (select 1 from public.inbox_messages m where m.id = p_reply_to and (m.recipient = auth.uid() or m.sender = auth.uid())) then
    raise exception 'No such message to reply to' using errcode = 'check_violation';
  end if;
  insert into public.inbox_messages (batch, sender, recipient, kind, subject, body, report_id, reply_to)
  select v_batch, auth.uid(), x, 'mail', left(v_subject, 140), left(v_body, 4000), p_report, p_reply_to from unnest(v_ids) x;
  return v_batch;
end $$;

/** Mark the signed-in person's messages read. */
create or replace function public.mark_mail_read(p_ids bigint[])
returns integer
language sql security definer set search_path = public as $$
  with u as (update public.inbox_messages set read_at = now()
              where id = any (coalesce(p_ids, '{}')) and recipient = auth.uid() and read_at is null returning 1)
  select count(*)::integer from u
$$;

/** A system message to one person. */
create or replace function public._system_mail(p_to uuid, p_subject text, p_body text, p_report uuid default null, p_question bigint default null)
returns void
language sql security definer set search_path = public as $$
  insert into public.inbox_messages (recipient, kind, subject, body, report_id, question_id)
  values (p_to, 'system', left(p_subject, 140), left(p_body, 4000), p_report, p_question)
$$;

-- Forwards and staff flags (0152) also arrive in the Inbox, as system messages.
create or replace function public._notify_committee_heads(p_committee text, p_report uuid, p_kind text, p_message text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_subject text := case p_kind when 'case_forwarded' then 'A case was forwarded' when 'forward_flag' then 'Staff flagged a case for forwarding' else 'About a case' end;
begin
  insert into public.notifications (user_id, report_id, kind, message)
  select u.id, p_report, p_kind::public.notification_kind, left(p_message, 500)
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_committee is null then coalesce(u.admin_tier, 'super') = 'super'
              else u.admin_tier = 'committee' and u.committee = p_committee end;
  insert into public.inbox_messages (recipient, kind, subject, body, report_id)
  select u.id, 'system', v_subject, left(p_message, 4000), p_report
    from public.users u
   where u.role = 'admin' and not coalesce(u.is_suspended, false) and u.id is distinct from auth.uid()
     and case when p_committee is null then coalesce(u.admin_tier, 'super') = 'super'
              else u.admin_tier = 'committee' and u.committee = p_committee end;
end $$;

-- ---------- the reroute ----------

/**
 * On a reroute, the committee whose tanods are tried first: the case's committee, when it has tanods of its own and nobody has
 * already answered (or timed out) this offer's question. Null: no preference, any tanod as before.
 */
create or replace function public._reroute_committee(p_report uuid)
returns text
language sql stable security definer set search_path = public as $$
  select x.c from (select r.dispatch_attempts as n, public._case_committee(r.id) as c from public.reports r where r.id = p_report) x
   where x.n > 0
     and coalesce(current_setting('smartsumbong.reroute_any', true), '') <> 'on'
     and x.c is not null
     and exists (select 1 from public.tanod_committees tc where tc.committee = x.c and tc.status = 'approved')
     and not exists (select 1 from public.reroute_questions q where q.report_id = p_report and q.attempt = x.n and q.state <> 'open')
$$;

/** May this tanod take the reroute? Any tanod, unless the case's committee has its own (then one of them). */
create or replace function public._reroute_ok(p_report uuid, p_tanod uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select v.c is null or exists (select 1 from public.tanod_committees tc where tc.tanod_id = p_tanod and tc.committee = v.c and tc.status = 'approved')
    from (select public._reroute_committee(p_report) as c) v
$$;

/** No tanod of the case's committee is free: ask its Kagawad (once per offer). True: asked or already waiting; false: reroute as before. */
create or replace function public._reroute_ask(p_report uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_com text := public._reroute_committee(p_report);
  r public.reports%rowtype; v_min smallint; v_q bigint; v_label text; v_msg text;
begin
  if v_com is null then return false; end if;
  if exists (select 1 from public.reroute_questions where report_id = p_report and state = 'open') then return true; end if;
  if not exists (select 1 from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false)) then
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
    from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false);
  insert into public.inbox_messages (recipient, kind, subject, body, report_id, question_id)
  select u.id, 'system', left('Pick a tanod for ' || r.tracking_id, 140), v_msg, p_report, v_q
    from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = v_com and not coalesce(u.is_suspended, false);
  return true;
end $$;

-- auto_dispatch: on a reroute, the case's committee's tanods first; none free, ask its Kagawad.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.auto_dispatch(uuid)'::regprocedure);
  n := replace(d, 'from public._smart_tanod_ranking(p_report) t limit 1;',
                  'from public._smart_tanod_ranking(p_report) t where public._reroute_ok(p_report, t.tanod_id) limit 1;');
  if n = d then raise exception '0155: the SMART pick in auto_dispatch was not found'; end if;
  d := n;
  n := replace(d, 'from public.nearest_available_tanod(p_report) t limit 1;',
                  'from public.nearest_available_tanod(p_report) t where public._reroute_ok(p_report, t.tanod_id) limit 1;');
  if n = d then raise exception '0155: the nearest pick in auto_dispatch was not found'; end if;
  d := n;
  n := replace(d, E'\n  if v_tanod is null then\n',
                  E'\n  -- 0155: on a reroute, none of the case''s committee''s tanods is free: ask its Kagawad first\n  if v_tanod is null and public._reroute_ask(p_report) then\n    return null;\n  end if;\n\n  if v_tanod is null then\n');
  if n = d then raise exception '0155: the no-tanod branch in auto_dispatch was not found'; end if;
  execute n;
end $patch$;

/**
 * The Kagawad (or a super admin) answers a reroute question: p_tanod sends that tanod; null lets the system send the nearest
 * from any committee now. Returns the new dispatch (null when nobody is free; the case then waits in line as before).
 */
create or replace function public.answer_reroute_question(p_question bigint, p_tanod uuid default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  q public.reroute_questions%rowtype; v_my text; v_d uuid; v_instr text;
begin
  select * into q from public.reroute_questions where id = p_question for update;
  if not found then raise exception 'No such question' using errcode = 'check_violation'; end if;
  select committee into v_my from public.users where id = auth.uid();
  if not (public.admin_tier() = 'super' or (public.admin_tier() = 'committee' and v_my = q.committee)) then
    raise exception 'The committee''s Kagawad answers this' using errcode = 'insufficient_privilege';
  end if;
  if q.state <> 'open' then raise exception 'This question was already answered' using errcode = 'check_violation'; end if;
  if p_tanod is not null then
    select admin_instructions into v_instr from public.dispatches where report_id = q.report_id order by assigned_at desc limit 1;
    v_d := public.admin_dispatch(q.report_id, p_tanod, left('Rerouted by the committee''s Kagawad. ' || coalesce(v_instr, ''), 1000));
  else
    perform set_config('smartsumbong.reroute_any', 'on', true);
    v_d := public.auto_dispatch(q.report_id);
    perform set_config('smartsumbong.reroute_any', 'off', true);
  end if;
  update public.reroute_questions
     set state = case when p_tanod is null then 'any' else 'picked' end, answered_by = auth.uid(), answered_at = now(), dispatch_id = v_d
   where id = p_question;
  return v_d;
end $$;

/** Every minute: a question past its wait sends the nearest tanod from any committee; one no longer needed closes. */
create or replace function public.sweep_reroute_questions()
returns void
language plpgsql security definer set search_path = public, extensions as $$
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
        from public.users u where u.role = 'admin' and u.admin_tier = 'committee' and u.committee = q.committee and not coalesce(u.is_suspended, false);
    end if;
  end loop;
end $$;

select cron.schedule('sweep-reroute-questions', '* * * * *', $$select public.sweep_reroute_questions()$$);

revoke all on function public._mail_may_send(uuid, uuid), public.mail_recipients(), public.send_mail(uuid[], text, text, uuid, bigint),
                       public.mark_mail_read(bigint[]), public._system_mail(uuid, text, text, uuid, bigint),
                       public._reroute_committee(uuid), public._reroute_ok(uuid, uuid), public._reroute_ask(uuid),
                       public.answer_reroute_question(bigint, uuid), public.sweep_reroute_questions() from public, anon, authenticated;
grant execute on function public.mail_recipients(), public.send_mail(uuid[], text, text, uuid, bigint), public.mark_mail_read(bigint[]),
                          public.answer_reroute_question(bigint, uuid) to authenticated;
