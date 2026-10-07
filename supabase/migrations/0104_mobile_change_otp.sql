-- SmartSumbong — change your own mobile number with an SMS code (Rose, 7 Oct 2026).
--
-- A resident or tanod changing their number used to ask the barangay to
-- approve it. It is their own number, so they prove it instead: a code goes
-- to the new number and entering it makes the change (password-otp, actions
-- mobile_send / mobile_verify). The codes share password_otps, told apart by
-- purpose; the number being moved to rides along with its code.
--
-- The app keeps the barangay request while SMS is switched off
-- (kSmsResetEnabled), so nothing changes until Semaphore has credits.

alter table public.password_otps
  add column if not exists purpose    text not null default 'password',
  add column if not exists new_mobile text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'password_otps_purpose_check') then
    alter table public.password_otps
      add constraint password_otps_purpose_check check (purpose in ('password', 'mobile'));
  end if;
end $$;

comment on column public.password_otps.purpose is
  'password: forgot password (0085). mobile: changing your own number (0104); new_mobile is the number the code was sent to.';
