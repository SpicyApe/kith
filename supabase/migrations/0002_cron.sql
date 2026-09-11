-- 0002_cron.sql — pg_cron schedules for the background edge functions.
--
-- Hosted environments only: this migration is NOT applied by the local pglite
-- schema test (tests/schema_check.mjs), which only loads 0001_init.sql.
--
-- Before applying, create the two Vault secrets these jobs read at call time
-- (run once, in the Supabase SQL editor or via the CLI, against the project
-- this migration is being applied to):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');
-- `send-pushes` calls itself with the service role key as a bearer token
-- (its own auth check is a plain equality against SUPABASE_SERVICE_ROLE_KEY);
-- `generate-puzzles` accepts the same bearer as an alternative to an admin JWT.

create extension if not exists pg_net;

select cron.schedule(
  'send-pushes',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-pushes',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);

select cron.schedule(
  'generate-puzzles',
  '0 3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/generate-puzzles',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);
