-- =============================================================================
-- supabase/tests/rls_test.sql
-- =============================================================================
-- pgTAP test suite covering the Sprint 1 RLS baseline:
--   1. Every public table has RLS enabled AND forced.
--   2. The 12 expected tables exist.
--   3. The auto_enable_rls() event trigger fires on a freshly-created table.
--   4. The 4 owner-only policies exist on every user-owned table.
--   5. consume_token() exists and is SECURITY DEFINER.
--   6. Default categories were seeded (15 rows, user_id IS NULL).
--
-- Negative cross-tenant tests ("user A can't read user B's expenses") need
-- two real auth.users rows + a JWT-aware session — wired up in the Sprint 9
-- expansion of this file.
--
-- Run locally:
--     supabase db reset                              # apply migrations + seed
--     pg_prove -d "$(supabase db url)" supabase/tests/rls_test.sql
-- Or via the Supabase test runner:
--     supabase test db
-- =============================================================================

begin;

create extension if not exists pgtap with schema public;

-- no_plan(): pgTAP counts assertions automatically and reports the total via
-- finish(). Preferred over a hard-coded plan(N) here because this file grows
-- every sprint (Sprint 8 adds user_corrections) and a stale N silently fails.
select * from no_plan();

-- -----------------------------------------------------------------------------
-- 1. Tables exist
-- -----------------------------------------------------------------------------
select has_table('public', 'categories',     'categories table exists');
select has_table('public', 'receipts',       'receipts table exists');
select has_table('public', 'receipt_items',  'receipt_items table exists');
select has_table('public', 'expenses',       'expenses table exists');
select has_table('public', 'budgets',        'budgets table exists');
select has_table('public', 'budget_alerts',  'budget_alerts table exists');
select has_table('public', 'tags',           'tags table exists');
select has_table('public', 'expense_tags',   'expense_tags table exists');
select has_table('public', 'user_settings',  'user_settings table exists');
select has_table('public', 'receipt_shares', 'receipt_shares table exists');
select has_table('public', 'rate_limits',    'rate_limits table exists');
select has_table('public', 'sync_log',       'sync_log table exists');
select has_table('public', 'user_corrections',
  'user_corrections table exists');

-- -----------------------------------------------------------------------------
-- 2. RLS is enabled on every public table (and forced for table owners)
-- -----------------------------------------------------------------------------
-- NB: use `select ok(...) from unnest(...)` — NOT a `do $$ … perform ok() $$`
-- loop. Inside PL/pgSQL, `perform ok(...)` discards the TAP line ok() returns
-- (only the side-effecting counter advances), so the harness sees test numbers
-- jump and reports "tests out of sequence". The set-returning form prints one
-- TAP line per row, in order.
select ok(
  (select relrowsecurity
     from pg_class
    where oid = ('public.' || t)::regclass),
  format('RLS is enabled on public.%s', t)
)
from unnest(array[
  'categories','receipts','receipt_items','expenses','budgets',
  'budget_alerts','tags','expense_tags','user_settings','receipt_shares',
  'rate_limits','sync_log','user_corrections'
]) as t;

select ok(
  (select relforcerowsecurity
     from pg_class
    where oid = ('public.' || t)::regclass),
  format('RLS is FORCED on public.%s', t)
)
from unnest(array[
  'categories','receipts','receipt_items','expenses','budgets',
  'budget_alerts','tags','expense_tags','user_settings','receipt_shares',
  'rate_limits','sync_log','user_corrections'
]) as t;

-- -----------------------------------------------------------------------------
-- 3. auto_enable_rls() catches new tables
-- -----------------------------------------------------------------------------
create table public._rls_probe_tmp (id int);
select ok(
  (select relrowsecurity
     from pg_class
    where oid = 'public._rls_probe_tmp'::regclass),
  'auto_enable_rls() turned on RLS for a newly-created table'
);
drop table public._rls_probe_tmp;

-- -----------------------------------------------------------------------------
-- 4. Owner-only policies exist (sample-check three tables)
-- -----------------------------------------------------------------------------
select policies_are(
  'public', 'expenses',
  array[
    'expenses_select_own',
    'expenses_insert_own',
    'expenses_update_own',
    'expenses_delete_own'
  ],
  'expenses has exactly the 4 owner-only policies'
);

select policies_are(
  'public', 'receipts',
  array[
    'receipts_select_own',
    'receipts_insert_own',
    'receipts_update_own',
    'receipts_delete_own'
  ],
  'receipts has exactly the 4 owner-only policies'
);

select policies_are(
  'public', 'budgets',
  array[
    'budgets_select_own',
    'budgets_insert_own',
    'budgets_update_own',
    'budgets_delete_own'
  ],
  'budgets has exactly the 4 owner-only policies'
);

-- categories uses the "default or own" pattern.
select policies_are(
  'public', 'categories',
  array[
    'categories_select_default_or_own',
    'categories_insert_own',
    'categories_update_own',
    'categories_delete_own'
  ],
  'categories has the default-or-own select policy plus 3 write policies'
);

-- rate_limits intentionally has zero policies → no client access.
select policies_are(
  'public', 'rate_limits',
  array[]::text[],
  'rate_limits has NO policies (clients have zero access)'
);

-- user_corrections (Sprint 8) uses the standard owner-only 4-policy set.
select policies_are(
  'public', 'user_corrections',
  array[
    'user_corrections_select_own',
    'user_corrections_insert_own',
    'user_corrections_update_own',
    'user_corrections_delete_own'
  ],
  'user_corrections has exactly the 4 owner-only policies'
);

-- -----------------------------------------------------------------------------
-- 5. consume_token() function
-- -----------------------------------------------------------------------------
select has_function(
  'public', 'consume_token',
  array['uuid','text','integer','integer'],
  'consume_token(user_id, bucket, max, refill) exists'
);

select is(
  (select prosecdef
     from pg_proc
    where proname = 'consume_token'
      and pronamespace = 'public'::regnamespace
    limit 1),
  true,
  'consume_token() is SECURITY DEFINER'
);

-- -----------------------------------------------------------------------------
-- 6. Default categories seeded
-- -----------------------------------------------------------------------------
select is(
  (select count(*)::int
     from public.categories
    where user_id is null),
  15,
  '15 global default categories are seeded'
);

select is(
  (select count(*)::int
     from public.categories
    where user_id is null and is_custom = true),
  0,
  'default categories are not marked as custom'
);

-- -----------------------------------------------------------------------------
-- 7. set_updated_at() trigger function exists
-- -----------------------------------------------------------------------------
select has_function(
  'public', 'set_updated_at', array[]::text[],
  'set_updated_at() trigger function exists'
);

-- -----------------------------------------------------------------------------
-- 8. Cross-tenant isolation for user_corrections (Sprint 8)
--    Two real auth.users + JWT-aware sessions prove the owner-only policies
--    actually block reads/writes across tenants (not just that they exist).
-- -----------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user-a@smartspend.test'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user-b@smartspend.test')
on conflict (id) do nothing;

-- A correction owned by user B, tagged with a global default category.
insert into public.user_corrections
  (user_id, store_name, new_category_id, occurred_at)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'Migros',
   (select id from public.categories where user_id is null limit 1),
   timezone('utc', now()));

-- Act as user A (non-superuser role + JWT claims → RLS is enforced).
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';

select is(
  (select count(*)::int from public.user_corrections),
  0,
  'user A cannot SELECT user B''s user_correction row'
);

select throws_ok(
  $$ insert into public.user_corrections
       (user_id, store_name, new_category_id, occurred_at)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Forged',
             (select id from public.categories where user_id is null limit 1),
             timezone('utc', now())) $$,
  '42501',
  null,
  'user A cannot INSERT a row forged with user B''s user_id'
);

select lives_ok(
  $$ delete from public.user_corrections where store_name = 'Migros' $$,
  'user A DELETE matches zero of user B''s rows (no error, no effect)'
);

-- Back to the privileged session role to confirm B's row is untouched.
reset role;
select is(
  (select count(*)::int
     from public.user_corrections
    where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and store_name = 'Migros'),
  1,
  'user B''s user_correction row survived user A''s delete attempt'
);

select * from finish();
rollback;
