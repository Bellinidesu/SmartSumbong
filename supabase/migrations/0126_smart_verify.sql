-- 0126: SMART Verify, ID checks on the server (10 Oct 2026).
--
-- The line SMART draws for OCR: a model may READ, rules DECIDE. The phone
-- reads the ID with on-device OCR (ML Kit, id_ocr.dart: offline, free, the
-- photo never leaves the phone for it) and sends only what it read: the ID
-- type it recognised, the name and the number. Everything that judges
-- happens here, by rules, with reasons an admin can check against the
-- photo. docs/SMART.md, "SMART Verify".
--
-- Why on the server: until now the app worked out ocr_flags itself and
-- wrote them straight onto the account (users_self_update), so a modified
-- app could send no flags and look "clean" for Quick Verify. Now the OCR
-- columns change only through submit_id_reading(), which computes the
-- flags itself, and the guard refuses any other change to them. The phone
-- can still misreport what it read, so a reading never approves anyone:
-- the admin still looks at the photo (docs/SMART_SCREENS.md).
--
-- OCR itself stays switched off (Rose, 27-30 Sep 2026: ID_OCR_ENABLED,
-- kIdOcrEnabled). This is what runs when the barangay turns it back on.

set search_path = public, extensions;

-- ---------- only the server writes the OCR columns -----------------------------

create or replace function public.guard_privileged_user_fields()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  -- auth.uid() is null only for service_role / backend contexts, which
  -- bypass RLS anyway; an unauthenticated client never reaches this row.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- The resident's own account deletion (request_account_deletion) scrubs
  -- these fields on purpose.
  if current_setting('smartsumbong.account_deletion', true) = 'on' and new.id = auth.uid() then
    return new;
  end if;

  if new.role                   is distinct from old.role
     or new.verification_status is distinct from old.verification_status
     or new.is_suspended        is distinct from old.is_suspended
     or new.verified_by         is distinct from old.verified_by
     or new.verified_at         is distinct from old.verified_at
     or new.rejection_reason    is distinct from old.rejection_reason then
    raise exception
      'Only an administrator may change account role, verification, or suspension state';
  end if;

  if new.mobile_number is distinct from old.mobile_number then
    raise exception
      'Your mobile number is how you sign in. Please ask the barangay to change it.';
  end if;

  if new.full_name is distinct from old.full_name then
    raise exception
      'Please ask the barangay to change the name on your account.';
  end if;

  -- 0126: what OCR read, and the flags from it, come only through
  -- submit_id_reading(), which sets this for its own update.
  if current_setting('smartsumbong.id_reading', true) is distinct from 'on'
     and (new.ocr_flags            is distinct from old.ocr_flags
       or new.ocr_detected_type    is distinct from old.ocr_detected_type
       or new.ocr_extracted_name   is distinct from old.ocr_extracted_name
       or new.ocr_extracted_number is distinct from old.ocr_extracted_number
       or new.ocr_processed_at     is distinct from old.ocr_processed_at) then
    raise exception 'The ID reading is saved by the app''s ID check, not edited directly.';
  end if;

  return new;
end $$;

-- ---------- reading names and numbers ------------------------------------------

/** A name as comparable words: capitals, OCR's usual digit-for-letter
    slips fixed inside words (0 O, 1 I, 2 Z, 5 S, 6 G, 8 B), punctuation out,
    suffixes like JR and III dropped. */
create or replace function public._smart_name_words(p_name text)
returns text[]
language sql
immutable
set search_path = public, extensions
as $$
  select coalesce(array_agg(w) filter (where length(w) >= 2 and w not in ('JR', 'SR', 'II', 'III', 'IV')), '{}')
    from unnest(regexp_split_to_array(
           trim(regexp_replace(upper(coalesce(p_name, '')), '[^A-Z0-9Ñ]+', ' ', 'g')), ' ')) as t(raw)
    cross join lateral (select case when raw ~ '[A-ZÑ]' then translate(raw, '012568', 'OIZSGB') else raw end as w) x
$$;

/** How well the name read off the ID covers the registered name
    ("Last, First Middle"): every surname word and at least one given-name
    word must be there, exactly or one letter off (for words of 5+). */
create or replace function public._smart_name_match(p_registered text, p_read text)
returns jsonb
language sql
immutable
set search_path = public, extensions
as $$
  with parts as (
    select public._smart_name_words(split_part(p_registered, ',', 1)) as surname,
           public._smart_name_words(case when position(',' in p_registered) > 0
                                         then split_part(p_registered, ',', 2) else '' end) as given,
           public._smart_name_words(p_read) as seen
  ), hit as (
    select w, kind, exists (select 1 from parts, unnest(parts.seen) s
                             where s = w or (length(w) >= 5 and levenshtein(s, w) <= 1)) as found
      from parts, lateral (select unnest(parts.surname) as w, 'surname' as kind
                           union all select unnest(parts.given), 'given') u
  )
  select jsonb_build_object(
    'result', case
      when (select count(*) from hit) = 0 or not exists (select 1 from hit where found) then 'none'
      when not exists (select 1 from hit where kind = 'surname' and not found)
       and exists (select 1 from hit where kind = 'given' and found) then 'match'
      else 'partial' end,
    'found',   coalesce((select jsonb_agg(w) from hit where found), '[]'),
    'missing', coalesce((select jsonb_agg(w) from hit where not found), '[]'))
$$;

/** An ID number in one form for comparing: capitals and digits only. */
create or replace function public._smart_id_number(p_number text)
returns text
language sql
immutable
as $$ select nullif(regexp_replace(upper(coalesce(p_number, '')), '[^A-Z0-9]', '', 'g'), '') $$;

/** Whether a number has the shape its ID type prints (only for types whose
    format is fixed): PhilSys card number 16 digits; LTO licence one letter
    and ten digits (A01-23-456789); passport one letter, seven digits, one
    letter (P1234567A) or the older two letters and seven digits. Null:
    no fixed format to check. */
create or replace function public._smart_id_number_ok(p_type public.id_document_type, p_number text)
returns boolean
language sql
immutable
as $$
  select case p_type
    when 'philsys'         then public._smart_id_number(p_number) ~ '^[0-9]{16}$'
    when 'drivers_license' then public._smart_id_number(p_number) ~ '^[A-Z][0-9]{10}$'
    when 'passport'        then public._smart_id_number(p_number) ~ '^([A-Z][0-9]{7}[A-Z]|[A-Z]{2}[0-9]{7})$'
    else null end
$$;

-- ---------- the checks -------------------------------------------------------------

/** The flags and reasons for one account's ID reading. */
create or replace function public._smart_verify(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  u public.users%rowtype;
  v_why jsonb := '[]';
  v_flags text[] := '{}';
  v_name jsonb;
  v_ok boolean;
  v_num text;
  o record;
  v_level text;
begin
  select * into u from public.users where id = p_user;
  if not found then return null; end if;
  if u.ocr_processed_at is null then
    return jsonb_build_object('level', 'no_reading', 'flags', '[]'::jsonb,
      'reasons', jsonb_build_array(jsonb_build_object('check', 'reading', 'result', 'none',
        'detail', 'The app has not read this ID (ID check off, an older app, or skipped).')));
  end if;

  if u.ocr_extracted_name is null and u.ocr_extracted_number is null and u.ocr_detected_type is null then
    v_flags := array_append(v_flags, 'unreadable');
    v_why := v_why || jsonb_build_object('check', 'reading', 'result', 'check',
      'detail', 'The ID could not be read: blurred, dark, or not an ID.');
  end if;

  -- type
  if u.ocr_detected_type is not null and u.id_type is not null and u.ocr_detected_type <> u.id_type then
    v_flags := array_append(v_flags, 'type_mismatch');
    v_why := v_why || jsonb_build_object('check', 'type', 'result', 'check',
      'detail', format('Chosen: %s; the card reads like: %s.', u.id_type, u.ocr_detected_type));
  elsif u.ocr_detected_type is not null then
    v_why := v_why || jsonb_build_object('check', 'type', 'result', 'ok',
      'detail', format('Reads like the chosen ID (%s).', u.ocr_detected_type));
  end if;

  -- name
  if u.ocr_extracted_name is not null then
    v_name := public._smart_name_match(u.full_name, u.ocr_extracted_name);
    if v_name ->> 'result' = 'match' then
      v_why := v_why || jsonb_build_object('check', 'name', 'result', 'ok',
        'detail', format('Name on the ID matches (%s).', u.ocr_extracted_name));
    else
      v_flags := array_append(v_flags, 'name_mismatch');
      v_why := v_why || jsonb_build_object('check', 'name',
        'result', case when v_name ->> 'result' = 'none' then 'problem' else 'check' end,
        'detail', format('Name on the ID: %s. Not found: %s.', u.ocr_extracted_name,
                         (select string_agg(x, ', ') from jsonb_array_elements_text(v_name -> 'missing') x)));
    end if;
  elsif u.ocr_extracted_number is not null or u.ocr_detected_type is not null then
    v_flags := array_append(v_flags, 'name_mismatch');
    v_why := v_why || jsonb_build_object('check', 'name', 'result', 'check', 'detail', 'No name could be read.');
  end if;

  -- number
  v_num := public._smart_id_number(u.ocr_extracted_number);
  if v_num is null then
    if u.ocr_extracted_name is not null or u.ocr_detected_type is not null then
      v_flags := array_append(v_flags, 'no_id_number');
      v_why := v_why || jsonb_build_object('check', 'number', 'result', 'check', 'detail', 'No ID number could be read.');
    end if;
  else
    v_ok := public._smart_id_number_ok(coalesce(u.id_type, u.ocr_detected_type), v_num);
    if v_ok is false then
      v_flags := array_append(v_flags, 'number_format');
      v_why := v_why || jsonb_build_object('check', 'number', 'result', 'check',
        'detail', format('%s does not have the shape a %s number has.', u.ocr_extracted_number, coalesce(u.id_type, u.ocr_detected_type)));
    elsif v_ok then
      v_why := v_why || jsonb_build_object('check', 'number', 'result', 'ok',
        'detail', format('%s has the right shape for a %s.', u.ocr_extracted_number, u.id_type));
    end if;

    -- the same ID on another account
    for o in
      select x.id, x.full_name, x.verification_status, x.role
        from public.users x
       where x.id <> u.id and public._smart_id_number(x.ocr_extracted_number) = v_num
       limit 3
    loop
      v_flags := array_append(v_flags, 'number_reused');
      v_why := v_why || jsonb_build_object('check', 'number', 'result', 'problem', 'other_account', o.id,
        'detail', format('The same ID number is on another account: %s (%s, %s).',
                         public.display_name(o.full_name), o.role, o.verification_status));
    end loop;
  end if;

  v_level := case
    when exists (select 1 from jsonb_array_elements(v_why) r where r ->> 'result' = 'problem') then 'problem'
    when exists (select 1 from jsonb_array_elements(v_why) r where r ->> 'result' = 'check') then 'check'
    else 'ready' end;
  return jsonb_build_object('level', v_level, 'flags', to_jsonb(array(select distinct f from unnest(v_flags) f order by f)),
                            'reasons', v_why,
                            'read', jsonb_build_object('type', u.ocr_detected_type, 'name', u.ocr_extracted_name,
                                                       'number', u.ocr_extracted_number, 'at', u.ocr_processed_at));
end $$;

revoke all on function public._smart_verify(uuid) from public, anon, authenticated;

-- ---------- the phone sends what it read ------------------------------------------

/** Called by the app after its on-device OCR pass, for the signed-in
    account only: stores what was read, works out the flags here, and
    clears a pending re-check request (0050). Never raises over a bad read;
    a resident's registration must not fail over this. */
create or replace function public.submit_id_reading(p_detected_type public.id_document_type,
                                                    p_name text, p_number text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('smartsumbong.id_reading', 'on', true);
  update public.users
     set ocr_detected_type = p_detected_type,
         ocr_extracted_name = nullif(left(trim(p_name), 120), ''),
         ocr_extracted_number = nullif(left(trim(p_number), 40), ''),
         ocr_processed_at = now(),
         ocr_rescan_requested_at = null
   where id = v_uid;
  update public.users
     set ocr_flags = array(select jsonb_array_elements_text(public._smart_verify(v_uid) -> 'flags'))
   where id = v_uid;
  perform set_config('smartsumbong.id_reading', 'off', true);
end $$;

revoke all on function public.submit_id_reading(public.id_document_type, text, text) from public, anon;
grant execute on function public.submit_id_reading(public.id_document_type, text, text) to authenticated;

-- ---------- what admins see ----------------------------------------------------------

/** Admins: one account's ID checks: level (ready, check, problem, or
    no_reading), flags, reasons, and what was read. */
create or replace function public.smart_verify(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see ID checks.' using errcode = 'insufficient_privilege';
  end if;
  return public._smart_verify(p_user);
end $$;

revoke all on function public.smart_verify(uuid) from public, anon;
grant execute on function public.smart_verify(uuid) to authenticated;

/** Admins: accounts waiting for verification with their ID-check level,
    problems first, then accounts to check, then ready ones, oldest first. */
create or replace function public.smart_verify_queue(p_role public.user_role default null)
returns table (user_id uuid, full_name text, role public.user_role, submitted_at timestamptz,
               level text, flags jsonb, reasons jsonb)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can see ID checks.' using errcode = 'insufficient_privilege';
  end if;
  return query
  select u.id, public.display_name(u.full_name), u.role, u.created_at,
         v ->> 'level', v -> 'flags', v -> 'reasons'
    from public.users u
    cross join lateral (select public._smart_verify(u.id) as v) x
   where u.verification_status = 'pending'
     and (p_role is null or u.role = p_role)
   order by array_position(array['problem', 'check', 'no_reading', 'ready'], v ->> 'level'), u.created_at;
end $$;

revoke all on function public.smart_verify_queue(public.user_role) from public, anon;
grant execute on function public.smart_verify_queue(public.user_role) to authenticated;
