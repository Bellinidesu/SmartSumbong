-- 0094 — The portal moved to Singapore (7 Oct 2026): smartsumbong-ph on
-- Render, next to Manila and a short hop from the Mumbai database. The
-- keep-awake ping (0091) now goes there. The old Ohio service only forwards
-- old links (PORTAL_MOVED_TO) and is left to sleep: Render's free plan has
-- hours for one always-on service, not two.

select cron.unschedule(jobid) from cron.job where jobname = 'keep-portal-awake';

select cron.schedule(
  'keep-portal-awake',
  '*/10 * * * *',
  $$ select net.http_get('https://smartsumbong-ph.onrender.com/admin/ping.php', timeout_milliseconds := 60000) $$
);
