-- =============================================================
-- SmartSumbong — 0157 Edit Profile's banner, alerts for the Inbox, and the
-- Kagawad's endorsement of a retirement
--
-- Roles and pages, step 7 (docs/ROLES_AND_PAGES.md, "Edit Profile" and
-- "Administrative Services"; decided with Ace on 30 Oct 2026).
--
--   users.banner_*          the profile banner: the person's sidebar colour
--                           (the default), the barangay's contour pattern, a
--                           solid colour, the committee's colour, or their own
--                           picture, moved up or down to frame it
--   set_my_banner()         an administrator sets their own
--   'inbox_mail'            a notification kind that carries the alert for a
--                           new Inbox message (so it can be switched off like
--                           the others); the Notifications list leaves it out,
--                           the Inbox already shows the message
--   retirement_requests     a Kagawad sees the requests of their committee's
--     .endorsed_*           tanods and can endorse one to the super admins,
--   endorse_retirement()    who still decide
-- =============================================================

set search_path = public, extensions;

alter type public.notification_kind add value if not exists 'inbox_mail';

alter table public.users
  add column banner_preset text not null default 'sidebar' check (banner_preset in ('sidebar', 'contour', 'solid', 'committee', 'photo')),
  add column banner_colour text check (banner_colour is null or banner_colour ~ '^#[0-9A-Fa-f]{6}$'),
  add column banner_url text check (banner_url is null or banner_url like 'https://res.cloudinary.com/%'),
  add column banner_y smallint not null default 50 check (banner_y between 0 and 100);
comment on column public.users.banner_preset is '0157: the profile banner: sidebar (the default), contour, solid (banner_colour), committee, or photo (banner_url, framed at banner_y percent).';

/** An administrator sets their own profile banner. */
create or replace function public.set_my_banner(p_preset text, p_colour text default null, p_url text default null, p_y integer default 50)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.admin_tier() is null then raise exception 'Only an administrator has a profile banner here' using errcode = 'insufficient_privilege'; end if;
  if p_preset = 'solid' and (p_colour is null or p_colour !~ '^#[0-9A-Fa-f]{6}$') then raise exception 'Pick a colour' using errcode = 'check_violation'; end if;
  if p_preset = 'photo' and p_url is null and (select banner_url from public.users where id = auth.uid()) is null then
    raise exception 'Choose a picture for the banner' using errcode = 'check_violation';
  end if;
  update public.users
     set banner_preset = p_preset,
         banner_colour = case when p_preset = 'solid' then upper(p_colour) else banner_colour end,
         banner_url    = coalesce(p_url, banner_url),
         banner_y      = greatest(0, least(100, coalesce(p_y, 50)))
   where id = auth.uid();
end $$;

-- A new Inbox message also raises an alert (kind inbox_mail), which each person can switch off on their profile.
create or replace function public._inbox_alert()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'mail' then
    insert into public.notifications (user_id, kind, message)
    values (new.recipient, 'inbox_mail',
            left(format('New message from %s: %s', coalesce((select public.display_name(full_name) from public.users where id = new.sender), 'an administrator'), new.subject), 500));
  end if;
  return new;
end $$;
create trigger inbox_messages_alert after insert on public.inbox_messages
  for each row execute function public._inbox_alert();

-- ---------- the Kagawad's endorsement ----------

alter table public.retirement_requests
  add column endorsed_by uuid references public.users (id) on delete set null,
  add column endorsed_at timestamptz,
  add column endorse_note text check (endorse_note is null or char_length(endorse_note) <= 500);

/** May the signed-in Kagawad see this tanod's requests? The tanod is approved in their committee (0153). */
create or replace function public._kagawad_of_tanod(p_tanod uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.admin_tier() = 'committee' and exists (
    select 1 from public.tanod_committees tc
     where tc.tanod_id = p_tanod and tc.status = 'approved'
       and tc.committee = (select committee from public.users where id = auth.uid()))
$$;

-- A committee's admins saw every request (is_admin); now a Kagawad sees their committee's tanods' only, and staff none.
alter policy retirement_requests_read on public.retirement_requests using (
  tanod_id = (select auth.uid())
  or ((select public.is_admin()) and not (select public.admin_scoped()))
  or (select public._kagawad_of_tanod(tanod_id)));

/** A Kagawad endorses a pending request of their committee's tanod; the super admins are told and still decide. */
create or replace function public.endorse_retirement(p_request uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r public.retirement_requests%rowtype; v_note text := nullif(trim(coalesce(p_note, '')), ''); v_by text; v_t text;
begin
  select * into r from public.retirement_requests where id = p_request for update;
  if not found then raise exception 'No such request' using errcode = 'check_violation'; end if;
  if not public._kagawad_of_tanod(r.tanod_id) then
    raise exception 'Only the Kagawad of the tanod''s committee endorses this' using errcode = 'insufficient_privilege';
  end if;
  if r.status <> 'pending' then raise exception 'This request was already decided' using errcode = 'check_violation'; end if;
  if r.endorsed_at is not null then raise exception 'This request is already endorsed' using errcode = 'check_violation'; end if;
  update public.retirement_requests set endorsed_by = auth.uid(), endorsed_at = now(), endorse_note = left(v_note, 500) where id = p_request;
  select public.display_name(full_name) into v_by from public.users where id = auth.uid();
  select public.display_name(full_name) into v_t from public.users where id = r.tanod_id;
  insert into public.notifications (user_id, kind, message, subject_user_id)
  select u.id, 'retirement', left(format('%s endorses %s''s request to retire%s', coalesce(v_by, 'A Kagawad'), coalesce(v_t, 'a tanod'), coalesce(': ' || v_note, '.')), 500), r.tanod_id
    from public.users u where u.role = 'admin' and coalesce(u.admin_tier, 'super') = 'super' and not coalesce(u.is_suspended, false);
end $$;

-- The queue the super admins decide from (and a Kagawad reads, under the policy above) carries the endorsement.
drop function public.retirement_requests_queue();
create function public.retirement_requests_queue()
returns table (id uuid, tanod_id uuid, full_name text, email text, mobile_number text, status public.retirement_status, requested_at timestamptz,
               decided_at timestamptz, decided_by uuid, decided_by_name text, denial_reason text,
               endorsed_at timestamptz, endorsed_by_name text, endorse_note text)
language sql stable set search_path = public, extensions as $$
  select r.id, r.tanod_id, u.full_name, u.email, u.mobile_number,
         r.status, r.requested_at, r.decided_at, r.decided_by, d.full_name,
         r.denial_reason, r.endorsed_at, k.full_name, r.endorse_note
    from public.retirement_requests r
    join public.users u on u.id = r.tanod_id
    left join public.users d on d.id = r.decided_by
    left join public.users k on k.id = r.endorsed_by
   order by (r.status = 'pending') desc, r.requested_at desc
$$;
comment on function public.retirement_requests_queue() is 'Retirement Requests queue. Pending first, newest first within that; with the Kagawad''s endorsement (0157).';
revoke all on function public.retirement_requests_queue() from public, anon;
grant execute on function public.retirement_requests_queue() to authenticated, service_role;

revoke all on function public.set_my_banner(text, text, text, integer), public.endorse_retirement(uuid, text),
                       public._kagawad_of_tanod(uuid), public._inbox_alert() from public, anon;
grant execute on function public.set_my_banner(text, text, text, integer), public.endorse_retirement(uuid, text),
                          public._kagawad_of_tanod(uuid) to authenticated;
