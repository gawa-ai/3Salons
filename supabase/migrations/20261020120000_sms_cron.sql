-- Runs the send-notifications Edge Function every minute. Re-runnable. No secrets (function has verify_jwt=false).
-- Safe while salons.sms_connected = false: sms_claim() only picks up sms_test rows until a salon is switched on.
-- Supabase only: skipped on plain Postgres (local tests) where pg_cron / pg_net do not exist.
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_net')
     or not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron / pg_net not available: skipping SMS cron job';
    return;
  end if;
  create extension if not exists pg_net with schema extensions;
  if exists (select 1 from cron.job where jobname = 'app-send-sms') then
    perform cron.unschedule('app-send-sms');
  end if;
  perform cron.schedule(
    'app-send-sms',
    '* * * * *',
    $job$
      select net.http_post(
        url := 'https://vqkrvbtndnnxpcemkuce.supabase.co/functions/v1/send-notifications',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := '{}'::jsonb,
        timeout_milliseconds := 20000
      );
    $job$);
end $$;
