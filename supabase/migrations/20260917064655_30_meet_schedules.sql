create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname in ('omelo-comms-dispatch', 'omelo-meet-housekeeping');

select cron.schedule(
  'omelo-comms-dispatch',
  '* * * * *',
  $$ select net.http_post(
       url := 'https://jfyqnlucoraazjkndbvm.supabase.co/functions/v1/comms-dispatch',
       headers := '{"Content-Type": "application/json"}'::jsonb,
       body := '{}'::jsonb,
       timeout_milliseconds := 30000) $$
);

select cron.schedule(
  'omelo-meet-housekeeping',
  '*/5 * * * *',
  $$ select omelo_private.omelo_meet_housekeeping() $$
);