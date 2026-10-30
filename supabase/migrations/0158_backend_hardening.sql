-- =============================================================
-- SmartSumbong — 0158 Backend hardening: retention, indexes, locks
--
-- A pass over the whole backend after the roles-and-pages build (Ace, 30 Oct
-- 2026: "everything on the side of the new backend ... complete and industry
-- standard"). What the advisors and the privacy inventory still listed:
--
--   1. Retention for what had none (docs/PRIVACY_INVENTORY.md, section 9.3).
--      The team proposed 30 days for SMS reset codes and left the rest to the
--      barangay, so each period is a setting a super admin changes in
--      Control Room > Rules, with a default:
--        SMS reset codes             30 days
--        tanod attendance            365 days
--        the punch card              365 days
--        Inbox messages              730 days
--        Workspace check-ins, removed posts   365 days
--      Reroute questions already answered are kept 180 days. The audit trail
--      (status_logs, account_audit, case_handler_log, case_forwards,
--      tanod_committee_log) is never purged: it is the barangay's record.
--      purge_old_records() runs daily at 03:30 Manila.
--   2. An index on every foreign key that had none, so a parent's delete or a
--      join on it does not read the whole child table.
--   3. Internal helpers that anonymous callers could run are closed to them.
--   4. look_shares' tanod policies read auth.uid() once per query, not per row.
--   5. forward_case and flag_case_for_forward lock the case while they work,
--      so two forwards (or two flags) sent at once cannot both pass.
-- =============================================================

set search_path = public, extensions;

-- ---------- 1. retention ----------

alter table public.operational_settings
  add column keep_otp_days smallint not null default 30 check (keep_otp_days between 1 and 90),
  add column keep_attendance_days smallint not null default 365 check (keep_attendance_days between 30 and 3650),
  add column keep_punch_days smallint not null default 365 check (keep_punch_days between 30 and 3650),
  add column keep_inbox_days smallint not null default 730 check (keep_inbox_days between 30 and 3650),
  add column keep_workspace_days smallint not null default 365 check (keep_workspace_days between 30 and 3650);
comment on column public.operational_settings.keep_otp_days is '0158: days an SMS reset code is kept after it was made (used or not).';
comment on column public.operational_settings.keep_attendance_days is '0158: days tanod attendance logs are kept.';
comment on column public.operational_settings.keep_punch_days is '0158: days punch card sign-ins and sign-outs are kept.';
comment on column public.operational_settings.keep_inbox_days is '0158: days Inbox messages are kept.';
comment on column public.operational_settings.keep_workspace_days is '0158: days Workspace shift check-ins and removed team posts are kept.';

/** Deletes what is past its retention period (operational_settings.keep_*); the audit trail is never touched. Returns the rows removed per table. */
create or replace function public.purge_old_records()
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.operational_settings%rowtype; n jsonb := '{}'::jsonb; c integer;
begin
  select * into s from public.operational_settings where id = 1;
  delete from public.password_otps where created_at < now() - make_interval(days => s.keep_otp_days);
  get diagnostics c = row_count; n := n || jsonb_build_object('password_otps', c);
  delete from public.attendance where logged_at < now() - make_interval(days => s.keep_attendance_days);
  get diagnostics c = row_count; n := n || jsonb_build_object('attendance', c);
  delete from public.admin_punches where at < now() - make_interval(days => s.keep_punch_days);
  get diagnostics c = row_count; n := n || jsonb_build_object('admin_punches', c);
  delete from public.inbox_messages where created_at < now() - make_interval(days => s.keep_inbox_days)
     and not exists (select 1 from public.reroute_questions q where q.id = inbox_messages.question_id and q.state = 'open');
  get diagnostics c = row_count; n := n || jsonb_build_object('inbox_messages', c);
  delete from public.shift_checkins where created_at < now() - make_interval(days => s.keep_workspace_days);
  get diagnostics c = row_count; n := n || jsonb_build_object('shift_checkins', c);
  delete from public.team_posts where removed_at is not null and removed_at < now() - make_interval(days => s.keep_workspace_days);
  get diagnostics c = row_count; n := n || jsonb_build_object('team_posts', c);
  delete from public.reroute_questions where state <> 'open' and asked_at < now() - interval '180 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('reroute_questions', c);
  return n;
end $$;
revoke all on function public.purge_old_records() from public, anon, authenticated;
select cron.schedule('purge-old-records', '30 19 * * *', $$select public.purge_old_records()$$);   -- 03:30 Manila

-- ---------- 2. an index on every foreign key that has none ----------

do $idx$
declare r record; v_name text;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conrelid, c.conkey,
           (select string_agg(quote_ident(a.attname), ', ' order by array_position(c.conkey, a.attnum))
              from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey)) as cols,
           (select string_agg(a.attname, '_' order by array_position(c.conkey, a.attnum))
              from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey)) as cols_name
      from pg_constraint c
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and not exists (select 1 from pg_index i where i.indrelid = c.conrelid
                         and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey)
  loop
    v_name := left((select relname from pg_class where oid = r.conrelid) || '_' || r.cols_name || '_fkey_idx', 63);
    execute format('create index if not exists %I on %s (%s)', v_name, r.tbl, r.cols);
  end loop;
end $idx$;

-- ---------- 3. internal helpers are not for anonymous callers ----------

revoke execute on function public._colour_clash(text, text), public._committee_free_colour(), public._smart_vocab() from public, anon;
grant execute on function public._colour_clash(text, text), public._committee_free_colour(), public._smart_vocab() to authenticated;

-- ---------- 4. auth.uid() once per query ----------

alter policy look_shares_tanod_read on public.look_shares using (tanod_id = (select auth.uid()));
alter policy look_shares_tanod_seen on public.look_shares using (tanod_id = (select auth.uid())) with check (tanod_id = (select auth.uid()));

-- ---------- 5. forwarding and flagging lock the case ----------

do $lock$
declare f text; d text; n text;
begin
  foreach f in array array['public.forward_case(uuid, text, text, bigint)', 'public.flag_case_for_forward(uuid, text, text)'] loop
    d := pg_get_functiondef(f::regprocedure);
    n := replace(d, 'select * into r from public.reports where id = p_report and deleted_at is null;',
                    'select * into r from public.reports where id = p_report and deleted_at is null for update;');
    if n = d then raise exception '0158: the case lookup in % was not found', f; end if;
    execute n;
  end loop;
end $lock$;
