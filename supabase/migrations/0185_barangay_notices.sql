-- 0185: Barangay notices (the former "published incidents", as the barangay speaking), 20 Nov 2026.
-- DRAFT: not applied until Ace says "apply 0185".
--
-- Decided with Ace on the design canvas (19 Nov, frames M5 to M7): a notice is a PSA-style item on the residents' map. An administrator
-- writes a HEADLINE and a MESSAGE (plain text), may tie it to a place (a point and a radius) and a category, and it is active or
-- resolved. Residents get one push when it is published, and a notice kind they can mute.
--
-- ADDITIVE: reports.is_public, set_report_public() and public_incidents() are untouched (the app 1.0.8.5B still reads them).
--
--   notices              the notice itself. No direct writes from the API roles: every write is a function below.
--   notice_log           who published, edited, resolved or withdrew what, and when (append-only)
--   notifications.notice_id    which notice a notification is about (the push opens it); null for every other kind
--   notification_kind 'notice'   the new kind: muted per resident through set_notification_mute('notice', true), like any other kind
--
--   publish_notice(...)           one notice, one notification per eligible resident, one push each (send-dispatch-push)
--   edit_notice(...)              fixes the words or the place; sends nothing
--   resolve_notice(id)            marks it resolved; sends nothing (decided: a resolution is read on the map, not buzzed)
--   withdraw_notice(id, reason)   takes a mistaken notice off the residents' map (it stays in the log)
--   notices_admin_list(...)       what an administrator may manage
--   notices_for_residents()       what a resident reads: the notice's own words, place and status. Never the author, a report id or
--                                 anything a resident wrote.
--
-- Who may publish: a super admin (any category, or none for a barangay-wide notice); a Kagawad for a category of their own
-- committee (a category is required); staff (moderators) and the view-only captain tier cannot. Editing, resolving and withdrawing
-- follow the same rule, and a Kagawad's notice is never touched by another committee.
-- A notice that starts from a case (source_report_id) needs the case in the caller's scope, is never a sensitive case (consistent with
-- 0184), and takes its category and a place rounded to about 100 m from the case unless the caller sets them. The report id is never
-- shown to residents.
--
-- Flood guards, all inside publish_notice: 5 notices per administrator per hour and 20 per barangay per day; at most 20,000 notifications
-- for one notice; the same client_ref from the same administrator gives the same notice back (a double press or a retry publishes once).
--
-- Realtime: nothing is added to the publication. The app reads notices_for_residents() when the Map tab opens and when the push arrives.
-- The notification rows ride the existing notifications realtime/webhook as any other kind.
--
-- The enum value is added first and is only used inside function bodies, so this file is safe in one transaction.

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'notice';

-- ---------- the tables -------------------------------------------------------------

create table public.notices (
  id               uuid primary key default gen_random_uuid(),
  headline         text not null check (char_length(headline) between 4 and 90),
  message          text not null check (char_length(message) between 10 and 600),
  category         public.complaint_category,
  latitude         double precision check (latitude between 4 and 22),
  longitude        double precision check (longitude between 116 and 128),
  radius_m         integer check (radius_m between 30 and 5000),
  place_label      text check (place_label is null or char_length(place_label) between 2 and 80),
  status           text not null default 'active' check (status in ('active', 'resolved')),
  created_by       uuid references public.users (id) on delete set null,
  client_ref       text check (client_ref is null or char_length(client_ref) between 8 and 64),
  source_report_id uuid references public.reports (id) on delete set null,
  notified_count   integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  withdrawn_at     timestamptz,
  constraint notices_point_whole check ((latitude is null) = (longitude is null)),
  constraint notices_radius_needs_point check (radius_m is null or latitude is not null),
  constraint notices_resolved_stamped check ((status = 'resolved') = (resolved_at is not null))
);
comment on table public.notices is '0185: a barangay notice, written by an administrator for the residents'' map. Written only by publish_notice, edit_notice, resolve_notice and withdraw_notice. source_report_id and created_by are never shown to residents (notices_for_residents).';
comment on column public.notices.client_ref is '0185: the publishing form''s own reference; the same one from the same administrator is the same notice.';

create index notices_created_by_idx on public.notices (created_by, created_at desc);
create unique index notices_author_ref_uidx on public.notices (created_by, client_ref) where client_ref is not null;
create index notices_category_idx on public.notices (category) where category is not null;
create index notices_status_idx on public.notices (status, created_at desc) where withdrawn_at is null;
create unique index notices_one_active_per_case_uidx on public.notices (source_report_id) where source_report_id is not null and status = 'active' and withdrawn_at is null;
create index notices_created_idx on public.notices (created_at desc);

create table public.notice_log (
  id         bigint generated always as identity primary key,
  notice_id  uuid not null references public.notices (id) on delete cascade,
  action     text not null check (action in ('publish', 'edit', 'resolve', 'withdraw')),
  actor      uuid references public.users (id) on delete set null,
  detail     text check (detail is null or char_length(detail) <= 500),
  created_at timestamptz not null default now()
);
comment on table public.notice_log is '0185: every publish, edit, resolve and withdraw of a notice, with who did it; append-only, written by the notice functions.';
create index notice_log_notice_idx on public.notice_log (notice_id, created_at);
create index notice_log_actor_idx on public.notice_log (actor);

alter table public.notifications
  add column notice_id uuid references public.notices (id) on delete cascade;
comment on column public.notifications.notice_id is '0185: the notice a notification of kind notice is about; null for every other kind.';
create index notifications_notice_idx on public.notifications (notice_id) where notice_id is not null;

-- ---------- row level security: administrators read what they may manage; nobody writes by hand ---------------------

alter table public.notices enable row level security;
alter table public.notice_log enable row level security;

-- may the signed-in administrator manage a notice of this category? (super: all, including none; a Kagawad: their committee's categories)
create or replace function public._can_manage_notice(p_cat public.complaint_category)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.admin_tier()
           when 'super' then true
           when 'committee' then p_cat is not null and public._user_sees_category(auth.uid(), p_cat)
           else false
         end $$;
revoke all on function public._can_manage_notice(public.complaint_category) from public, anon;
grant execute on function public._can_manage_notice(public.complaint_category) to authenticated;

create policy notices_admin_read on public.notices for select to authenticated
  using ((select public.is_full_viewer()) or public._can_manage_notice(category));
create policy notice_log_admin_read on public.notice_log for select to authenticated
  using ((select public.is_full_viewer())
         or exists (select 1 from public.notices n where n.id = notice_log.notice_id and public._can_manage_notice(n.category)));

revoke all on public.notices, public.notice_log from anon;
revoke insert, update, delete on public.notices, public.notice_log from authenticated;
grant select on public.notices, public.notice_log to authenticated;

-- ---------- the functions ------------------------------------------------------------------

-- plain text: tidy spaces, no control characters
create or replace function public._notice_text(p_text text, p_multiline boolean)
returns text language sql immutable set search_path = public as $$
  select nullif(btrim(case when p_multiline
      then regexp_replace(regexp_replace(replace(coalesce(p_text, ''), E'\r', ''), '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g'), E'\n{3,}', E'\n\n', 'g')
      else regexp_replace(regexp_replace(coalesce(p_text, ''), '[\x01-\x1F\x7F]', ' ', 'g'), '\s+', ' ', 'g') end), '') $$;
revoke all on function public._notice_text(text, boolean) from public, anon;

-- the shared checks of publish and edit: the words and the place; returns the cleaned values
create or replace function public._notice_check(p_headline text, p_message text, p_lat double precision, p_lng double precision, p_radius integer, p_label text,
                                                out o_headline text, out o_message text, out o_label text)
language plpgsql immutable set search_path = public as $$
begin
  o_headline := public._notice_text(p_headline, false);
  o_message  := public._notice_text(p_message, true);
  o_label    := public._notice_text(p_label, false);
  if o_headline is null or char_length(o_headline) not between 4 and 90 then
    raise exception 'The headline needs 4 to 90 characters.' using errcode = 'check_violation';
  end if;
  if o_message is null or char_length(o_message) not between 10 and 600 then
    raise exception 'The message needs 10 to 600 characters.' using errcode = 'check_violation';
  end if;
  if o_label is not null and char_length(o_label) not between 2 and 80 then
    raise exception 'The place name needs 2 to 80 characters.' using errcode = 'check_violation';
  end if;
  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Give both the latitude and the longitude, or neither.' using errcode = 'check_violation';
  end if;
  if p_lat is not null and (p_lat not between 4 and 22 or p_lng not between 116 and 128) then
    raise exception 'That place is outside the Philippines.' using errcode = 'check_violation';
  end if;
  if p_radius is not null and (p_lat is null or p_radius not between 30 and 5000) then
    raise exception 'The reach is 30 to 5,000 metres around a point.' using errcode = 'check_violation';
  end if;
end $$;
revoke all on function public._notice_check(text, text, double precision, double precision, integer, text) from public, anon;

create or replace function public.publish_notice(
  p_headline text, p_message text, p_category public.complaint_category default null,
  p_lat double precision default null, p_lng double precision default null, p_radius_m integer default null,
  p_place_label text default null, p_source_report uuid default null, p_client_ref text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid  uuid := auth.uid();
  v_tier text := public.admin_tier();
  v_cat  public.complaint_category := p_category;
  v_lat  double precision := p_lat;
  v_lng  double precision := p_lng;
  v_ref  text := nullif(btrim(coalesce(p_client_ref, '')), '');
  v_id   uuid;
  v_n    integer;
  v_clean record;
  v_src  record;
begin
  if v_uid is null then raise exception 'Not signed in' using errcode = 'insufficient_privilege'; end if;
  if v_tier is null or not public.admin_can_write() then
    raise exception 'Only an administrator may publish a notice.' using errcode = 'insufficient_privilege';
  end if;
  if v_tier = 'moderator' then
    raise exception 'Staff cannot publish a notice. Ask your Kagawad.' using errcode = 'insufficient_privilege';
  end if;
  if v_ref is not null and char_length(v_ref) not between 8 and 64 then
    raise exception 'That form is not valid. Please try again.' using errcode = 'check_violation';
  end if;

  -- serialised per administrator, so two presses at once cannot both pass the checks below
  perform pg_advisory_xact_lock(hashtextextended('notice_publish:' || v_uid::text, 0));

  -- one press, one notice: the same reference from the same administrator is the notice already made
  if v_ref is not null then
    select id into v_id from public.notices where created_by = v_uid and client_ref = v_ref;
    if found then return v_id; end if;
  end if;

  -- a notice that starts from a case: the case must be theirs to work, ordinary, and not already a notice
  if p_source_report is not null then
    perform public._scope_guard(p_source_report, true);
    select r.id, r.category, r.latitude, r.longitude, r.is_sensitive, r.deleted_at, r.status into v_src from public.reports r where r.id = p_source_report;
    if not found or v_src.deleted_at is not null then raise exception 'No such report' using errcode = 'no_data_found'; end if;
    if v_src.is_sensitive then
      raise exception 'A sensitive case is never shown on the residents'' map' using errcode = 'check_violation';
    end if;
    if v_src.status in ('rejected', 'cancelled') then
      raise exception 'A rejected or cancelled report cannot become a notice.' using errcode = 'check_violation';
    end if;
    v_cat := coalesce(v_cat, v_src.category);
    if v_lat is null and v_lng is null then
      -- about 100 m: a notice says where to expect trouble, never which door
      v_lat := round(v_src.latitude::numeric, 3)::double precision;
      v_lng := round(v_src.longitude::numeric, 3)::double precision;
    end if;
  end if;

  if v_tier = 'committee' then
    if v_cat is null then raise exception 'Choose the category of the notice.' using errcode = 'check_violation'; end if;
    if not public._can_manage_notice(v_cat) then
      raise exception 'That category belongs to another committee.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_clean from public._notice_check(p_headline, p_message, v_lat, v_lng, p_radius_m, p_place_label);

  -- the flood guards
  if (select count(*) from public.notices n where n.created_by = v_uid and n.created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Slow down: you have published 5 notices in the last hour. Try again later.' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.notices n where n.created_at > now() - interval '24 hours') >= 20 then
    raise exception 'Slow down: the barangay has published 20 notices in the last day. Try again tomorrow.' using errcode = 'check_violation';
  end if;
  if p_source_report is not null and exists (select 1 from public.notices n where n.source_report_id = p_source_report and n.status = 'active' and n.withdrawn_at is null) then
    raise exception 'This case is already an active notice.' using errcode = 'check_violation';
  end if;

  insert into public.notices (headline, message, category, latitude, longitude, radius_m, place_label, created_by, client_ref, source_report_id)
  values (v_clean.o_headline, v_clean.o_message, v_cat, v_lat, v_lng, p_radius_m, v_clean.o_label, v_uid, v_ref, p_source_report)
  returning id into v_id;

  -- one notification per resident who can be told (muting a kind holds back the push only, as since 0044: the row is the in-app record)
  select count(*) into v_n from public.users u
   where u.role = 'resident' and u.verification_status = 'verified' and not u.is_suspended and u.removed_at is null and not coalesce(u.is_test, false);
  if v_n > 20000 then
    raise exception 'That would notify % residents, more than one notice may reach. Ask the team to raise the limit.', v_n using errcode = 'check_violation';
  end if;
  insert into public.notifications (user_id, kind, message, notice_id)
  select u.id, 'notice', v_clean.o_headline, v_id from public.users u
   where u.role = 'resident' and u.verification_status = 'verified' and not u.is_suspended and u.removed_at is null and not coalesce(u.is_test, false);
  get diagnostics v_n = row_count;
  update public.notices set notified_count = v_n where id = v_id;

  insert into public.notice_log (notice_id, action, actor, detail)
  values (v_id, 'publish', v_uid, format('%s; told %s residents%s', v_clean.o_headline, v_n, case when p_source_report is not null then '; from a case' else '' end));
  return v_id;
end $$;

create or replace function public.edit_notice(
  p_id uuid, p_headline text, p_message text, p_category public.complaint_category default null,
  p_lat double precision default null, p_lng double precision default null, p_radius_m integer default null, p_place_label text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_old public.notices%rowtype;
  v_clean record;
begin
  if v_uid is null or not public.admin_can_write() then
    raise exception 'Only an administrator may change a notice.' using errcode = 'insufficient_privilege';
  end if;
  select * into v_old from public.notices where id = p_id and withdrawn_at is null for update;
  if not found then raise exception 'No such notice' using errcode = 'no_data_found'; end if;
  if not public._can_manage_notice(v_old.category) or (public.admin_tier() = 'committee' and not public._can_manage_notice(p_category)) then
    raise exception 'That notice belongs to another committee.' using errcode = 'insufficient_privilege';
  end if;
  select * into v_clean from public._notice_check(p_headline, p_message, p_lat, p_lng, p_radius_m, p_place_label);
  update public.notices
     set headline = v_clean.o_headline, message = v_clean.o_message, category = p_category,
         latitude = p_lat, longitude = p_lng, radius_m = p_radius_m, place_label = v_clean.o_label, updated_at = now()
   where id = p_id;
  insert into public.notice_log (notice_id, action, actor, detail) values (p_id, 'edit', v_uid, v_clean.o_headline);
end $$;

create or replace function public.resolve_notice(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_old public.notices%rowtype;
begin
  if v_uid is null or not public.admin_can_write() then
    raise exception 'Only an administrator may resolve a notice.' using errcode = 'insufficient_privilege';
  end if;
  select * into v_old from public.notices where id = p_id and withdrawn_at is null for update;
  if not found then raise exception 'No such notice' using errcode = 'no_data_found'; end if;
  if not public._can_manage_notice(v_old.category) then
    raise exception 'That notice belongs to another committee.' using errcode = 'insufficient_privilege';
  end if;
  if v_old.status = 'resolved' then return; end if;
  update public.notices set status = 'resolved', resolved_at = now(), updated_at = now() where id = p_id;
  insert into public.notice_log (notice_id, action, actor, detail) values (p_id, 'resolve', v_uid, v_old.headline);
end $$;

create or replace function public.withdraw_notice(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_old public.notices%rowtype;
  v_why text := left(public._notice_text(p_reason, false), 300);
begin
  if v_uid is null or not public.admin_can_write() then
    raise exception 'Only an administrator may withdraw a notice.' using errcode = 'insufficient_privilege';
  end if;
  select * into v_old from public.notices where id = p_id and withdrawn_at is null for update;
  if not found then raise exception 'No such notice' using errcode = 'no_data_found'; end if;
  if not public._can_manage_notice(v_old.category) then
    raise exception 'That notice belongs to another committee.' using errcode = 'insufficient_privilege';
  end if;
  if v_why is null or char_length(v_why) < 4 then
    raise exception 'Say why the notice is being withdrawn.' using errcode = 'check_violation';
  end if;
  update public.notices set withdrawn_at = now(), updated_at = now() where id = p_id;
  insert into public.notice_log (notice_id, action, actor, detail) values (p_id, 'withdraw', v_uid, v_why);
end $$;

-- what an administrator manages: a super admin and the captain read all, a Kagawad their committee's categories; staff are refused
create or replace function public.notices_admin_list(p_status text default null, p_limit integer default 100)
returns table (id uuid, headline text, message text, category public.complaint_category, latitude double precision, longitude double precision,
               radius_m integer, place_label text, status text, created_at timestamptz, updated_at timestamptz, resolved_at timestamptz,
               withdrawn_at timestamptz, author text, source_tracking_id text, notified_count integer, can_manage boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null or public.admin_tier() is null or public.admin_tier() = 'moderator' then
    raise exception 'Notices are managed by the Kagawad and the super admins.' using errcode = 'insufficient_privilege';
  end if;
  return query
  select n.id, n.headline, n.message, n.category, n.latitude, n.longitude, n.radius_m, n.place_label, n.status, n.created_at, n.updated_at, n.resolved_at,
         n.withdrawn_at, u.full_name, r.tracking_id, n.notified_count,
         public.admin_can_write() and public._can_manage_notice(n.category)
    from public.notices n
    left join public.users u on u.id = n.created_by
    left join public.reports r on r.id = n.source_report_id
   where (public.is_full_viewer() or public._can_manage_notice(n.category))
     and (p_status is null or n.status = p_status)
     and (p_status is distinct from 'active' or n.withdrawn_at is null)
   order by (n.withdrawn_at is null) desc, (n.status = 'active') desc, n.created_at desc
   limit least(greatest(coalesce(p_limit, 100), 1), 200);
end $$;

-- what a resident reads: the notice's own words, place and status; active ones, and resolved ones for 90 days; withdrawn ones never
create or replace function public.notices_for_residents()
returns table (id uuid, headline text, message text, category public.complaint_category, latitude double precision, longitude double precision,
               radius_m integer, place_label text, status text, created_at timestamptz, updated_at timestamptz, resolved_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select n.id, n.headline, n.message, n.category, n.latitude, n.longitude, n.radius_m, n.place_label, n.status, n.created_at, n.updated_at, n.resolved_at
    from public.notices n
   where auth.uid() is not null
     and n.withdrawn_at is null
     and (n.status = 'active' or n.resolved_at > now() - interval '90 days')
   order by (n.status = 'active') desc, n.created_at desc
   limit 200
$$;

comment on function public.publish_notice(text, text, public.complaint_category, double precision, double precision, integer, text, uuid, text) is
  '0185: publish a barangay notice and notify every eligible resident once. Super admins (any category) and Kagawad (their committee''s categories); 5 an hour per administrator, 20 a day; the same client_ref is the same notice.';
comment on function public.notices_for_residents() is
  '0185: the notices a resident reads (headline, message, category, place, status, times). No author, no report, nothing a resident wrote.';

-- ---------- the push carries the notice ----------------------------------------------------------

-- push_plan (0136) is as it was, and its record now says which notice a notification is about, so the push can open it
create or replace function public.push_plan(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  n record;
  u record;
  v_hour int := extract(hour from now() at time zone 'Asia/Manila');
  v_urgent boolean;
  v_why text;
begin
  select * into n from public.notifications where id = p_id;
  if not found then return null; end if;
  select muted_notification_kinds, push_scope, push_quiet_from, push_quiet_to, push_quiet_urgent
    into u from public.users where id = n.user_id;

  v_urgent := n.report_id is not null
              and exists (select 1 from public.report_triage t where t.report_id = n.report_id and t.effective_level = 'urgent');

  if n.kind = 'test' then
    v_why := null;
  elsif n.kind = any (coalesce(u.muted_notification_kinds, '{}')) then
    v_why := 'muted';
  elsif u.push_scope = 'mine' and n.report_id is not null
        and not exists (select 1 from public.reports r
                         where r.id = n.report_id and (r.handler_id = n.user_id or r.resident_id = n.user_id))
        and not exists (select 1 from public.dispatches d where d.report_id = n.report_id and d.tanod_id = n.user_id) then
    v_why := 'not their case';
  elsif n.kind = 'notice' and n.notice_id is not null
        and exists (select 1 from public.notices x where x.id = n.notice_id and (x.status <> 'active' or x.withdrawn_at is not null)) then
    v_why := 'notice no longer active';   -- resolved or withdrawn before this resident's push went out
  elsif u.push_quiet_from is not null
        and (case when u.push_quiet_from < u.push_quiet_to then v_hour >= u.push_quiet_from and v_hour < u.push_quiet_to
                  else v_hour >= u.push_quiet_from or v_hour < u.push_quiet_to end)
        and not (u.push_quiet_urgent and v_urgent) then
    v_why := 'quiet hours';
  end if;

  return jsonb_build_object(
    'send', v_why is null,
    'why', v_why,
    'record', jsonb_build_object('id', n.id, 'user_id', n.user_id, 'report_id', n.report_id, 'kind', n.kind, 'message', n.message, 'notice_id', n.notice_id),
    'tracking_id', (select r.tracking_id from public.reports r where r.id = n.report_id),
    'urgent', v_urgent,
    'tokens', coalesce((select jsonb_agg(t.fcm_token) from public.device_tokens t where t.user_id = n.user_id), '[]'),
    'web', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'endpoint', w.endpoint, 'p256dh', w.p256dh, 'auth', w.auth))
                       from public.web_push_subscriptions w where w.user_id = n.user_id), '[]'));
end $$;

-- ---------- grants ----------------------------------------------------------------------------------

revoke all on function public.publish_notice(text, text, public.complaint_category, double precision, double precision, integer, text, uuid, text) from public, anon;
revoke all on function public.edit_notice(uuid, text, text, public.complaint_category, double precision, double precision, integer, text) from public, anon;
revoke all on function public.resolve_notice(uuid) from public, anon;
revoke all on function public.withdraw_notice(uuid, text) from public, anon;
revoke all on function public.notices_admin_list(text, integer) from public, anon;
revoke all on function public.notices_for_residents() from public, anon;
grant execute on function public.publish_notice(text, text, public.complaint_category, double precision, double precision, integer, text, uuid, text) to authenticated;
grant execute on function public.edit_notice(uuid, text, text, public.complaint_category, double precision, double precision, integer, text) to authenticated;
grant execute on function public.resolve_notice(uuid) to authenticated;
grant execute on function public.withdraw_notice(uuid, text) to authenticated;
grant execute on function public.notices_admin_list(text, integer) to authenticated;
grant execute on function public.notices_for_residents() to authenticated;
