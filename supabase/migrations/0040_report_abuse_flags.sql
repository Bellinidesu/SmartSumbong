-- =============================================================
-- SmartSumbong — 0040 Report abuse flags and auto-restriction
--
-- reports_resident_insert (0003) already blocks a suspended resident
-- from filing anything: `and not u.is_suspended` in the RLS check. And
-- set_account_suspension (0013) already lets an admin suspend an
-- account, reused as-is here rather than duplicated -- for a resident,
-- is_suspended already means exactly "cannot file a report" and nothing
-- broader, so a second, parallel "restricted" flag would just be the
-- same state under a different name.
--
-- What was actually missing: nothing distinguished an ordinary rejected
-- report ("wrong barangay", "duplicate of BRG-2026-0123") from a
-- bad-faith one, nothing counted a pattern per resident, and nothing
-- acted on that count automatically -- every suspension was a manual
-- admin click, every time, for every reason including this one.
--
-- Threshold is 3 flagged reports, decided with the user (29 Aug 2026):
-- forgiving enough that one bad report never costs someone their
-- account, firm enough that a real pattern doesn't need an admin to
-- notice it themselves across a queue full of other complaints. A
-- literal constant in review_report() below, not an operational_settings
-- row like the SLA policies -- nobody asked for it to be barangay-
-- tunable, and a stray digit in a migration is easier to reason about
-- than a settings row nobody remembers exists.
--
-- Restriction lifts the same way suspension already does: an admin
-- clicks Reinstate on the resident's account. No auto-expiry, decided
-- with the user -- reuses set_account_suspension's existing reinstate
-- path rather than inventing a second, time-based one.
-- =============================================================

set search_path = public, extensions;

-- ---------- the flag itself -----------------------------------

alter table public.status_logs
  add column if not exists is_abusive boolean not null default false;

comment on column public.status_logs.is_abusive is
  'Set only alongside a reject decision in review_report() -- an admin '
  'marking this specific denial as bad-faith (fabricated, malicious, '
  'spam) rather than an honest mistake (wrong barangay, duplicate, not '
  'enough detail). Meaningless on any other new_status; review_report() '
  'never sets it true for anything but a reject. Counted per resident to '
  'drive the 3-strike auto-restriction below.';

-- ---------- review_report: adds the abuse flag + auto-restrict --
-- New trailing parameter, so this is a distinct signature from 0011's
-- three-argument version -- drop that one explicitly or it keeps
-- existing alongside this one as a silent second overload.

drop function if exists public.review_report(uuid, text, text);

create or replace function public.review_report(
  p_report   uuid,
  p_decision text,                    -- 'validate' | 'reject'
  p_remark   text default null,
  p_abusive  boolean default false)
returns report_status
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_new      report_status;
  v_remark   text := nullif(trim(coalesce(p_remark, '')), '');
  v_abusive  boolean;
  v_strikes  integer;
  v_resident public.users%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may review a complaint';
  end if;

  if p_decision not in ('validate', 'reject') then
    raise exception 'Unknown decision: %', p_decision;
  end if;

  select * into v_report
    from public.reports
   where id = p_report and deleted_at is null
     for update;

  if not found then
    raise exception 'No such report';
  end if;

  if v_report.status <> 'pending_review' then
    raise exception 'This complaint has already been reviewed (current status: %)',
      replace(v_report.status::text, '_', ' ');
  end if;

  if p_decision = 'reject' and v_remark is null then
    raise exception 'A reason is required when denying a complaint';
  end if;

  -- Only a reject can be abusive. A stray true on a validate call (there
  -- is no UI path that sends one, but nothing stops a direct RPC call)
  -- is silently dropped rather than raising -- this flag is additive
  -- bookkeeping, not something worth failing the whole review over.
  v_abusive := p_decision = 'reject' and coalesce(p_abusive, false);

  v_new := case p_decision when 'validate' then 'validated' else 'rejected' end::report_status;

  update public.reports
     set status = v_new
   where id = p_report;

  insert into public.status_logs
    (report_id, changed_by, old_status, new_status, remark, is_abusive)
  values
    (p_report, auth.uid(), v_report.status, v_new,
     coalesce(v_remark,
              'Complaint accepted for action by the barangay admin.'),
     v_abusive);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_report.resident_id, p_report, 'status_change',
          case p_decision
            when 'validate' then
              format('%s has been accepted and is now with the barangay.', v_report.tracking_id)
            else
              format('%s was not accepted. Reason: %s', v_report.tracking_id, v_remark)
          end);

  -- Auto-restriction. Counted fresh each time rather than kept as a
  -- running column on users -- this table is small per resident and a
  -- computed count can never drift out of sync with the log it is
  -- supposedly summarising, unlike a counter that has to be remembered
  -- to update everywhere the flag could change.
  if v_abusive then
    select count(*) into v_strikes
      from public.status_logs sl
      join public.reports r2 on r2.id = sl.report_id
     where r2.resident_id = v_report.resident_id
       and sl.is_abusive = true
       and sl.new_status = 'rejected';

    select * into v_resident from public.users where id = v_report.resident_id;

    if v_strikes >= 3 and v_resident.id is not null and not v_resident.is_suspended then
      perform public.set_account_suspension(
        v_report.resident_id,
        true,
        format('Automatically restricted: %s reports flagged as abusive.', v_strikes));
    end if;
  end if;

  return v_new;
end $$;

revoke execute on function public.review_report(uuid, text, text, boolean) from public, anon;
grant  execute on function public.review_report(uuid, text, text, boolean) to authenticated;

comment on function public.review_report(uuid, text, text, boolean) is
  'Validate Report / deny path, now with an optional abuse flag on a '
  'reject. At 3 abuse-flagged rejects for the same resident, calls '
  'set_account_suspension() itself -- same suspension, same RLS block on '
  'reports_resident_insert, same Reinstate button an admin already knows, '
  'just system-triggered instead of manual.';

-- ---------- the admin-facing history -----------------------------
-- Backs both case.php's "N flags on file" note next to the Deny panel
-- (context before an admin flags a new one) and accounts.php's Abuse
-- History panel on the resident's own profile (the full list). One
-- function, two call sites -- count(rows) is the number either screen
-- needs, the rows themselves are the other.

create or replace function public.resident_abuse_reports(p_user uuid)
returns table (
  report_id   uuid,
  tracking_id text,
  subject     text,
  remark      text,
  flagged_at  timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.tracking_id, r.subject, sl.remark, sl.created_at
    from public.status_logs sl
    join public.reports r on r.id = sl.report_id
   where public.is_admin()
     and r.resident_id = p_user
     and sl.is_abusive = true
     and sl.new_status = 'rejected'
   order by sl.created_at desc
$$;

revoke execute on function public.resident_abuse_reports(uuid) from public, anon;
grant  execute on function public.resident_abuse_reports(uuid) to authenticated;

comment on function public.resident_abuse_reports(uuid) is
  'Every report rejected AND flagged abusive for one resident, newest '
  'first. Admin only -- the where clause returns zero rows rather than '
  'raising for anyone else, same style as tanod_roster()''s own guard.';

-- ---------- surface the count on the accounts list -------------
-- account_directory (0013, extended by 0039 for OCR) -- one more
-- column appended at the end, same reasoning 0039 already gave for
-- appending rather than reordering: existing callers select by name.
--
-- Same drop-first requirement as review_report above and as 0039 now
-- does for this same function -- CREATE OR REPLACE cannot add a column
-- to a RETURNS TABLE function.
drop function if exists public.account_directory(user_role);

create or replace function public.account_directory(p_role user_role)
returns table (
  id                  uuid,
  full_name           text,
  email               text,
  mobile_number       text,
  role                user_role,
  verification_status verification_state,
  is_suspended        boolean,
  duty_status         duty_state,
  id_image_url        text,
  selfie_url          text,
  rejection_reason    text,
  submitted_at        timestamptz,
  due_at              timestamptz,
  minutes_left        integer,
  is_overdue          boolean,
  holding_incident    boolean,
  created_at          timestamptz,
  ocr_detected_type   id_document_type,
  ocr_flags           text[],
  ocr_extracted_name  text,
  ocr_extracted_number text,
  abuse_strike_count  integer)
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
            and sl.new_status = 'rejected')
    from public.users u
   where u.role = p_role
   order by (u.verification_status = 'pending') desc,
            cardinality(u.ocr_flags) > 0 desc,
            u.verification_due_at nulls last,
            u.full_name
$$;

revoke execute on function public.account_directory(user_role) from public, anon;
grant  execute on function public.account_directory(user_role) to authenticated;

comment on function public.account_directory(user_role) is
  'Residents / Personnel list. Pending first, then flagged-by-OCR first '
  'within that, soonest deadline after -- the two-hour window and the '
  'OCR flags are the ordering, not columns the admin has to hunt for. '
  'abuse_strike_count is a live count, not a stored counter -- see '
  'resident_abuse_reports() for the rows behind the number.';

-- Verification. Run separately.
--
--   select is_abusive, new_status, count(*) from public.status_logs
--    group by 1, 2 order by 1, 2;
--
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname = 'review_report';
