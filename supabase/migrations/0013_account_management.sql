-- =============================================================
-- SmartSumbong — 0013 Account verification and suspension
--
-- Verify User Account and Manage User Account are both use cases with
-- no implementation. As with case review, an admin could *almost* do
-- them with a plain UPDATE — guard_privileged_user_fields waves admins
-- through, and users_admin_all allows the write. What they cannot do is
-- insert the notification telling the applicant, because notifications
-- has no insert policy by design.
--
-- The verification decision also has a second effect the portal must not
-- be trusted to remember: suspending a tanod who is holding a live
-- incident. sync_dispatchable will stop future dispatches, but the
-- incident already on their phone would sit there unworked with the
-- report still marked 'assigned'. So suspension releases it back to the
-- queue the same way an elapsed acceptance window does.
--
-- DECISION FOR THE BARANGAY: the agreed design shows an "Uploaded
-- Selfie" panel beside the ID. The Register Account use case asks only
-- for a government ID (residents) or a barangay appointment ID
-- (tanods) — no selfie. Rather than drop a panel from an agreed design
-- or silently invent a registration requirement, this adds a NULLABLE
-- selfie_url. The portal shows the panel and says "not submitted" when
-- it is empty, so nothing breaks either way. If the barangay does want
-- a selfie at signup, that is a change to the Flutter registration
-- flow, to UC 1, and to the Data Dictionary — not just to this column.
-- =============================================================

set search_path = public, extensions;

alter table public.users
  add column if not exists selfie_url text;

comment on column public.users.selfie_url is
  'Optional liveness photo. Nullable: the Register Account use case does not require it. See 0013 header.';

-- ---------- Verify User Account ------------------------------

create or replace function public.verify_user_account(
  p_user     uuid,
  p_decision text,                    -- 'approve' | 'deny'
  p_reason   text default null)
returns verification_state
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user   public.users%rowtype;
  v_new    verification_state;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may verify an account';
  end if;

  if p_decision not in ('approve', 'deny') then
    raise exception 'Unknown decision: %', p_decision;
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if v_user.role = 'admin' then
    raise exception 'Administrator accounts are not verified through this queue';
  end if;

  if v_user.verification_status <> 'pending' then
    raise exception 'This account has already been reviewed (current status: %)',
      v_user.verification_status;
  end if;

  -- A rejection the applicant cannot act on just produces a second
  -- identical registration an hour later.
  if p_decision = 'deny' and v_reason is null then
    raise exception 'A reason is required when denying an account';
  end if;

  v_new := case p_decision when 'approve' then 'verified' else 'rejected' end::verification_state;

  update public.users
     set verification_status = v_new,
         verified_at         = case when v_new = 'verified' then now() end,
         verified_by         = auth.uid(),
         rejection_reason    = v_reason
   where id = p_user;

  insert into public.notifications (user_id, kind, message)
  values (p_user, 'verification',
          case p_decision
            when 'approve' then
              'Your Smart Sumbong account has been verified. You may now file a complaint.'
            else
              format('Your registration was not approved. Reason: %s', v_reason)
          end);

  return v_new;
end $$;

revoke execute on function public.verify_user_account(uuid, text, text) from public, anon;
grant  execute on function public.verify_user_account(uuid, text, text) to authenticated;

comment on function public.verify_user_account(uuid, text, text) is
  'Verify User Account. Admin only, pending only. Status, audit fields and applicant notification in one transaction.';

-- ---------- Manage User Account: suspension ------------------

create or replace function public.set_account_suspension(
  p_user    uuid,
  p_suspend boolean,
  p_reason  text default null)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user   public.users%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  d        record;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may suspend an account';
  end if;

  select * into v_user from public.users where id = p_user for update;
  if not found then
    raise exception 'No such account';
  end if;

  if p_user = auth.uid() then
    raise exception 'You cannot suspend your own account';
  end if;

  if v_user.role = 'admin' then
    raise exception 'Administrator accounts cannot be suspended from this screen';
  end if;

  if v_user.is_suspended = p_suspend then
    raise exception 'That account is already %',
      case when p_suspend then 'suspended' else 'active' end;
  end if;

  if p_suspend and v_reason is null then
    raise exception 'A reason is required when suspending an account';
  end if;

  update public.users
     set is_suspended     = p_suspend,
         suspended_reason = case when p_suspend then v_reason end
   where id = p_user;

  -- Suspending a tanod mid-incident cannot leave the complaint parked on
  -- a phone that will never open again. Same treatment as an acceptance
  -- window that elapsed: close the dispatch, put the report back in the
  -- queue, let proximity find someone else.
  if p_suspend and v_user.role = 'tanod' then
    for d in
      update public.dispatches
         set state = 'expired'
       where tanod_id = p_user and state in ('assigned', 'accepted')
      returning report_id
    loop
      perform public.redispatch_report(d.report_id, 'assigned tanod was suspended');
    end loop;
  end if;

  insert into public.notifications (user_id, kind, message)
  values (p_user,
          'verification',
          case when p_suspend
            then format('Your account has been suspended. Reason: %s', v_reason)
            else 'Your account has been reinstated.'
          end);

  return p_suspend;
end $$;

revoke execute on function public.set_account_suspension(uuid, boolean, text) from public, anon;
grant  execute on function public.set_account_suspension(uuid, boolean, text) to authenticated;

comment on function public.set_account_suspension(uuid, boolean, text) is
  'Manage User Account suspend/reinstate. Releases any live dispatch the tanod was holding back to the queue.';

-- ---------- the two queues the portal lists ------------------
-- Both screens are the same shape with a different role filter, so this
-- is one function. It exists rather than a plain PostgREST select
-- because the useful columns are computed: how long a pending account
-- has been waiting against the two-hour window, and whether a tanod is
-- currently holding an incident.

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
  created_at          timestamptz)
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
         u.created_at
    from public.users u
   where u.role = p_role
   order by (u.verification_status = 'pending') desc,
            u.verification_due_at nulls last,
            u.full_name
$$;

revoke execute on function public.account_directory(user_role) from public, anon;
grant  execute on function public.account_directory(user_role) to authenticated;

comment on function public.account_directory(user_role) is
  'Residents / Personnel list. Pending first, soonest deadline first — the two-hour window is the ordering, not a column to hunt for.';
