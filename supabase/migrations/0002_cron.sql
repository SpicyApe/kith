-- 0002_cron.sql — pg_cron schedules for the background edge functions.
--
-- Hosted environments only: the local pglite schema test loads 0001 and 0003.
--
-- The jobs read two Vault secrets at call time. This migration is safe to apply
-- BEFORE they exist (it only warns); once you have created them, re-run the
-- scheduling block by executing `select public.schedule_background_jobs();`
-- in the SQL editor. Create the secrets with:
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');
-- `send-pushes` checks the bearer against SUPABASE_SERVICE_ROLE_KEY;
-- `generate-puzzles` accepts the same bearer as an alternative to an admin JWT.

create extension if not exists pg_net;

-- Idempotent: cron.schedule(jobname, ...) upserts by name in pg_cron >= 1.4.
create or replace function public.schedule_background_jobs()
returns text language plpgsql security definer set search_path = public, pg_temp as $fn$
declare
  have_secrets boolean;
begin
  select count(*) = 2 into have_secrets
  from vault.decrypted_secrets where name in ('project_url', 'service_role_key');
  if not have_secrets then
    raise notice 'schedule_background_jobs: Vault secrets project_url/service_role_key missing; nothing scheduled';
    return 'skipped: vault secrets missing';
  end if;

  perform cron.schedule(
    'send-pushes',
    '*/15 * * * *',
    $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-pushes',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $job$
  );

  perform cron.schedule(
    'generate-puzzles',
    '0 3 * * *',
    $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/generate-puzzles',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $job$
  );
  return 'scheduled: send-pushes (*/15 * * * *), generate-puzzles (0 3 * * *)';
end;
$fn$;

revoke all on function public.schedule_background_jobs() from public, anon, authenticated;

select public.schedule_background_jobs();
