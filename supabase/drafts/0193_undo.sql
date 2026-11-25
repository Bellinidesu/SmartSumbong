-- UNDO of 0193_auth_triggers_idempotent: nothing to undo in practice. 0193 re-creates the two auth.users triggers exactly as
-- 0004 and 0022 made them, so the state before 0193 (with the triggers in place, as on live since Ace's repair of 24-25 Nov)
-- is the state after it. Do NOT drop the triggers to "undo": without them no new resident can register or sign in.
-- If 0193 itself failed half-way, the migration's transaction rolled it back; re-run 0193 or the two create statements below.
set search_path = public, extensions;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();
drop trigger if exists auth_users_confirm_synthetic on auth.users;
create trigger auth_users_confirm_synthetic before insert on auth.users for each row execute function public.confirm_synthetic_auth_email();
