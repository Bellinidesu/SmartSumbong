-- 49_housekeeping.sql: the job history is purged and the trigger functions name their search_path (0170). Rolled back.
do $sweep$
declare
  v_log text := 'setup ok';   -- the first line is joined to psql's ERROR line, so the checks start on the next
  n integer; m integer; j bigint;
begin
  -- 1. the purge keeps the last seven days and drops what is older
  begin
    select jobid into j from cron.job where jobname = 'cron-history-purge' and schedule = '10 4 * * *';
    if j is null then raise exception 'the cron-history-purge job is not scheduled'; end if;
    delete from cron.job_run_details;
    insert into cron.job_run_details (jobid, runid, status, start_time, end_time)
    values (j, 900001, 'succeeded', now() - interval '10 days', now() - interval '10 days'),
           (j, 900002, 'succeeded', now() - interval '8 days',  now() - interval '8 days'),
           (j, 900003, 'failed',    now() - interval '6 days',  now() - interval '6 days'),
           (j, 900004, 'succeeded', now() - interval '1 hour',  now() - interval '1 hour'),
           (j, 900005, 'running',   now() - interval '9 days',  null),
           (j, 900006, 'running',   now() - interval '1 minute', null);
    n := public.purge_cron_history();
    select count(*) into m from cron.job_run_details;
    if n <> 3 or m <> 3 then raise exception 'purged %, % left (expected 3 and 3)', n, m; end if;
    if not exists (select 1 from cron.job_run_details where runid = 900003) then raise exception 'a failure from this week was dropped'; end if;
    if has_function_privilege('authenticated', 'public.purge_cron_history()', 'execute') or has_function_privilege('anon', 'public.purge_cron_history()', 'execute') then
      raise exception 'a signed-in or signed-out caller may run the purge';
    end if;
    v_log := v_log || E'
' || 'ok  the job history keeps seven days, and only the job may purge it';
  exception when others then v_log := v_log || E'
' || 'FAIL purge: ' || sqlerrm; end;

  -- 2. the five functions name their search_path; the five folded-in helpers are left alone
  begin
    select count(*) into n from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('_status_log_no_repeat', 'assign_tracking_id', '_smart_common_words', '_smart_id_number', '_smart_id_number_ok')
       and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
    if n <> 5 then raise exception '% of 5 functions name their search_path', n; end if;
    select count(*) into n from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proconfig is not null
       and p.proname in ('_colour_dist', '_places_grp', '_places_query', 'is_media_url', 'is_identity_media_url');
    if n <> 0 then raise exception '% of the folded-in helpers got a setting (they would no longer be folded in)', n; end if;
    v_log := v_log || E'\n' || 'ok  the trigger functions name their search_path; the folded-in helpers are untouched';
  exception when others then v_log := v_log || E'\n' || 'FAIL search_path: ' || sqlerrm; end;

  raise exception 'SWEEP-ROLLBACK%', v_log;
end $sweep$;
