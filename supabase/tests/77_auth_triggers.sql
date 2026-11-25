-- auth_triggers (round 3, 25 Nov 2026; guards 0004/0022 and the 0193 draft). Rolled back (ends by raising SWEEP-ROLLBACK).
-- On 23-24 Nov live had lost both auth.users triggers and new residents could not register or sign in; nothing in public had
-- changed, so no other check noticed. This one fails if either trigger is missing, disabled, at the wrong timing or calls the
-- wrong function, and proves what they are for: a phone sign-up gets its users row and a confirmed derived address.
do $sweep$
declare
  v_log text := 'setup ok';
  v_res uuid := gen_random_uuid(); v_adm uuid := gen_random_uuid(); n integer;
begin
  begin
    select count(*) into n from pg_trigger t join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal and t.tgenabled = 'O' and (
           (t.tgname = 'on_auth_user_created' and p.proname = 'handle_new_auth_user' and pg_get_triggerdef(t.oid) like '%AFTER INSERT ON auth.users FOR EACH ROW%')
        or (t.tgname = 'auth_users_confirm_synthetic' and p.proname = 'confirm_synthetic_auth_email' and pg_get_triggerdef(t.oid) like '%BEFORE INSERT ON auth.users FOR EACH ROW%'));
    if n <> 2 then raise exception 'expected both auth.users triggers (after insert -> handle_new_auth_user, before insert -> confirm_synthetic_auth_email), found %', n; end if;
    v_log := v_log || E'\n' || 'ok  both auth.users triggers exist, enabled, with the right timing and function';
  exception when others then v_log := v_log || E'\n' || 'FAIL both auth.users triggers exist, enabled, with the right timing and function: ' || sqlerrm; end;

  begin
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_res, 'authenticated', 'authenticated', public.auth_email_for('+639999999977'),
            jsonb_build_object('full_name', 'Trigger, Resident', 'mobile_number', '+639999999977', 'role', 'resident', 'id_type', 'barangay_id',
                               'id_image_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/ids/' || gen_random_uuid() || '.jpg',
                               'selfie_url', 'https://res.cloudinary.com/nwb2kryl/image/upload/v1/selfies/' || gen_random_uuid() || '.jpg'), now(), now());
    if not exists (select 1 from public.users where id = v_res) then raise exception 'a phone sign-up got no public.users row'; end if;
    if (select email_confirmed_at from auth.users where id = v_res) is null then raise exception 'the derived address was left unconfirmed (the resident could never sign in)'; end if;
    v_log := v_log || E'\n' || 'ok  a phone sign-up gets its users row and a confirmed derived address';
  exception when others then v_log := v_log || E'\n' || 'FAIL a phone sign-up gets its users row and a confirmed derived address: ' || sqlerrm; end;

  begin
    perform set_config('smartsumbong.provisioning_admin', 'on', true);   -- a real address comes only from admin provisioning
    insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_adm, 'authenticated', 'authenticated', 'trigger.check@example.com',
            jsonb_build_object('full_name', 'Trigger, Real Address'), now(), now());
    perform set_config('smartsumbong.provisioning_admin', 'off', true);
    if (select email_confirmed_at from auth.users where id = v_adm) is not null then raise exception 'a real address was confirmed without its mail'; end if;
    v_log := v_log || E'\n' || 'ok  an account with a real address still goes through normal confirmation';
  exception when others then v_log := v_log || E'\n' || 'FAIL an account with a real address still goes through normal confirmation: ' || sqlerrm; end;

  raise exception E'SWEEP-ROLLBACK\n%', v_log;
end $sweep$;
