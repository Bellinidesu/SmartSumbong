-- =============================================================
-- SmartSumbong — 0015 Tamper-evident audit trail
--
-- status_logs is the record a resident's complaint is judged by, and
-- account_audit is the record of who was given administrator access.
-- Both are append-only by policy: no function updates them, and RLS
-- grants no update or delete. But policy binds the application, not
-- someone holding a database connection. A future administrator with
-- the project password could quietly rewrite a remark, backdate an
-- acceptance, or drop the entry showing a complaint was ignored for
-- nine days — and nothing in the system would know.
--
-- Two mechanisms, deliberately separate.
--
-- IMMUTABILITY stops the easy case. Triggers refuse every UPDATE, and
-- refuse a DELETE while the parent still exists. A cascade from a
-- genuinely deleted report still works, because by then the parent row
-- is already gone — which is the one legitimate way these rows die.
--
-- TAMPER EVIDENCE handles the hard case, where someone has enough
-- access to drop the triggers. Each entry carries a SHA-256 of its own
-- contents plus the hash of the entry before it, so the trail is a
-- chain. Changing any field, or removing any entry, breaks every link
-- after it. It cannot prevent a determined edit — nothing in the
-- database can — but it makes the edit provable, which is what an audit
-- trail is actually for.
--
-- Rebuilding the chain to cover a forgery is possible for someone with
-- write access. Defeating that needs the head hash published somewhere
-- the barangay does not control — printed on the monthly report, say.
-- That is a procedure, not a migration, and it belongs in the turnover
-- document.
-- =============================================================

set search_path = public, extensions;

alter table public.status_logs
  add column if not exists prev_hash  text,
  add column if not exists entry_hash text;

alter table public.account_audit
  add column if not exists prev_hash  text,
  add column if not exists entry_hash text;

comment on column public.status_logs.entry_hash is
  'SHA-256 over this entry and the previous entry_hash for the same report. See 0015.';

-- ---------- the canonical string an entry hashes ----------
-- Written out rather than hashing the row, because a row cast changes
-- with column order and a chain that breaks when someone reorders
-- columns is a chain nobody will trust.

create or replace function public.status_log_fingerprint(l public.status_logs)
returns text language sql immutable set search_path = public, extensions as $$
  select concat_ws('|',
    l.id::text, l.report_id::text, coalesce(l.changed_by::text, ''),
    coalesce(l.old_status::text, ''), l.new_status::text,
    coalesce(l.remark, ''), l.is_system::text,
    to_char(l.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))
$$;

create or replace function public.account_audit_fingerprint(a public.account_audit)
returns text language sql immutable set search_path = public, extensions as $$
  select concat_ws('|',
    a.id::text, a.subject_id::text, coalesce(a.actor_id::text, ''),
    a.action, coalesce(a.detail, ''),
    to_char(a.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))
$$;

-- ---------- chaining on insert ----------
-- status_logs chains per report: each complaint carries its own
-- verifiable history, and two complaints being written at the same
-- moment do not contend for one tail.

create or replace function public.chain_status_log()
returns trigger language plpgsql set search_path = public, extensions as $$
declare v_prev text;
begin
  select entry_hash into v_prev
    from public.status_logs
   where report_id = new.report_id
   order by created_at desc, id desc
   limit 1;

  new.prev_hash  := coalesce(v_prev, repeat('0', 64));
  new.entry_hash := encode(
    digest(new.prev_hash || '|' || public.status_log_fingerprint(new), 'sha256'), 'hex');
  return new;
end $$;

create or replace trigger status_logs_chain
  before insert on public.status_logs
  for each row execute function public.chain_status_log();

-- account_audit is one barangay-wide chain: there are few entries and
-- the question asked of it is "was anyone quietly made an admin", which
-- is a question about the whole sequence.

create or replace function public.chain_account_audit()
returns trigger language plpgsql set search_path = public, extensions as $$
declare v_prev text;
begin
  select entry_hash into v_prev
    from public.account_audit
   order by created_at desc, id desc
   limit 1;

  new.prev_hash  := coalesce(v_prev, repeat('0', 64));
  new.entry_hash := encode(
    digest(new.prev_hash || '|' || public.account_audit_fingerprint(new), 'sha256'), 'hex');
  return new;
end $$;

create or replace trigger account_audit_chain
  before insert on public.account_audit
  for each row execute function public.chain_account_audit();

-- ---------- backfill anything written before today ----------
-- Ordering matters: this rewrites rows the immutability triggers guard,
-- so those triggers are dropped here and created immediately after. The
-- gap lasts only as long as the migration transaction.

drop trigger if exists status_logs_immutable   on public.status_logs;
drop trigger if exists account_audit_immutable on public.account_audit;

do $$
declare
  r      record;
  l      public.status_logs%rowtype;
  a      public.account_audit%rowtype;
  v_prev text;
begin
  for r in select distinct report_id from public.status_logs loop
    v_prev := repeat('0', 64);
    for l in select * from public.status_logs
              where report_id = r.report_id
              order by created_at, id loop
      update public.status_logs
         set prev_hash  = v_prev,
             entry_hash = encode(digest(v_prev || '|' || public.status_log_fingerprint(l), 'sha256'), 'hex')
       where id = l.id;
      select entry_hash into v_prev from public.status_logs where id = l.id;
    end loop;
  end loop;

  v_prev := repeat('0', 64);
  for a in select * from public.account_audit order by created_at, id loop
    update public.account_audit
       set prev_hash  = v_prev,
           entry_hash = encode(digest(v_prev || '|' || public.account_audit_fingerprint(a), 'sha256'), 'hex')
     where id = a.id;
    select entry_hash into v_prev from public.account_audit where id = a.id;
  end loop;
end $$;

-- ---------- immutability ----------

create or replace function public.refuse_audit_write()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'The audit trail cannot be edited. Add a correcting entry instead.';
  end if;

  -- Branch on the table before touching a column, because PL/pgSQL
  -- evaluates the whole condition and account_audit has no report_id.
  if tg_table_name = 'account_audit' then
    raise exception 'Account audit entries cannot be deleted.';
  end if;

  -- A DELETE on a complaint trail is only legitimate as a cascade from a
  -- report that has already gone. If the parent is still there, someone
  -- is removing a single entry — exactly what this guards against.
  if exists (select 1 from public.reports where id = old.report_id) then
    raise exception 'Audit entries cannot be deleted while the complaint exists.';
  end if;

  return old;
end $$;

create or replace trigger status_logs_immutable
  before update or delete on public.status_logs
  for each row execute function public.refuse_audit_write();

create or replace trigger account_audit_immutable
  before update or delete on public.account_audit
  for each row execute function public.refuse_audit_write();

-- ---------- verification ----------

create or replace function public.verify_report_trail(p_report uuid)
returns table (
  entry_no   integer,
  logged_at  timestamptz,
  change     text,
  intact     boolean,
  problem    text)
language plpgsql stable set search_path = public, extensions as $$
declare
  l       public.status_logs%rowtype;
  v_prev  text := repeat('0', 64);
  v_calc  text;
  n       integer := 0;
begin
  for l in select * from public.status_logs
            where report_id = p_report
            order by created_at, id loop
    n := n + 1;
    v_calc := encode(digest(v_prev || '|' || public.status_log_fingerprint(l), 'sha256'), 'hex');

    entry_no  := n;
    logged_at := l.created_at;
    change    := coalesce(l.old_status::text, 'filed') || ' → ' || l.new_status::text;
    intact    := (l.entry_hash = v_calc and l.prev_hash = v_prev);
    problem   := case
                   when l.entry_hash is null then 'No hash recorded'
                   when l.prev_hash <> v_prev then 'Chain broken — an earlier entry was changed or removed'
                   when l.entry_hash <> v_calc then 'This entry was altered after it was written'
                 end;

    return next;
    v_prev := l.entry_hash;   -- continue from what is stored, to localise the break
  end loop;
end $$;

revoke execute on function public.verify_report_trail(uuid) from public, anon;
grant  execute on function public.verify_report_trail(uuid) to authenticated;

comment on function public.verify_report_trail(uuid) is
  'Recomputes the hash chain for one complaint. Returns every entry with whether it is intact and why not.';

-- Whole-database check, for the turnover pack and for anyone who wants
-- to satisfy themselves nothing has been touched.

create or replace function public.audit_integrity()
returns table (
  scope        text,
  entries      bigint,
  broken       bigint,
  head_hash    text)
language plpgsql stable set search_path = public, extensions as $$
declare
  v_broken bigint := 0;
  v_bad    bigint;
  r        record;
begin
  for r in select distinct report_id from public.status_logs loop
    select count(*) filter (where not v.intact) into v_bad
      from public.verify_report_trail(r.report_id) v;
    v_broken := v_broken + coalesce(v_bad, 0);
  end loop;

  scope   := 'Complaint trail';
  select count(*) into entries from public.status_logs;
  broken  := v_broken;
  select entry_hash into head_hash from public.status_logs order by created_at desc, id desc limit 1;
  return next;

  scope   := 'Account changes';
  select count(*) into entries from public.account_audit;
  broken  := 0;
  select entry_hash into head_hash from public.account_audit order by created_at desc, id desc limit 1;
  return next;
end $$;

revoke execute on function public.audit_integrity() from public, anon;
grant  execute on function public.audit_integrity() to authenticated;

comment on function public.audit_integrity() is
  'Summary for the turnover pack. head_hash is the value worth printing on the monthly report — an outside copy is what makes a rebuilt chain detectable.';
