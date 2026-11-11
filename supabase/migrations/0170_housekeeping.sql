-- 0170: housekeeping from the backend sweep (11 Nov 2026).
--
-- 1. The scheduled jobs' own history was never purged. pg_cron writes one row to cron.job_run_details for every run of every
--    job; with 22 jobs (four of them every minute) that was 21,600 rows in the first four days on the Singapore database, about
--    two million a year (the Mumbai database had 173,000). A daily job keeps the last seven days: enough to see what failed
--    this week, which is what check_system_health() and a person looking into a problem need.
-- 2. Five functions had no fixed search_path (Supabase's "function_search_path_mutable" advice): the two trigger functions,
--    and the three that already carried a setting of their own. They now name it, like every other function here.
--    Five more are left as they are, on purpose: _colour_dist, _places_grp, _places_query, is_media_url and
--    is_identity_media_url are small immutable SQL helpers that PostgreSQL folds into the query that calls them; a function
--    with a setting of its own cannot be folded in, so pinning them would slow the place search and the media checks. They run
--    with the caller's own rights and touch no table.
-- Nothing a page or the app sees changes.

-- ---------- 1. the job history ----------
create or replace function public.purge_cron_history()
returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare n integer;
begin
  delete from cron.job_run_details where end_time < now() - interval '7 days'
     or (end_time is null and start_time < now() - interval '7 days');
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_cron_history() from public, anon, authenticated;
comment on function public.purge_cron_history() is '0170: keeps the last seven days of the scheduled jobs'' run history (cron.job_run_details). Run daily by the cron-history-purge job.';

select cron.unschedule('cron-history-purge') where exists (select 1 from cron.job where jobname = 'cron-history-purge');
select cron.schedule('cron-history-purge', '10 4 * * *', $$select public.purge_cron_history()$$);

-- ---------- 2. a fixed search_path where it costs nothing ----------
alter function public._status_log_no_repeat() set search_path = public, extensions;
alter function public.assign_tracking_id() set search_path = public, extensions;
alter function public._smart_common_words() set search_path = public, extensions;
alter function public._smart_id_number(text) set search_path = public, extensions;
alter function public._smart_id_number_ok(public.id_document_type, text) set search_path = public, extensions;
