-- 0109: signed media uploads (backend review, 10 Oct 2026).
--
-- Until now every photo and video went to Cloudinary through an unsigned
-- preset whose name ships inside the APK, so anyone could fill the
-- barangay's Cloudinary quota from a script. The sign-upload Edge Function
-- now signs each upload, choosing the file name, size and format itself,
-- for whoever is entitled to that folder. The one opening left is the
-- registration ID and selfie, uploaded before any account exists; those
-- signatures are rationed per network address through take_rate_slot().
-- Once every phone runs an app that asks for signatures, the unsigned
-- presets can be deleted in Cloudinary (see docs/OPERATIONS.md).

create table if not exists public.rate_limit_hits (
  bucket        text primary key,
  window_start  timestamptz not null default now(),
  hits          integer not null default 0
);

comment on table public.rate_limit_hits is
  '0109: fixed-window counters for Edge Functions (take_rate_slot). '
  'A bucket names what is limited and for whom, e.g. upload-ids:<address>.';

alter table public.rate_limit_hits enable row level security;
-- No policies: only take_rate_slot() touches it.

create or replace function public.take_rate_slot(
  p_bucket text, p_max integer, p_window interval)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now  timestamptz := now();
  v_hits integer;
begin
  insert into public.rate_limit_hits as r (bucket, window_start, hits)
  values (p_bucket, v_now, 1)
  on conflict (bucket) do update
     set hits = case when r.window_start < v_now - p_window then 1 else r.hits + 1 end,
         window_start = case when r.window_start < v_now - p_window then v_now else r.window_start end
  returning hits into v_hits;

  if v_hits = 1 then
    delete from public.rate_limit_hits where window_start < v_now - interval '1 day';
  end if;
  return v_hits <= p_max;
end $$;

comment on function public.take_rate_slot(text, integer, interval) is
  '0109: true while bucket has had at most p_max calls in the current '
  'p_window. Edge Functions only (service role).';

revoke all on function public.take_rate_slot(text, integer, interval) from public, anon, authenticated;
grant execute on function public.take_rate_slot(text, integer, interval) to service_role;
