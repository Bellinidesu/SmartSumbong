-- 0174: forgot password by email, to an address the person has confirmed (17 Nov 2026).
--
-- Residents and tanods sign in with an address made from their number (0021), which no one can receive mail at. Their profile
-- email (public.users.email) is a real one, theirs to type in Edit Profile, and until now it carried no weight. From now the
-- reset code (0085) goes to that address, sent by the password-otp function over Gmail. A typed address is not proof that the
-- person reads it, so a code only ever goes to an address that has been CONFIRMED: Edit Profile sends a one-time code to it,
-- and the right code marks it confirmed. Changing the address clears the mark, so a new address is confirmed again.
--
--   - users.email_confirmed_at: when the address on the profile was confirmed; null when there is none or it is not confirmed.
--     Only the password-otp function (the service role) sets it. A person, the portal or anyone signed in cannot, not even
--     an administrator, and any change to the email clears it.
--   - password_otps: a third purpose, 'email', for the confirming code; new_email is the address the code was sent to, so a
--     code for an address the person has since changed confirms nothing.
--
-- Nothing else changes: SMS stays as the fallback when the Semaphore secrets are set, and the hall's counter reset (0028)
-- still works for anyone with neither.

-- ---------- the confirmed mark on the profile ----------

alter table public.users
  add column if not exists email_confirmed_at timestamptz;

comment on column public.users.email_confirmed_at is
  '0174: when the profile email was confirmed with a one-time code (password-otp, email_send / email_verify). Null when there is '
  'no email or it is not confirmed. Set only by the service role; cleared whenever the email changes. Reset codes go only to a '
  'confirmed email.';

create or replace function public._email_confirmation_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Signed in (a person, the app, the portal): the mark is not theirs to write. Signed out with no claim is the service role,
  -- the sign-up trigger, the SQL editor or a migration.
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.email_confirmed_at := null;
    elsif new.email_confirmed_at is distinct from old.email_confirmed_at then
      raise exception 'An email is confirmed with the code sent to it, not set by hand.'
        using errcode = '42501';
    end if;
  end if;
  -- A different address (not just a change of case or spaces) is not confirmed until its own code comes back.
  if tg_op = 'UPDATE'
     and lower(btrim(coalesce(new.email, ''))) is distinct from lower(btrim(coalesce(old.email, ''))) then
    new.email_confirmed_at := null;
  end if;
  if new.email is null or btrim(new.email) = '' then
    new.email_confirmed_at := null;
  end if;
  return new;
end $$;

comment on function public._email_confirmation_guard() is
  '0174: only the service role marks an email confirmed; any change to the email clears the mark.';

revoke all on function public._email_confirmation_guard() from public, anon, authenticated;

drop trigger if exists users_email_confirmation on public.users;
create trigger users_email_confirmation
  before insert or update on public.users
  for each row execute function public._email_confirmation_guard();

-- ---------- the confirming code ----------

alter table public.password_otps
  add column if not exists new_email text;

alter table public.password_otps drop constraint if exists password_otps_purpose_check;
alter table public.password_otps
  add constraint password_otps_purpose_check check (purpose in ('password', 'mobile', 'email'));

comment on column public.password_otps.purpose is
  'password: forgot password (0085; by email since 0174, by SMS as the fallback). mobile: changing your own number (0104); '
  'new_mobile is the number the code was sent to. email: confirming the profile email (0174); new_email is the address the '
  'code was sent to.';

comment on column public.password_otps.new_email is
  '0174: for purpose email, the address the confirming code went to. The code confirms nothing once the profile email differs.';
