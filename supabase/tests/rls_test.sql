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

select plan(50);

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

-- -----------------------------------------------------------------------------
-- 2. RLS is enabled on every public table (and forced for table owners)
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'categories','receipts','receipt_items','expenses','budgets',
    'budget_alerts','tags','expense_tags','user_settings','receipt_shares',
    'rate_limits','sync_log'
  ];
begin
  foreach t in array tables loop
    perform ok(
      (select relrowsecurity
         from pg_class
        where oid = ('public.'||t)::regclass),
      format('RLS is enabled on public.%s', t)
    );
    perform ok(
      (select relforcerowsecurity
         from pg_class
        where oid = ('public.'||t)::regclass),
      format('RLS is FORCED on public.%s', t)
    );
  end loop;
end $$;

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

select * from finish();
rollback;
