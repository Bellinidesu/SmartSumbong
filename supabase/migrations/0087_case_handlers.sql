-- 0087 — A handler for every case (6 Oct 2026).
--
-- With several administrators, two of them could act on the same complaint
-- at once. Now each case has a handler: the first admin to act on it (or to
-- press Take this case) becomes its handler, and only the handler can act
-- on it until they release it or another admin takes it over with a reason.
-- It is enforced here, in the database, by triggers on everything an admin
-- action writes, so no second tab, stale page or double-click gets round it.
-- Residents, tanods and the scheduled jobs are never affected.
--
-- reports.version moves on every change, so the portal can tell an admin
-- "this case changed while you were looking" instead of doubling up.
-- case_handler_log records takes, releases and take-overs for the portal's
-- Activity page; it is admin-only (the resident's timeline never shows it).

set search_path = public, extensions;

alter table public.reports
  add column if not exists handler_id    uuid references public.users (id),
  add column if not exists handled_since timestamptz,
  add column if not exists version       bigint not null default 0;

create index if not exists reports_handler_idx on public.reports (handler_id) where handler_id is not null;

create table if not exists public.case_handler_log (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports (id) on delete cascade,
  admin_id    uuid not null references public.users (id),
  action      text not null check (action in ('take', 'release', 'take_over')),
  previous_id uuid references public.users (id),
  reason      text check (char_length(reason) <= 300),
  created_at  timestamptz not null default now()
);
create index if not exists case_handler_log_idx on public.case_handler_log (created_at desc);

alter table public.case_handler_log enable row level security;
drop policy if exists case_handler_log_read on public.case_handler_log;
create policy case_handler_log_read on public.case_handler_log for select using ((select public.is_admin()));

-- ---------- enforcement ----------------------------------------------

-- Called before anything an admin action writes about a report. Claims an
-- unclaimed case for the acting admin; refuses if someone else holds it.
create or replace function public._case_guard(p_report uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_h   uuid;
  v_name text;
begin
  if p_report is null or v_uid is null or not public.is_admin() then
    return;
  end if;
  if current_setting('smartsumbong.handler_change', true) = 'on' then
    return;
  end if;
  select handler_id into v_h from public.reports where id = p_report;
  if v_h is null then
    perform set_config('smartsumbong.handler_change', 'on', true);
    update public.reports set handler_id = v_uid, handled_since = now()
     where id = p_report and handler_id is null;
    insert into public.case_handler_log (report_id, admin_id, action) values (p_report, v_uid, 'take');
    perform set_config('smartsumbong.handler_change', 'off', true);
  elsif v_h <> v_uid then
    select full_name into v_name from public.users where id = v_h;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
end $$;
revoke all on function public._case_guard(uuid) from public, anon, authenticated;

create or replace function public._case_guard_row()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'report_messages' then
    if new.from_barangay then perform public._case_guard(new.report_id); end if;
  elsif tg_table_name = 'dispatch_updates' then
    perform public._case_guard((select report_id from public.dispatches where id = new.dispatch_id));
  else
    perform public._case_guard(new.report_id);
  end if;
  return new;
end $$;

drop trigger if exists case_guard on public.status_logs;
create trigger case_guard before insert on public.status_logs for each row execute function public._case_guard_row();
drop trigger if exists case_guard on public.report_messages;
create trigger case_guard before insert on public.report_messages for each row execute function public._case_guard_row();
drop trigger if exists case_guard on public.dispatch_updates;
create trigger case_guard before insert on public.dispatch_updates for each row execute function public._case_guard_row();
drop trigger if exists case_guard on public.report_evidence;
create trigger case_guard before insert on public.report_evidence for each row execute function public._case_guard_row();

-- Direct changes to the report itself (target date, publishing, status).
create or replace function public._case_guard_report()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
begin
  new.version := coalesce(old.version, 0) + 1;
  if v_uid is null or current_setting('smartsumbong.handler_change', true) = 'on' or not public.is_admin() then
    return new;
  end if;
  if old.handler_id is null then
    new.handler_id := v_uid;
    new.handled_since := now();
    insert into public.case_handler_log (report_id, admin_id, action) values (new.id, v_uid, 'take');
  elsif old.handler_id <> v_uid then
    select full_name into v_name from public.users where id = old.handler_id;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
  return new;
end $$;

drop trigger if exists case_guard on public.reports;
create trigger case_guard before update on public.reports for each row execute function public._case_guard_report();

-- ---------- take, release, take over ---------------------------------

create or replace function public.take_case(p_report uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_h uuid; v_name text;
begin
  if not public.is_admin() then raise exception 'Only an administrator may take a case'; end if;
  select handler_id into v_h from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h = auth.uid() then return; end if;
  if v_h is not null then
    select full_name into v_name from public.users where id = v_h;
    raise exception '% is already handling this case. Use Take over.', coalesce(v_name, 'Another administrator');
  end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = auth.uid(), handled_since = now() where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action) values (p_report, auth.uid(), 'take');
end $$;

create or replace function public.release_case(p_report uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_h uuid;
begin
  if not public.is_admin() then raise exception 'Only an administrator may release a case'; end if;
  select handler_id into v_h from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h is distinct from auth.uid() then raise exception 'Only the handler can release this case'; end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = null, handled_since = null where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action) values (p_report, auth.uid(), 'release');
end $$;

create or replace function public.take_over_case(p_report uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_h      uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_me     text;
  v_track  text;
begin
  if not public.is_admin() then raise exception 'Only an administrator may take over a case'; end if;
  if v_reason is null or char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Give a reason for taking over (the current handler sees it)';
  end if;
  select handler_id, tracking_id into v_h, v_track from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h = auth.uid() then return; end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = auth.uid(), handled_since = now() where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action, previous_id, reason)
  values (p_report, auth.uid(), case when v_h is null then 'take' else 'take_over' end, v_h, v_reason);
  if v_h is not null then
    select full_name into v_me from public.users where id = auth.uid();
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_h, p_report, 'status_change', coalesce(v_me, 'Another administrator') || ' took over ' || v_track || ' from you: ' || v_reason);
  end if;
end $$;

revoke all on function public.take_case(uuid) from public, anon;
revoke all on function public.release_case(uuid) from public, anon;
revoke all on function public.take_over_case(uuid, text) from public, anon;
grant execute on function public.take_case(uuid) to authenticated;
grant execute on function public.release_case(uuid) to authenticated;
grant execute on function public.take_over_case(uuid, text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'case_handler_log') then
    alter publication supabase_realtime add table public.case_handler_log;
  end if;
end $$;
