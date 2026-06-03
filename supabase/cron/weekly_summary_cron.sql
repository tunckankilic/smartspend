-- weekly-summary cron — MANUAL-APPLY TEMPLATE (do NOT put in migrations/)
-- ─────────────────────────────────────────────────────────────────────────
-- This file is intentionally OUTSIDE supabase/migrations/ so `supabase db push`
-- never runs it automatically. Apply it by hand in the prod SQL editor only
-- after (a) the placeholders below are filled and (b) the weekly-summary Edge
-- Function is finished (see CAVEAT).
--
-- ⚠️ CAVEAT — weekly-summary is currently a STUB and is DEFERRED from v1:
--   • Its `Deno.serve(handle)` entry-point is commented out in
--     supabase/functions/weekly-summary/index.ts ("don't publish an
--     unfinished function").
--   • It requires a per-USER JWT (it runs under RLS as that user). A cron job
--     cannot mint user JWTs without service_role admin, and the function
--     forbids service_role.
--   ➜ Before scheduling, EITHER refactor weekly-summary into an admin/batch
--     function that iterates users server-side (using getAdminClient), OR have
--     the cron call a thin dispatcher that signs a short-lived token per user.
--   For v1, leaving this unscheduled is fine — the app ships without it.
--
-- The pattern below (pg_cron + pg_net + Vault) is the canonical, reusable way
-- to call an Edge Function on a schedule once the function is deploy-ready.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. Enable the scheduler + HTTP client extensions (idempotent).
create extension if not exists pg_cron  with schema extensions;
create extension if not exists pg_net   with schema extensions;

-- 2. Store the auth token in Vault so it never sits in plaintext in the job.
--    Replace the value with the token the (finished) function expects.
--    NOTE: do NOT store the service_role key here while the function forbids
--    service_role — see the CAVEAT above.
--    select vault.create_secret('REPLACE_WITH_FUNCTION_AUTH_TOKEN',
--                               'weekly_summary_token');

-- 3. Schedule: every Sunday at 09:00 UTC. Adjust the cron expression as needed.
--    Replace <PROJECT_REF> with your prod project ref.
select cron.schedule(
  'weekly-summary',
  '0 9 * * 0',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/weekly-summary',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets
          where name = 'weekly_summary_token')
    ),
    body    := jsonb_build_object('source', 'cron')
  );
  $$
);

-- To inspect / remove the job later:
--   select * from cron.job;
--   select cron.unschedule('weekly-summary');
