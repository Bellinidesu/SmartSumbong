-- 0097 — Error tracking (industry pass 6, 7 Oct 2026).
--
-- PHP failures and browser errors on the portal used to end up only in
-- Render's logs (or nowhere, for the browser). Now both are recorded here,
-- grouped by message so a repeating error is one row with a count, and
-- the newest show in Settings → System status. Writing goes through
-- log_portal_error() only — callable without signing in (a crash can happen
-- on the login page), so it trims everything and keeps at most 500 rows.

create table if not exists public.portal_errors (
  id          bigint generated always as identity primary key,
  source      text not null check (source in ('server', 'browser')),
  page        text not null,
  message     text not null,
  detail      text,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  count       int not null default 1,
  signature   text not null unique
);
create index if not exists portal_errors_last_seen_idx on public.portal_errors (last_seen desc);
alter table public.portal_errors enable row level security;
create policy portal_errors_admin_read on public.portal_errors for select using ((select public.is_admin()));

create or replace function public.log_portal_error(p_source text, p_page text, p_message text, p_detail text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_page text := left(coalesce(nullif(trim(p_page), ''), '?'), 200);
  v_msg  text := left(coalesce(nullif(trim(p_message), ''), '(no message)'), 500);
  v_sig  text;
begin
  if p_source not in ('server', 'browser') then return; end if;
  v_sig := md5(p_source || '|' || v_page || '|' || v_msg);
  insert into public.portal_errors (source, page, message, detail, signature)
  values (p_source, v_page, v_msg, left(p_detail, 2000), v_sig)
  on conflict (signature) do update
     set count = portal_errors.count + 1, last_seen = now(),
         detail = coalesce(excluded.detail, portal_errors.detail);
  -- Keep the table small: the 500 most recently seen.
  delete from public.portal_errors where id in (
    select id from public.portal_errors order by last_seen desc offset 500);
end $$;
revoke all on function public.log_portal_error(text, text, text, text) from public;
grant execute on function public.log_portal_error(text, text, text, text) to anon, authenticated;
