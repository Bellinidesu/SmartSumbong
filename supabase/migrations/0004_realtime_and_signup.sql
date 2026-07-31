-- =============================================================
-- SmartSumbong — 0004 Signup bridge + Realtime
--
-- Two things the schema needed before any client could talk to it:
--   1. Nothing created a public.users row when someone signed up.
--      auth.users and public.users were joined by a foreign key and
--      by nothing else, so every registration produced a credential
--      with no profile attached to it.
--   2. reports was not in a publication, so Realtime emitted nothing
--      and the live admin map had no source of events.
-- =============================================================

-- ---------- signup bridge ------------------------------------
-- Supabase Auth owns auth.users. The client passes profile fields as
-- user metadata at signup; this copies them across into the row the
-- barangay actually cares about, in the same transaction.
--
-- Registration lands as 'pending' with no duty status. Verification is
-- the admin's job (Verify User Account UC) and cannot be self-asserted
-- from client-supplied metadata.

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_full_name text := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');
  v_mobile    text := nullif(trim(new.raw_user_meta_data ->> 'mobile_number'), '');
  v_role      text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'role'), ''), 'resident');
begin
  if v_full_name is null then
    raise exception 'full_name is required at signup';
  end if;
  if v_mobile is null then
    raise exception 'mobile_number is required at signup';
  end if;
  -- An account cannot register itself as staff. Admin promotes later.
  if v_role not in ('resident', 'tanod') then
    raise exception 'role must be resident or tanod at signup';
  end if;

  insert into public.users (
    id, full_name, email, mobile_number, role,
    id_image_url, verification_status, verification_submitted_at
  )
  values (
    new.id, v_full_name, new.email, v_mobile, v_role::user_role,
    nullif(trim(new.raw_user_meta_data ->> 'id_image_url'), ''),
    'pending', now()
  );

  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------- realtime -----------------------------------------
-- Realtime respects RLS: a subscriber only receives rows their policies
-- already let them SELECT. The admin map sees everything because
-- reports_resident_read grants admins full read, not because the
-- channel is open.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table public.reports;
alter publication supabase_realtime add table public.dispatches;
alter publication supabase_realtime add table public.status_logs;

-- UPDATE and DELETE events carry only the primary key unless the table
-- publishes full rows. The map needs the old status to move a pin
-- between layers, so reports publishes everything.
alter table public.reports replica identity full;
