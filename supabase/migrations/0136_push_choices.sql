-- =============================================================
-- SmartSumbong — 0136 Alerts each person sets up, and browser alerts
--
-- Ace (22 Oct 2026): "it should be modular for everyone and anyone can
-- set up what they want to receive". So the choices are per person and
-- apply to every channel a push goes out on, the phone app (FCM, 0035)
-- and now the browser (Web Push, for the portal):
--
--   - which kinds: users.muted_notification_kinds, as since 0044;
--   - which cases: every case they are told about, or only their own
--     (cases they handle, were dispatched to, or reported);
--   - quiet hours, Manila time, with urgent cases let through or not;
--   - which browsers: web_push_subscriptions, one row per browser.
--
-- As in 0044, the choices only ever hold back the push. The row in
-- notifications, the inbox, is never touched.
--
-- push_plan() is the one place the choices are read. send-dispatch-push
-- calls it for each new notification and sends to what it returns.
-- =============================================================

set search_path = public, extensions;

alter type notification_kind add value if not exists 'test';

alter table public.users
  add column if not exists push_scope text not null default 'all' check (push_scope in ('all', 'mine')),
  add column if not exists push_quiet_from smallint check (push_quiet_from between 0 and 23),
  add column if not exists push_quiet_to smallint check (push_quiet_to between 0 and 23),
  add column if not exists push_quiet_urgent boolean not null default true;

comment on column public.users.push_scope is
  '0136: all = a push for every notification; mine = only for cases this person handles, was dispatched to, or reported.';
comment on column public.users.push_quiet_from is
  '0136: quiet hours start (hour, Manila), null = no quiet hours. With push_quiet_to; may wrap past midnight.';
comment on column public.users.push_quiet_urgent is
  '0136: during quiet hours, still push for a case rated urgent (SMART''s level, or an administrator''s override).';

-- ---------- browsers ----------------------------------------

create table public.web_push_subscriptions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.users (id) on delete cascade,
  -- only the browsers' own push services: the server posts to this address, so it cannot be just any URL
  endpoint    text not null unique check (char_length(endpoint) <= 1000 and endpoint ~
                '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)/'),
  p256dh      text not null check (p256dh ~ '^[A-Za-z0-9_-]{80,100}$'),
  auth        text not null check (auth ~ '^[A-Za-z0-9_-]{16,32}$'),
  label       text check (char_length(label) <= 80),
  created_at  timestamptz not null default now(),
  last_ok_at  timestamptz,
  failures    smallint not null default 0
);
create index web_push_subscriptions_user_idx on public.web_push_subscriptions (user_id);

alter table public.web_push_subscriptions enable row level security;
-- Read and remove your own; adding goes through web_push_subscribe(), which pins the owner.
create policy web_push_own_read on public.web_push_subscriptions
  for select using (user_id = (select auth.uid()));
create policy web_push_own_delete on public.web_push_subscriptions
  for delete using (user_id = (select auth.uid()));

comment on table public.web_push_subscriptions is
  '0136: one row per browser that turned alerts on. The endpoint belongs to whoever last signed in on that browser.';

create or replace function public.web_push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_label text default null)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  insert into public.web_push_subscriptions (user_id, endpoint, p256dh, auth, label)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(p_label, 80))
  on conflict (endpoint) do update
    set user_id = v_uid, p256dh = excluded.p256dh, auth = excluded.auth, label = excluded.label,
        failures = 0, created_at = now()
  returning id into v_id;
  -- ten browsers each is plenty; the oldest go first
  delete from public.web_push_subscriptions
   where user_id = v_uid
     and id not in (select id from public.web_push_subscriptions where user_id = v_uid order by created_at desc limit 10);
  return v_id;
end $$;

create or replace function public.web_push_unsubscribe(p_endpoint text)
returns void
language sql security definer set search_path = public, extensions as $$
  delete from public.web_push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- ---------- choices ------------------------------------------

create or replace function public.set_push_choices(p_scope text, p_quiet_from smallint, p_quiet_to smallint, p_quiet_urgent boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_scope not in ('all', 'mine') then raise exception 'Scope is all or mine'; end if;
  if (p_quiet_from is null) <> (p_quiet_to is null) then raise exception 'Quiet hours need a start and an end'; end if;
  if p_quiet_from = p_quiet_to then raise exception 'Quiet hours cannot start and end at the same hour'; end if;
  update public.users
     set push_scope = p_scope, push_quiet_from = p_quiet_from, push_quiet_to = p_quiet_to,
         push_quiet_urgent = coalesce(p_quiet_urgent, true)
   where id = auth.uid();
end $$;

-- A test alert to your own phones and browsers, past every choice. The row is
-- read at once and send-dispatch-push removes it after sending, so the inbox
-- never keeps it. One a minute.
create or replace function public.push_test()
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from public.notifications where user_id = v_uid and kind = 'test' and created_at > now() - interval '1 minute') then
    raise exception 'One test a minute';
  end if;
  insert into public.notifications (user_id, kind, message, is_read)
  values (v_uid, 'test', 'Alerts work here. This is how a SmartSumbong alert looks.', true);
end $$;

-- ---------- the plan for one notification ------------------------

create or replace function public.push_plan(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
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
  elsif u.push_quiet_from is not null
        and (case when u.push_quiet_from < u.push_quiet_to then v_hour >= u.push_quiet_from and v_hour < u.push_quiet_to
                  else v_hour >= u.push_quiet_from or v_hour < u.push_quiet_to end)
        and not (u.push_quiet_urgent and v_urgent) then
    v_why := 'quiet hours';
  end if;

  return jsonb_build_object(
    'send', v_why is null,
    'why', v_why,
    'record', jsonb_build_object('id', n.id, 'user_id', n.user_id, 'report_id', n.report_id, 'kind', n.kind, 'message', n.message),
    'tracking_id', (select r.tracking_id from public.reports r where r.id = n.report_id),
    'urgent', v_urgent,
    'tokens', coalesce((select jsonb_agg(t.fcm_token) from public.device_tokens t where t.user_id = n.user_id), '[]'),
    'web', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'endpoint', w.endpoint, 'p256dh', w.p256dh, 'auth', w.auth))
                       from public.web_push_subscriptions w where w.user_id = n.user_id), '[]'));
end $$;

revoke execute on function public.push_plan(uuid) from public, anon, authenticated;
grant execute on function public.push_plan(uuid) to service_role;
revoke execute on function public.web_push_subscribe(text, text, text, text) from public, anon;
revoke execute on function public.web_push_unsubscribe(text) from public, anon;
revoke execute on function public.set_push_choices(text, smallint, smallint, boolean) from public, anon;
revoke execute on function public.push_test() from public, anon;
grant execute on function public.web_push_subscribe(text, text, text, text) to authenticated;
grant execute on function public.web_push_unsubscribe(text) to authenticated;
grant execute on function public.set_push_choices(text, smallint, smallint, boolean) to authenticated;
grant execute on function public.push_test() to authenticated;

comment on function public.push_plan(uuid) is
  '0136: for one notification, whether its owner''s choices let a push through (send, why) and where to: phone tokens and browsers. Service role only; send-dispatch-push calls it.';
