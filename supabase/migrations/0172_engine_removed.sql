-- 0172: the server engine is removed (11 Nov 2026, the backend sweep; Ace's decision).
--
-- 0137 added a queue for a separate OCR service (engine/) that would read sign-ups' ID photos on the server. That service was
-- never deployed: the app reads the ID on the phone and sends what it read (submit_id_reading, kept). Yet engine-tick ran every
-- minute and returned 'off', and the repository built and scanned the engine's image on every change. This removes the queue,
-- its two jobs and its status function. Nothing else used them (checked on the live database: no other function, view, foreign
-- key or vault secret referred to them, and the queue was empty).
--
-- Kept from 0137, because the app's own reading uses them: submit_id_reading, _id_reading_save, _cld_sign.

select cron.unschedule('engine-tick') where exists (select 1 from cron.job where jobname = 'engine-tick');
select cron.unschedule('engine-jobs-purge') where exists (select 1 from cron.job where jobname = 'engine-jobs-purge');

drop function if exists public.engine_status();
drop function if exists public.engine_tick();
drop function if exists public.engine_enqueue();
drop function if exists public._engine_config();
drop table if exists public.engine_jobs;
