-- 0091 — Keep the portal awake (speed, 7 Oct 2026).
--
-- Render's free web service sleeps after ~15 minutes without traffic, and
-- the next visitor waits ~50 s while it starts again. pg_cron + pg_net
-- request the portal's ping page every 10 minutes so it never sleeps.
-- To stop it: select cron.unschedule('keep-portal-awake');

select cron.unschedule(jobid) from cron.job where jobname = 'keep-portal-awake';

select cron.schedule(
  'keep-portal-awake',
  '*/10 * * * *',
  $$ select net.http_get('https://smartsumbong.onrender.com/admin/ping.php', timeout_milliseconds := 60000) $$
);
