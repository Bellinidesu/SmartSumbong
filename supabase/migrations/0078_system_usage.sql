-- 0078 — Plan and usage figures for the portal's Settings page (3 Oct 2026).
--
-- Settings > Plan and usage shows how close the barangay is to the
-- Supabase plan's limits. Three of those figures live in the database
-- itself and can't be read through the REST API: the database's size,
-- the files in Storage, and how many people signed in this month. This
-- returns them, to admins only. Nothing is stored and no table is added.

create or replace function public.system_usage()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  month_start timestamptz := date_trunc('month', now() at time zone 'Asia/Manila') at time zone 'Asia/Manila';
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  return json_build_object(
    'db_bytes',      pg_database_size(current_database()),
    'storage_bytes', coalesce((select sum((metadata->>'size')::bigint) from storage.objects), 0),
    'active_users',  (select count(*) from auth.users where last_sign_in_at >= month_start),
    'month_start',   month_start
  );
end $$;

revoke all on function public.system_usage() from public, anon;
grant execute on function public.system_usage() to authenticated;
