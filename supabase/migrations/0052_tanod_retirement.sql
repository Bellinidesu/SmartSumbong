-- =============================================================
-- SmartSumbong — 0052 Tanod retirement (replaces self-account-deletion
--                     for service personnel)
--
-- Residents can delete their own account (0045). A tanod cannot: that
-- account is an appointment record, not a consumer signup, and the
-- barangay's own instruction was explicit — "self account deletion is
-- not allowed, only retirement." Retirement ends a tanod's ability to
-- sign in without touching a single fact already on file. Nothing here
-- scrubs a name, an email, or a dispatch history the way 0045 does for
-- a resident who deletes themselves — a retired tanod's record is kept
-- exactly as it stands, because it is now an employment record.
--
-- TWO-PRONGED, ON PURPOSE. The barangay's instruction described the
-- mobile side of this precisely: entering "EXTRA ADMINISTRATIVE
-- SERVICES" takes a password, and asking to retire from inside it takes
-- the password again before anything is sent. Both checks are the
-- client re-authenticating the same way sign-in already does (see
-- AuthService.verifyPassword in mobile/core) — this migration is the
-- second prong, the one no phone screen can fake: the request this
-- creates changes nothing about the account by itself. An admin has to
-- open the new Retirement Requests queue and decide. Compare
-- verify_user_account (0013): a barangay appointment was never
-- self-service to end, and it is not self-service to end here either.
--
-- WHY A REQUEST TABLE RATHER THAN A STRAIGHT FLAG FLIP. A tanod who
-- taps Retire cannot be allowed to just BE retired — that is exactly
-- the self-service power the barangay ruled out. request_retirement()
-- only ever queues an ask; is_retired only ever changes inside
-- finalize_retirement(), and only on 'approve'. The audit trail the
-- barangay gets for free this way — who asked, when, who decided, on
-- what reason if refused — is also what the dedicated Retirement
-- Requests queue in the portal is built to show, separate from the
-- Personnel page's own suspend/reinstate history.
--
-- WHY "MARK RETIRED, KEEP EVERYTHING INTACT" RATHER THAN 0045'S SCRUB.
-- Confirmed directly: retirement is not a deletion. sync_dispatchable
-- is updated so a retired tanod can never be dispatched again, and the
-- launch gate (client side, same as suspension) refuses to let a
-- retired account past sign-in — but full_name, contact info, and every
-- dispatch/attendance record already on file are left exactly as they
-- were. That is also why this does not touch GoTrue: no ban, the same
-- way an ordinary suspension does not (0013's own header explains why).
-- =============================================================

set search_path = public, extensions;

-- ---------- schema -------------------------------------------

alter type notification_kind add value if not exists 'retirement';

create type retirement_status as enum ('pending', 'approved', 'denied');

alter table public.users
  add column if not exists is_retired boolean not null default false,
  add column if not exists retired_at timestamptz;

comment on column public.users.is_retired is
  'Set only by finalize_retirement() on approval. Never a self-service flag — see 0052 header.';
comment on column public.users.retired_at is
  'When an admin approved the retirement request. Null until then.';

create table public.retirement_requests (
  id            uuid primary key default gen_random_uuid(),
  tanod_id      uuid not null references public.users (id) on delete cascade,
  status        retirement_status not null default 'pending',
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid references public.users (id),
  denial_reason text
);

-- At most one open ask per tanod at a time — a second tap while one is
-- already sitting with the admin should tell them so, not queue a
-- duplicate for the same request to be decided twice over.
create unique index retirement_requests_one_pending_idx
  on public.retirement_requests (tanod_id) where status = 'pending';

create index retirement_requests_status_idx
  on public.retirement_requests (status, requested_at);

comment on table public.retirement_requests is
  'A tanod''s ask to end their service. Insert only via request_retirement(); '
  'decided only via finalize_retirement(). See 0052 header.';

-- ---------- RLS -------------------------------------------------
-- Same shape as dispatches (0003): a plain select policy scoped to the
-- owner or an admin, and an admin-only catch-all for everything else.
-- Deliberately no insert/update policy for the tanod themselves — every
-- actual write goes through a security definer RPC below, never a raw
-- table write, exactly the reasoning 0003 states for dispatches.

alter table public.retirement_requests enable row level security;

create policy retirement_requests_read on public.retirement_requests
  for select using (tanod_id = auth.uid() or public.is_admin());

create policy retirement_requests_admin_write on public.retirement_requests
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------- sync_dispatchable, extended --------------------------
-- A retired tanod must never be handed a fresh dispatch — the account
-- exists as a record now, not as someone who can be sent anywhere.

create or replace function public.sync_dispatchable()
returns trigger language plpgsql as $$
begin
  new.is_dispatchable := coalesce(
    new.role = 'tanod'
    and new.duty_status = 'on_duty'
    and new.verification_status = 'verified'
    and not new.is_suspended
    and not new.is_retired, false);
  return new;
end $$;

-- ---------- request_retirement() ---------------------------------
-- Called by the tanod, from the password-confirmed Retirement screen.
-- Queues the ask; changes nothing about the account. Notifies every
-- admin the same way verify_user_account's applicant notification does
-- the other direction.

create or replace function public.request_retirement()
returns public.retirement_requests
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user public.users%rowtype;
  v_req  public.retirement_requests%rowtype;
  a      record;
begin
  select * into v_user from public.users where id = auth.uid() for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.role <> 'tanod' then
    raise exception 'Only a tanod may request retirement';
  end if;

  if v_user.is_retired then
    raise exception 'This account has already retired';
  end if;

  if exists (
    select 1 from public.retirement_requests
     where tanod_id = v_user.id and status = 'pending'
  ) then
    raise exception 'A retirement request for this account is already waiting on the barangay';
  end if;

  insert into public.retirement_requests (tanod_id)
  values (v_user.id)
  returning * into v_req;

  for a in select id from public.users where role = 'admin' loop
    insert into public.notifications (user_id, kind, message)
    values (a.id, 'retirement',
            format('%s has requested retirement.', v_user.full_name));
  end loop;

  return v_req;
end $$;

revoke execute on function public.request_retirement() from public, anon;
grant  execute on function public.request_retirement() to authenticated;

comment on function public.request_retirement() is
  'Tanod-only. Queues a retirement request and notifies every admin. '
  'Never changes users.is_retired itself — see finalize_retirement().';

-- ---------- finalize_retirement() ---------------------------------
-- Admin only, mirrors verify_user_account/set_account_suspension
-- exactly: row-locked, decision validated, a reason required on the
-- negative decision, one notification back to the tanod. On approval
-- it also releases any live dispatch, the same protection suspension
-- already gets in 0013 — a retired tanod's phone must not sit holding
-- an incident that will never be worked.

create or replace function public.finalize_retirement(
  p_request  uuid,
  p_decision text,                    -- 'approve' | 'deny'
  p_reason   text default null)
returns retirement_status
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_req    public.retirement_requests%rowtype;
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_new    retirement_status;
  d        record;
begin
  if not public.is_admin() then
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
    raise exception 'This request has already been decided (current status: %)',
      v_req.status;
  end if;

  if p_decision = 'deny' and v_reason is null then
    raise exception 'A reason is required when denying a retirement request';
  end if;

  select * into v_user from public.users where id = v_req.tanod_id for update;
  if not found then
    raise exception 'That tanod account no longer exists';
  end if;

  v_new := case p_decision when 'approve' then 'approved' else 'denied' end::retirement_status;

  update public.retirement_requests
     set status        = v_new,
         decided_at    = now(),
         decided_by    = auth.uid(),
         denial_reason = v_reason
   where id = p_request;

  if v_new = 'approved' then
    update public.users
       set is_retired  = true,
           retired_at  = now(),
           duty_status = null
     where id = v_user.id;

    -- Same protection set_account_suspension gives a suspended tanod
    -- (0013): a live dispatch cannot be left on a phone that is about
    -- to stop being checked.
    for d in
      update public.dispatches
         set state = 'expired'
       where tanod_id = v_user.id and state in ('assigned', 'accepted')
      returning report_id
    loop
      perform public.redispatch_report(d.report_id, 'assigned tanod has retired');
    end loop;
  end if;

  insert into public.notifications (user_id, kind, message)
  values (v_user.id, 'retirement',
          case v_new
            when 'approved' then
              'Your retirement has been approved. Thank you for your service — this account can no longer sign in.'
            else
              format('Your retirement request was not approved. Reason: %s', v_reason)
          end);

  return v_new;
end $$;

revoke execute on function public.finalize_retirement(uuid, text, text) from public, anon;
grant  execute on function public.finalize_retirement(uuid, text, text) to authenticated;

comment on function public.finalize_retirement(uuid, text, text) is
  'Manage Retirement Request, admin only. Approve sets is_retired/retired_at and '
  'releases any live dispatch, mirroring set_account_suspension exactly.';

-- ---------- retirement_requests_queue() ---------------------------
-- The new admin portal page's listing. Same shape as account_directory
-- (0013/0051): plain `language sql stable`, no security definer — the
-- retirement_requests_read policy above already scopes an admin caller
-- to every row and a non-admin caller to just their own, so there is
-- nothing this function needs to do that RLS does not already do for it.

create or replace function public.retirement_requests_queue()
returns table (
  id              uuid,
  tanod_id        uuid,
  full_name       text,
  email           text,
  mobile_number   text,
  status          retirement_status,
  requested_at    timestamptz,
  decided_at      timestamptz,
  decided_by      uuid,
  decided_by_name text,
  denial_reason   text)
language sql stable set search_path = public, extensions as $$
  select r.id, r.tanod_id, u.full_name, u.email, u.mobile_number,
         r.status, r.requested_at, r.decided_at, r.decided_by, d.full_name,
         r.denial_reason
    from public.retirement_requests r
    join public.users u on u.id = r.tanod_id
    left join public.users d on d.id = r.decided_by
   order by (r.status = 'pending') desc, r.requested_at desc
$$;

revoke execute on function public.retirement_requests_queue() from public, anon;
grant  execute on function public.retirement_requests_queue() to authenticated;

comment on function public.retirement_requests_queue() is
  'Retirement Requests queue. Pending first, newest first within that.';

-- ---------- my_retirement_status() ---------------------------------
-- What the tanod app's own Retirement screen needs on repeat visits: is
-- there already a request in flight, or a denial worth explaining,
-- rather than the screen only ever finding out by having a fresh
-- request_retirement() call fail. Relies on the same read policy above,
-- so no security definer and no argument — the caller's own uid decides
-- what comes back.

create or replace function public.my_retirement_status()
returns table (
  status        retirement_status,
  requested_at  timestamptz,
  decided_at    timestamptz,
  denial_reason text)
language sql stable set search_path = public, extensions as $$
  select r.status, r.requested_at, r.decided_at, r.denial_reason
    from public.retirement_requests r
   where r.tanod_id = auth.uid()
   order by r.requested_at desc
   limit 1
$$;

revoke execute on function public.my_retirement_status() from public, anon;
grant  execute on function public.my_retirement_status() to authenticated;

comment on function public.my_retirement_status() is
  'Latest retirement request for the calling tanod, or no rows if none was ever filed.';

-- ---------- account_directory(), extended --------------------------
-- Same drop-first requirement 0039/0040/0050/0051 all hit — CREATE OR
-- REPLACE cannot add a column to an existing RETURNS TABLE function.
-- Personnel now shows retirement standing alongside verification and
-- suspension, the same list an admin already checks before anything
-- else about a tanod.

drop function if exists public.account_directory(user_role);

create or replace function public.account_directory(p_role user_role)
returns table (
  id                      uuid,
  full_name               text,
  email                   text,
  mobile_number           text,
  role                    user_role,
  verification_status     verification_state,
  is_suspended            boolean,
  duty_status             duty_state,
  id_image_url            text,
  selfie_url              text,
  rejection_reason        text,
  submitted_at            timestamptz,
  due_at                  timestamptz,
  minutes_left            integer,
  is_overdue              boolean,
  holding_incident        boolean,
  created_at              timestamptz,
  ocr_detected_type       id_document_type,
  ocr_flags               text[],
  ocr_extracted_name      text,
  ocr_extracted_number    text,
  abuse_strike_count      integer,
  ocr_processed_at        timestamptz,
  ocr_rescan_requested_at timestamptz,
  id_type                 id_document_type,
  suspended_reason        text,
  is_retired              boolean,
  retired_at              timestamptz)
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
         u.retired_at
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
  'within that, soonest deadline after. Carries id_type, suspended_reason '
  '(0051) and now is_retired/retired_at (0052) so Personnel shows every '
  'account-standing signal in one place.';

-- Verification. Run separately.
--
--   select proname, pg_get_function_result(oid)
--     from pg_proc where proname in ('request_retirement', 'finalize_retirement',
--                                     'retirement_requests_queue', 'my_retirement_status');
--
--   -- confirm a retired tanod is excluded from dispatch eligibility:
--   select full_name, is_retired, is_dispatchable from public.users
--    where is_retired = true;
