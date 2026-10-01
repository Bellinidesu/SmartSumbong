-- 0075 — Attendance history (2 Oct 2026).
--
-- public.attendance has existed since 0001 but nothing ever wrote to it:
-- the tanod app only overwrites users.duty_status (tanod/duty.dart), so
-- there was no shift history. Without one, the portal's tanod page cannot
-- draw "Today's shift" and Report Summary's Tanod Attendance Rate is
-- always "—".
--
-- This logs every change of a tanod's duty status into attendance, from
-- the database itself, so the app needs no update. No table or column is
-- added; the ERD is unchanged. History starts now — earlier shifts were
-- never stored and cannot be recovered.

create or replace function public.log_duty_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only an actual change, only for a tanod, never a null status.
  if new.role = 'tanod'
     and new.duty_status is not null
     and new.duty_status is distinct from old.duty_status then
    insert into public.attendance (tanod_id, duty_status)
    values (new.id, new.duty_status);
  end if;
  return new;
end $$;

revoke all on function public.log_duty_change() from public, anon, authenticated;

drop trigger if exists users_log_duty_change on public.users;
create trigger users_log_duty_change
  after update of duty_status on public.users
  for each row execute function public.log_duty_change();

-- Start today's history with where every tanod is right now, so the
-- first shift bar is not empty until someone next changes status.
insert into public.attendance (tanod_id, duty_status)
select id, duty_status
  from public.users
 where role = 'tanod' and duty_status is not null;
