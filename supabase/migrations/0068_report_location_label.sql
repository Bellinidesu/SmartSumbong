-- 0068 — a street address on each complaint (branch B, 26 Sep 2026).
--
-- A complaint has always been exact coordinates only. The resident app
-- already looked the nearest street up from OpenStreetMap (Nominatim) to
-- label its own list, but kept it on the phone. Admins and tanods read
-- places, not coordinates — "near 12th St, Villamor" — so the label is
-- now stored once, where every screen can show it.
--
-- It is an approximation nobody typed, never a replacement for the
-- coordinates: the column is a display label, set once and not edited.
-- Written by the resident's app right after filing, or, for older
-- complaints and any the app could not label, by the portal on its first
-- look (both through set_report_location_label below).

alter table public.reports
  add column if not exists location_label text
    check (location_label is null or char_length(location_label) between 1 and 160);

comment on column public.reports.location_label is
  'Nearest street/place from OpenStreetMap reverse geocoding (0068). Display only; '
  'latitude/longitude stay the record.';

-- Set once. The filing resident may label their own complaint, and an
-- admin may label any; a label already set is left alone, so this can be
-- called freely by whichever screen gets there first.
create or replace function public.set_report_location_label(p_report uuid, p_label text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_label text := nullif(btrim(left(coalesce(p_label, ''), 160)), '');
begin
  if v_label is null then
    return false;
  end if;

  select resident_id into v_owner from public.reports where id = p_report;
  if not found then
    return false;
  end if;
  if v_owner is distinct from auth.uid() and coalesce(public.my_role()::text, '') <> 'admin' then
    raise exception 'not_allowed';
  end if;

  update public.reports
     set location_label = v_label
   where id = p_report
     and location_label is null;
  return found;
end $$;

revoke execute on function public.set_report_location_label(uuid, text) from public, anon;
grant  execute on function public.set_report_location_label(uuid, text) to authenticated;
