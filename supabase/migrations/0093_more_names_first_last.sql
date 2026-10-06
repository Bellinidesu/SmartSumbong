-- 0093 - Appointing an admin and take_case: names read First Last too (Rose, 7 Oct 2026).
-- Only messages and audit wording change; stored names stay "Last, First".

CREATE OR REPLACE FUNCTION public.promote_to_admin(p_user uuid, p_reason text DEFAULT NULL::text, p_handover_days integer DEFAULT NULL::integer, p_revert_role user_role DEFAULT NULL::user_role)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may appoint another administrator';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.role = 'admin' then
    raise exception '% is already an administrator', public.display_name(v_user.full_name);
  end if;

  if v_user.verification_status <> 'verified' then
    raise exception
      '% is not a verified account. Only a verified resident or tanod of Barangay 183 may be appointed.',
      public.display_name(v_user.full_name);
  end if;

  if v_user.is_suspended then
    raise exception '% is suspended and cannot be appointed', public.display_name(v_user.full_name);
  end if;

  if p_handover_days is not null then
    if p_handover_days < 1 or p_handover_days > 90 then
      raise exception 'A handover window must be between 1 and 90 days';
    end if;
    if p_revert_role is null or p_revert_role = 'admin' then
      raise exception 'Choose the role you will return to when the handover ends';
    end if;
  end if;

  -- A tanod who becomes an admin stops being dispatchable: they are no
  -- longer on the roster, and leaving them in it would send incidents to
  -- someone sitting at a desk. sync_dispatchable does this on its own
  -- once the role changes, but the duty status is cleared here so the
  -- Personnel screen does not still show them as On Duty.
  update public.users
     set role        = 'admin',
         duty_status = null
   where id = p_user;

  if p_handover_days is not null then
    update public.users
       set admin_handover_until        = now() + (p_handover_days || ' days')::interval,
           admin_handover_role         = p_revert_role,
           admin_handover_successor_id = p_user
     where id = auth.uid();
  end if;

  insert into public.account_audit (subject_id, actor_id, action, detail)
  values (p_user, auth.uid(), 'promoted_to_admin',
          coalesce(v_reason, format('Appointed by %s',
            (select public.display_name(full_name) from public.users where id = auth.uid()))));

  if p_handover_days is not null then
    insert into public.account_audit (subject_id, actor_id, action, detail)
    values (auth.uid(), auth.uid(), 'handover_scheduled',
            format('Training %s for up to %s day(s); returns to %s on %s',
              public.display_name(v_user.full_name), p_handover_days, p_revert_role,
              to_char(now() + (p_handover_days || ' days')::interval, 'Mon dd, yyyy')));
  end if;

  insert into public.notifications (user_id, kind, message)
  values (p_user, 'verification',
          'You have been given barangay administrator access to Smart Sumbong.'
          || case when p_handover_days is not null
               then format(' The outgoing administrator will continue to help for up to %s day(s).', p_handover_days)
               else '' end);

  return public.display_name(v_user.full_name);
end $function$;

CREATE OR REPLACE FUNCTION public.take_case(p_report uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_h uuid; v_name text;
begin
  if not public.is_admin() then raise exception 'Only an administrator may take a case'; end if;
  select handler_id into v_h from public.reports where id = p_report and deleted_at is null for update;
  if not found then raise exception 'No such report'; end if;
  if v_h = auth.uid() then return; end if;
  if v_h is not null then
    select public.display_name(full_name) into v_name from public.users where id = v_h;
    raise exception '% is already handling this case. Use Take over.', coalesce(v_name, 'Another administrator');
  end if;
  perform set_config('smartsumbong.handler_change', 'on', true);
  update public.reports set handler_id = auth.uid(), handled_since = now() where id = p_report;
  perform set_config('smartsumbong.handler_change', 'off', true);
  insert into public.case_handler_log (report_id, admin_id, action) values (p_report, auth.uid(), 'take');
end $function$;
