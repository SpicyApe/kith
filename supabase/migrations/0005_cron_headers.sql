-- 0005 — cron jobs call the edge functions with the headers the functions gateway
-- actually accepts: `apikey` = the project's anon key (gateway) and
-- `Authorization: Bearer <KITH_CRON_SECRET>` (checked by the functions). The
-- service key injected into the edge runtime is an `sb_secret_…` key that the
-- gateway refuses as a bearer, so 0002's shape could never have worked.
--
-- Vault secrets read at call time (create once in the SQL editor):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<anon key>',                        'anon_key');
--   select vault.create_secret('<KITH_CRON_SECRET value>',         'cron_secret');
-- then: select public.schedule_background_jobs();

create or replace function public.schedule_background_jobs()
returns text language plpgsql security definer set search_path = public, pg_temp as $fn$
declare
  have_secrets boolean;
begin
  select count(*) = 3 into have_secrets
  from vault.decrypted_secrets where name in ('project_url', 'anon_key', 'cron_secret');
  if not have_secrets then
    raise notice 'schedule_background_jobs: Vault secrets project_url/anon_key/cron_secret missing; nothing scheduled';
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
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'anon_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
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
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'anon_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
      ),
      body := '{"daysAhead":30}'::jsonb,
      timeout_milliseconds := 120000
    );
    $job$
  );
  return 'scheduled: send-pushes (*/15 * * * *), generate-puzzles (0 3 * * *)';
end;
$fn$;

revoke all on function public.schedule_background_jobs() from public, anon, authenticated;
select public.schedule_background_jobs();
