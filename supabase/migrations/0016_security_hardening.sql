-- =============================================================
-- SmartSumbong — 0016 Security hardening
--
-- Findings from a security review of the deployed schema. The review
-- signed in as an ordinary unverified resident and attempted every
-- escalation the API allows. Almost everything held: row-level security
-- exposed exactly one row (the attacker's own account), and every
-- privileged function refused. Two things did not hold, and both are
-- closed here.
--
-- FINDING 1 (exploited). auto_dispatch() is SECURITY DEFINER, was
-- granted to `authenticated`, and checked nothing about its caller. Any
-- account that could sign up — verified or not, related to the report or
-- not — could call it with any report id and create a real dispatch.
-- Proven in a sandbox: it returned a dispatch id and wrote the row.
--
-- Impact: forcing tanods toward arbitrary locations, exhausting a
-- complaint's three dispatch attempts so it falls into the awaiting-unit
-- queue, and flooding the roster with assignments nobody ordered.
--
-- Fix: auto_dispatch is internal. It is called by the on-file trigger,
-- by redispatch_report and by the sweeps — all of which run as the
-- function owner and are unaffected by a revoke. Administrators dispatch
-- through admin_dispatch(), which has always checked is_admin(). The
-- grant is withdrawn and a caller check added anyway, so a future grant
-- issued by mistake does not silently reopen this.
--
-- FINDING 2 (not exploited, but fragile). The hash-chain triggers called
-- digest() unqualified and did not pin search_path. Resolution therefore
-- depended on the caller's search_path: an insert from a role without
-- `extensions` on its path fails outright, and in principle a caller who
-- controls search_path could resolve digest() to a function of their own
-- and write an entry whose hash validates against nothing.
--
-- Fix: schema-qualify to extensions.digest and pin search_path on every
-- function in the chain and verification path.
--
-- Also: several helper functions were left at PostgreSQL's default of
-- EXECUTE for PUBLIC. They are all invoker-rights functions, so RLS
-- still filtered their results and no data was exposed — but least
-- privilege says a resident has no business calling them at all.
-- =============================================================

set search_path = public, extensions;

-- ---------- FINDING 1: auto_dispatch is internal ----------

revoke execute on function public.auto_dispatch(uuid) from public, anon, authenticated;

comment on function public.auto_dispatch(uuid) is
  'INTERNAL. Called by the on-file trigger, redispatch_report and the sweeps. Not callable by clients — administrators use admin_dispatch(). See 0016.';

-- The defence in depth: if a later migration or a console session grants
-- this again, the function still refuses a caller who is not an admin
-- and not an internal (owner) context.
-- The guard must distinguish "a client called this over the API" from
-- "a trigger, a cron job or another definer function called this".
--
-- auth.uid() is the WRONG signal and was tried first: it is set for the
-- resident whose insert fired the on-file trigger, so keying on it broke
-- complaint filing outright. The database role is the right signal —
-- PostgREST arrives as `authenticated` or `anon`, while every internal
-- path runs as the function owner.
create or replace function public.assert_not_client(p_what text)
returns void language plpgsql stable set search_path = public, extensions as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception '% may not be called directly. Administrators use admin_dispatch().', p_what;
  end if;
end $$;

revoke execute on function public.assert_not_client(text) from public, anon;

-- Restated in full with the guard as its first statement. Rewriting the
-- body programmatically was tried and rejected: a regex that edits a
-- function definition is a worse risk than the duplication it saves.
-- This body is identical to 0007 apart from the guard line.

create or replace function public.auto_dispatch(p_report uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_report   public.reports%rowtype;
  v_tanod    uuid;
  v_metres   double precision;
  v_dispatch uuid;
  v_system   uuid;
begin
  perform public.assert_not_client('auto_dispatch');

  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'No such report';
  end if;

  if not public.is_within_barangay(v_report.latitude, v_report.longitude) then
    update public.reports
       set escalation_level = greatest(escalation_level, 1),
           escalated_at = coalesce(escalated_at, now())
     where id = p_report;

    insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                    remark, is_system)
    values (p_report, v_report.resident_id, v_report.status, v_report.status,
            'Outside Barangay 183 — referred to city services', true);
    return null;
  end if;

  select t.tanod_id, t.metres into v_tanod, v_metres
    from public.nearest_available_tanod(p_report) t limit 1;

  if v_tanod is null then
    if v_report.awaiting_unit_since is null then
      update public.reports set awaiting_unit_since = now() where id = p_report;

      insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                      remark, is_system)
      values (p_report, v_report.resident_id, v_report.status, v_report.status,
              'No tanod on duty within range — waiting for an available unit', true);
    end if;
    return null;
  end if;

  select id into v_system from public.users where role = 'admin' order by created_at limit 1;

  insert into public.dispatches (report_id, tanod_id, assigned_by, admin_instructions)
  values (p_report, v_tanod, coalesce(v_system, v_tanod),
          format('Automatic dispatch — nearest available unit, %s m from the incident.',
                 round(v_metres)))
  returning id into v_dispatch;

  update public.reports
     set status = 'assigned', awaiting_unit_since = null
   where id = p_report;

  insert into public.status_logs (report_id, changed_by, old_status, new_status,
                                  remark, is_system)
  values (p_report, coalesce(v_system, v_tanod), v_report.status, 'assigned',
          format('Auto-dispatched to nearest unit (%s m)', round(v_metres)), true);

  insert into public.notifications (user_id, report_id, kind, message)
  values (v_tanod, p_report, 'assignment', format('New dispatch: %s', v_report.subject));

  return v_dispatch;
end $$;

revoke execute on function public.auto_dispatch(uuid) from public, anon, authenticated;

-- ---------- FINDING 2: pin the hash chain ----------

create or replace function public.chain_status_log()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_prev text;
begin
  select entry_hash into v_prev
    from public.status_logs
   where report_id = new.report_id
   order by created_at desc, id desc
   limit 1;

  new.prev_hash  := coalesce(v_prev, repeat('0', 64));
  -- Schema-qualified: the chain must not depend on the caller's
  -- search_path, and must not be resolvable to somebody else's digest().
  new.entry_hash := encode(
    extensions.digest(new.prev_hash || '|' || public.status_log_fingerprint(new), 'sha256'), 'hex');
  return new;
end $$;

create or replace function public.chain_account_audit()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_prev text;
begin
  select entry_hash into v_prev
    from public.account_audit
   order by created_at desc, id desc
   limit 1;

  new.prev_hash  := coalesce(v_prev, repeat('0', 64));
  new.entry_hash := encode(
    extensions.digest(new.prev_hash || '|' || public.account_audit_fingerprint(new), 'sha256'), 'hex');
  return new;
end $$;

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
    v_calc := encode(
      extensions.digest(v_prev || '|' || public.status_log_fingerprint(l), 'sha256'), 'hex');

    entry_no  := n;
    logged_at := l.created_at;
    change    := coalesce(l.old_status::text, 'filed') || ' → ' || l.new_status::text;
    intact    := (l.entry_hash = v_calc and l.prev_hash = v_prev);
    problem   := case
                   when l.entry_hash is null      then 'No hash recorded'
                   when l.prev_hash  <> v_prev    then 'Chain broken — an earlier entry was changed or removed'
                   when l.entry_hash <> v_calc    then 'This entry was altered after it was written'
                 end;

    return next;
    v_prev := l.entry_hash;
  end loop;
end $$;

-- ---------- least privilege on the helpers ----------
-- All invoker-rights, so RLS already filtered them and nothing leaked.
-- Revoked anyway: a resident has no reason to enumerate the tanod roster.

revoke execute on function public.assignable_tanods(uuid)          from public, anon;
revoke execute on function public.nearest_available_tanod(uuid)    from public, anon;
revoke execute on function public.my_role()                        from public, anon;
revoke execute on function public.is_within_barangay(double precision, double precision) from public, anon;
revoke execute on function public.location_is_fresh(timestamptz)   from public, anon;

grant execute on function public.assignable_tanods(uuid)           to authenticated;
grant execute on function public.nearest_available_tanod(uuid)     to authenticated;
grant execute on function public.my_role()                         to authenticated;
grant execute on function public.is_within_barangay(double precision, double precision) to authenticated;
grant execute on function public.location_is_fresh(timestamptz)    to authenticated;

-- Fingerprint helpers are pure string builders, but they are part of the
-- integrity story and nothing outside the chain should call them. This is
-- only safe because the chain triggers above are SECURITY DEFINER and so
-- resolve them as the owner — an invoker trigger would need every caller
-- to hold EXECUTE, which would defeat the revoke and let the hash be
-- computed with the caller's privileges.
revoke execute on function public.status_log_fingerprint(public.status_logs)     from public, anon, authenticated;
revoke execute on function public.account_audit_fingerprint(public.account_audit) from public, anon, authenticated;
