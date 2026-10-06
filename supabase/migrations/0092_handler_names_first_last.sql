-- 0092 - Names in the case-handler messages read First Last (Rose, 7 Oct 2026).
--
-- "X is handling this case" and "X took over ... from you" printed the
-- stored "Last, First". Same functions as 0087, name through display_name().

CREATE OR REPLACE FUNCTION public._case_guard(p_report uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select public.display_name(full_name) into v_name from public.users where id = v_h;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._case_guard_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select public.display_name(full_name) into v_name from public.users where id = old.handler_id;
    raise exception '% is handling this case. Take it over to act on it.', coalesce(v_name, 'Another administrator');
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.take_over_case(p_report uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select public.display_name(full_name) into v_me from public.users where id = auth.uid();
    insert into public.notifications (user_id, report_id, kind, message)
    values (v_h, p_report, 'status_change', coalesce(v_me, 'Another administrator') || ' took over ' || v_track || ' from you: ' || v_reason);
  end if;
end $function$;
