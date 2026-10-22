-- =============================================================
-- SmartSumbong — 0141 SMART's rules: versions, rollback, replay (Iteration 3)
--
-- The rules that score every report live in one row (smart_rules) and a word
-- list (smart_lexicon). Until now a change left no trace: who, when, why, and
-- what the rules were before. And the only way to see what a change would do
-- was to make it.
--
--   1. Versions. Every change to the rules or the word list is saved as a
--      numbered snapshot with who, when and why (smart_rule_versions), by
--      triggers, whoever makes the change. Switches that are not scoring
--      rules (storm mode, the digest) are not versions.
--   2. Each score remembers the version that produced it
--      (report_triage.rules_version). An administrator's override does not
--      re-stamp it.
--   3. smart_save_rules(changes, reason): the one way the portal changes rules,
--      only the keys given, with the reason recorded.
--   4. smart_rollback(version, reason): restores a version's rules and word
--      list as one new version, then re-scores the open reports.
--   5. smart_replay(changes, days, limit): scores recent reports under the
--      proposed rules and under the current ones, inside a block that always
--      rolls back, and says what would move. Nothing is saved, ever.
-- =============================================================

set search_path = public, extensions;

create table public.smart_rule_versions (
  version    integer generated always as identity primary key,
  created_at timestamptz not null default clock_timestamp(),
  changed_by uuid references public.users (id) on delete set null,
  reason     text not null check (char_length(reason) between 1 and 300),
  rules      jsonb not null,
  lexicon    jsonb not null
);
alter table public.smart_rule_versions enable row level security;
create policy smart_rule_versions_admin_read on public.smart_rule_versions for select using ((select public.is_admin()));
comment on table public.smart_rule_versions is
  '0141: every version of SMART''s scoring rules and word list, with who, when and why. Written only by the triggers and smart_rollback().';

-- The parts of smart_rules that are switches or bookkeeping, not rules: a change to only these is not a version.
create or replace function public._smart_rules_snapshot(p jsonb)
returns jsonb
language sql immutable set search_path = public as $$
  select p - 'id' - 'updated_at' - 'updated_by' - 'storm_mode' - 'storm_until' - 'storm_reason' - 'digest_enabled';
$$;

create or replace function public._smart_lexicon_snapshot()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(l) order by l.variant), '[]') from public.smart_lexicon l;
$$;

create or replace function public._smart_new_version(p_default_reason text)
returns integer
language plpgsql security definer set search_path = public as $$
declare v integer; v_reason text;
begin
  v_reason := coalesce(nullif(current_setting('smartsumbong.rules_reason', true), ''), p_default_reason);
  insert into public.smart_rule_versions (changed_by, reason, rules, lexicon)
  select auth.uid(), left(v_reason, 300), public._smart_rules_snapshot(to_jsonb(k)), public._smart_lexicon_snapshot()
    from public.smart_rules k where k.id = 1
  returning version into v;
  perform public._smart_event('rules_changed', null, format('SMART rules version %s: %s', v, left(v_reason, 200)), jsonb_build_object('version', v));
  return v;
end $$;

create or replace function public._smart_rules_versioned()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('smartsumbong.rules_batch', true) = 'on' then return null; end if;   -- a rollback writes one version itself
  if public._smart_rules_snapshot(to_jsonb(new)) is distinct from public._smart_rules_snapshot(to_jsonb(old)) then
    perform public._smart_new_version('Rules changed');
  end if;
  return null;
end $$;

create or replace function public._smart_lexicon_versioned()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('smartsumbong.rules_batch', true) = 'on' then return null; end if;
  perform public._smart_new_version('Word list changed');
  return null;
end $$;

create trigger smart_rules_versioned after update on public.smart_rules
  for each row execute function public._smart_rules_versioned();
create trigger smart_lexicon_versioned after insert or update or delete on public.smart_lexicon
  for each statement execute function public._smart_lexicon_versioned();

revoke all on function public._smart_rules_snapshot(jsonb), public._smart_lexicon_snapshot(), public._smart_new_version(text),
  public._smart_rules_versioned(), public._smart_lexicon_versioned() from public, anon, authenticated;

-- The rules as they are now are version 1.
select set_config('smartsumbong.rules_reason', 'The rules as they were when versions began (0141)', true);
select public._smart_new_version('The rules as they were when versions began (0141)');
select set_config('smartsumbong.rules_reason', '', true);

-- ---------- each score remembers its version ---------------------------

alter table public.report_triage add column if not exists rules_version integer references public.smart_rule_versions (version);
comment on column public.report_triage.rules_version is
  '0141: the version of SMART''s rules that produced this score. Null: scored before versions began. Re-stamped only when the report is scored again, not by an override.';

create or replace function public._triage_rules_version()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.computed_at is distinct from old.computed_at then
    new.rules_version := (select max(version) from public.smart_rule_versions);
  end if;
  return new;
end $$;
create trigger report_triage_rules_version before insert or update on public.report_triage
  for each row execute function public._triage_rules_version();

-- ---------- changing the rules, with a reason --------------------------

-- The keys an administrator may change. Not id or the bookkeeping, and not storm mode or the digest, which have
-- their own controls.
create or replace function public._smart_rule_keys()
returns text[]
language sql stable set search_path = public as $$
  select array_agg(column_name::text) from information_schema.columns
   where table_schema = 'public' and table_name = 'smart_rules'
     and column_name not in ('id', 'updated_at', 'updated_by', 'storm_mode', 'storm_until', 'storm_reason', 'digest_enabled');
$$;

-- Writes the given keys of p_changes into the rules row. Every key must be a rule.
create or replace function public._smart_apply_rules(p_changes jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_keys text[];
  v_bad  text;
  v_cols text;
begin
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' or p_changes = '{}' then
    raise exception 'Say which rules to change' using errcode = 'check_violation';
  end if;
  select array_agg(k) into v_keys from jsonb_object_keys(p_changes) k;
  select string_agg(k, ', ') into v_bad from unnest(v_keys) k where k <> all (public._smart_rule_keys());
  if v_bad is not null then raise exception 'Not a rule that can be changed here: %', v_bad using errcode = 'check_violation'; end if;
  select string_agg(quote_ident(k), ', ') into v_cols from unnest(v_keys) k;
  execute format('update public.smart_rules set (%1$s) = (select %1$s from jsonb_populate_record(null::public.smart_rules, $1)) where id = 1', v_cols)
    using p_changes;
end $$;
revoke all on function public._smart_rule_keys(), public._smart_apply_rules(jsonb) from public, anon, authenticated;

create or replace function public.smart_save_rules(p_changes jsonb, p_reason text)
returns integer
language plpgsql security definer set search_path = public as $$
declare v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if v_reason is null then raise exception 'Say why the rules are changing' using errcode = 'check_violation'; end if;
  perform set_config('smartsumbong.rules_reason', left(v_reason, 300), true);
  perform public._smart_apply_rules(p_changes);
  update public.smart_rules set updated_at = now(), updated_by = auth.uid() where id = 1;
  perform set_config('smartsumbong.rules_reason', '', true);
  return (select max(version) from public.smart_rule_versions);
end $$;

-- ---------- rolling back --------------------------------------------------

create or replace function public.smart_rollback(p_version integer, p_reason text)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v public.smart_rule_versions%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_new integer;
  v_keys jsonb;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  if v_reason is null then raise exception 'Say why you are rolling back' using errcode = 'check_violation'; end if;
  select * into v from public.smart_rule_versions where version = p_version;
  if not found then raise exception 'No such version' using errcode = 'check_violation'; end if;

  -- one version for the whole rollback, not one per statement
  perform set_config('smartsumbong.rules_batch', 'on', true);
  -- only the keys the snapshot holds and that are still rules (a column added later keeps its current value)
  select jsonb_object_agg(e.key, e.value) into v_keys
    from jsonb_each(v.rules) e where e.key = any (public._smart_rule_keys());
  perform public._smart_apply_rules(v_keys);
  update public.smart_rules set updated_at = now(), updated_by = auth.uid() where id = 1;
  delete from public.smart_lexicon;
  insert into public.smart_lexicon select * from jsonb_populate_recordset(null::public.smart_lexicon, v.lexicon);
  perform set_config('smartsumbong.rules_batch', 'off', true);

  perform set_config('smartsumbong.rules_reason', format('Rolled back to version %s: %s', p_version, v_reason), true);
  v_new := public._smart_new_version('Rolled back');
  perform set_config('smartsumbong.rules_reason', '', true);
  perform public.smart_retriage(null);
  return v_new;
end $$;

-- ---------- the history -------------------------------------------------

create or replace function public.smart_rule_history(p_limit integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'version', h.version, 'at', h.created_at, 'reason', h.reason, 'by', u.full_name,
             'changed', coalesce((select jsonb_agg(e.key order by e.key) from jsonb_each(h.rules) e
                                   where p.rules is not null and (p.rules -> e.key) is distinct from e.value), '[]')
                        || case when p.lexicon is not null and p.lexicon is distinct from h.lexicon then '["word list"]'::jsonb else '[]' end,
             'words', jsonb_array_length(h.lexicon),
             'current', h.version = (select max(version) from public.smart_rule_versions))
           order by h.version desc)
      from (select * from public.smart_rule_versions order by version desc limit greatest(1, least(p_limit, 200))) h
      left join public.smart_rule_versions p on p.version = (select max(version) from public.smart_rule_versions x where x.version < h.version)
      left join public.users u on u.id = h.changed_by), '[]');
end $$;

-- ---------- replay: what a change would do, without making it -------------------

create or replace function public.smart_replay(p_changes jsonb, p_days integer default 90, p_limit integer default 1000)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions set jit = off as $$
declare
  v_days  integer := greatest(1, least(coalesce(p_days, 90), 365));
  v_limit integer := greatest(1, least(coalesce(p_limit, 1000), 2000));
  v_before jsonb;
  v_after  jsonb;
begin
  if not public.is_admin() then raise exception 'Administrators only' using errcode = 'insufficient_privilege'; end if;

  -- the current rules, scored the same way as the proposal (not the stored scores, which may be older rules)
  select coalesce(jsonb_object_agg(x.id, jsonb_build_object('t', x.tracking_id, 's', x.subject, 'score', x.score, 'level', x.level)), '{}')
    into v_before
    from (select r.id, r.tracking_id, r.subject, sc.score, sc.level
            from public.reports r
            cross join lateral public._smart_score(r.category, r.subject, r.description, r.geom, r.created_at, r.resident_id, r.id) sc
           where r.deleted_at is null and r.created_at > now() - make_interval(days => v_days)
           order by r.created_at desc limit v_limit) x;

  begin
    perform set_config('smartsumbong.rules_batch', 'on', true);   -- no version for a rehearsal
    perform public._smart_apply_rules(p_changes);
    select coalesce(jsonb_object_agg(x.id, jsonb_build_object('score', x.score, 'level', x.level)), '{}')
      into v_after
      from (select r.id, sc.score, sc.level
              from public.reports r
              cross join lateral public._smart_score(r.category, r.subject, r.description, r.geom, r.created_at, r.resident_id, r.id) sc
             where r.deleted_at is null and r.created_at > now() - make_interval(days => v_days)
             order by r.created_at desc limit v_limit) x;
    raise exception 'smart-replay-rollback';
  exception when others then
    if sqlerrm <> 'smart-replay-rollback' then raise; end if;   -- a real error (a bad key) goes to the caller
  end;
  perform set_config('smartsumbong.rules_batch', 'off', true);

  return jsonb_build_object(
    'days', v_days,
    'reports', (select count(*) from jsonb_object_keys(v_before)),
    'moved', (select count(*) from jsonb_each(v_before) b where (b.value ->> 'level') is distinct from (v_after -> b.key ->> 'level')),
    'transitions', coalesce((select jsonb_agg(jsonb_build_object('from', t.f, 'to', t.t, 'reports', t.n) order by t.n desc)
                               from (select b.value ->> 'level' f, v_after -> b.key ->> 'level' t, count(*) n
                                       from jsonb_each(v_before) b group by 1, 2) t), '[]'),
    -- the reports whose score would change, the biggest moves first, 50 at most
    'changed', coalesce((select jsonb_agg(c.j order by c.d desc)
                           from (select jsonb_build_object('tracking_id', b.value ->> 't', 'subject', b.value ->> 's',
                                          'score_before', (b.value ->> 'score')::int, 'score_after', (v_after -> b.key ->> 'score')::int,
                                          'level_before', b.value ->> 'level', 'level_after', v_after -> b.key ->> 'level') as j,
                                        abs((v_after -> b.key ->> 'score')::int - (b.value ->> 'score')::int) as d
                                   from jsonb_each(v_before) b
                                  where (b.value ->> 'score') is distinct from (v_after -> b.key ->> 'score')
                                  order by 2 desc limit 50) c), '[]'));
end $$;

revoke all on function public.smart_save_rules(jsonb, text), public.smart_rollback(integer, text), public.smart_rule_history(integer),
  public.smart_replay(jsonb, integer, integer) from public, anon;
grant execute on function public.smart_save_rules(jsonb, text), public.smart_rollback(integer, text), public.smart_rule_history(integer),
  public.smart_replay(jsonb, integer, integer) to authenticated;
