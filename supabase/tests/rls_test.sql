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
select has_table('public', 'product_events',
  'product_events table exists');

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
  'rate_limits','sync_log','user_corrections','product_events'
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
  'rate_limits','sync_log','user_corrections','product_events'
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


-- product_events (1.3.0, Block 3) uses the standard owner-only 4-policy set.
select policies_are(
  'public', 'product_events',
  array[
    'product_events_select_own',
    'product_events_insert_own',
    'product_events_update_own',
    'product_events_delete_own'
  ],
  'product_events has exactly the 4 owner-only policies'
);

-- -----------------------------------------------------------------------------
-- 9. product_events (1.3.0, Block 3)
--
--    9a. The "no free text, no amounts, no document content" rule is a
--        constraint, not a convention. These assertions are the proof: if a
--        future change loosens the CHECKs, this file fails rather than
--        letting a store name or an OCR line reach the server.
--    9b. Counter semantics (D-14): each device owns its own row, writes are
--        absolute, and readers sum() across devices. Re-sending the same
--        value must be a no-op — that is what makes upload retries safe.
--    9c. Cross-tenant isolation, same shape as section 8.
-- -----------------------------------------------------------------------------

-- 9a. Shape constraints reject everything that is not an identifier.
select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, day, count)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '11111111-1111-1111-1111-111111111111',
             'Migros Kadikoy subesi fisi', current_date, 1) $$,
  '23514',
  null,
  'event_key rejects a free-text phrase (spaces + uppercase)'
);

select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, day, count)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '11111111-1111-1111-1111-111111111111',
             repeat('a', 49), current_date, 1) $$,
  '23514',
  null,
  'event_key rejects anything past the 48-char cap'
);

select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, dimension, day, count)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '11111111-1111-1111-1111-111111111111',
             'scan_started', '1.249,90 TL', current_date, 1) $$,
  '23514',
  null,
  'dimension rejects an amount (comma, period, space)'
);

select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, day, count)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'not-a-uuid-shape!', 'scan_started', current_date, 1) $$,
  '23514',
  null,
  'device_id rejects anything that is not a hex/uuid-shaped install id'
);

select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, day, count)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '11111111-1111-1111-1111-111111111111',
             'scan_started', current_date, -1) $$,
  '23514',
  null,
  'count rejects a negative value'
);

select hasnt_column(
  'public', 'product_events', 'amount',
  'product_events has no amount column — a lira value has nowhere to land'
);

-- 9b. Counter semantics: two devices, one user, one event, one day.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111', 'scan_started', date '2026-09-01', 4),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '22222222-2222-2222-2222-222222222222', 'scan_started', date '2026-09-01', 2);

select is(
  (select sum(count)::int from public.product_events
    where event_key = 'scan_started' and day = date '2026-09-01'),
  6,
  'two devices on the same day aggregate to the sum, not to one survivor'
);

-- The client's upload, replayed. Absolute value, ON CONFLICT DO UPDATE.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111', 'scan_started', date '2026-09-01', 4)
on conflict (user_id, device_id, event_key, dimension, day)
do update set count = excluded.count;

select is(
  (select sum(count)::int from public.product_events
    where event_key = 'scan_started' and day = date '2026-09-01'),
  6,
  'replaying the same absolute count is a no-op — upload retries are safe'
);

select is(
  (select count(*)::int from public.product_events
    where event_key = 'scan_started' and day = date '2026-09-01'),
  2,
  'the replay updated a row rather than inserting a third'
);

-- Device 1 observes two more scans and sends its new absolute total.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111', 'scan_started', date '2026-09-01', 6)
on conflict (user_id, device_id, event_key, dimension, day)
do update set count = excluded.count;

select is(
  (select sum(count)::int from public.product_events
    where event_key = 'scan_started' and day = date '2026-09-01'),
  8,
  'device 1 advancing to 6 lifts the total to 8 without touching device 2'
);

-- The empty-string dimension sentinel is a real conflict target, so a second
-- write for the same key does not slip past ON CONFLICT as a fresh row.
select is(
  (select count(*)::int from public.product_events
    where device_id = '11111111-1111-1111-1111-111111111111'
      and event_key = 'scan_started'
      and dimension = ''),
  1,
  'the empty-string dimension sentinel matches ON CONFLICT (never NULL-skips)'
);

-- A different dimension is a different counter, not a collision.
insert into public.product_events
  (user_id, device_id, event_key, dimension, day, count)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111',
   'tax_profile_completed', 'limited', date '2026-09-01', 1);

select is(
  (select count(*)::int from public.product_events
    where device_id = '11111111-1111-1111-1111-111111111111'),
  2,
  'a categorical dimension gets its own counter row'
);

-- 9c. Cross-tenant isolation.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '33333333-3333-3333-3333-333333333333', 'scan_approved', date '2026-09-01', 9);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';

select is(
  (select count(*)::int from public.product_events
    where event_key = 'scan_approved'),
  0,
  'user A cannot SELECT user B''s product_events row'
);

select throws_ok(
  $$ insert into public.product_events
       (user_id, device_id, event_key, day, count)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             '44444444-4444-4444-4444-444444444444',
             'forged_event', current_date, 1) $$,
  '42501',
  null,
  'user A cannot INSERT a product_events row forged with user B''s user_id'
);

select lives_ok(
  $$ update public.product_events set count = 0 where event_key = 'scan_approved' $$,
  'user A UPDATE matches zero of user B''s rows (no error, no effect)'
);

reset role;
select is(
  (select count from public.product_events
    where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and event_key = 'scan_approved'),
  9,
  'user B''s counter survived user A''s update attempt'
);


-- -----------------------------------------------------------------------------
-- 10. product_events retention + anonymisation (1.3.0, Block 3)
--
--     Aggregation alone does not make data anonymous. On a small user base a
--     single-contributor aggregate points at one person, so the roll-up only
--     carries a combination across when at least k distinct users are behind
--     it. These assertions are that guarantee: they fail if someone loosens
--     the threshold, and they fail if the identified rows stop being deleted.
-- -----------------------------------------------------------------------------

select has_table('public', 'product_event_daily',
  'product_event_daily table exists');

select hasnt_column('public', 'product_event_daily', 'user_id',
  'the roll-up table carries no user_id — that is what makes it anonymous');
select hasnt_column('public', 'product_event_daily', 'device_id',
  'the roll-up table carries no device_id either');

-- Same posture as rate_limits: RLS on, nothing granted to anyone.
select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.product_event_daily'::regclass),
  'RLS is enabled on public.product_event_daily'
);
select policies_are(
  'public', 'product_event_daily',
  array[]::text[],
  'product_event_daily has NO policies (clients have zero access)'
);

select has_function(
  'public', 'roll_up_product_events', array['integer','integer'],
  'roll_up_product_events(retention_days, min_users) exists'
);
select is(
  (select prosecdef from pg_proc
    where proname = 'roll_up_product_events'
      and pronamespace = 'public'::regnamespace
    limit 1),
  true,
  'roll_up_product_events() is SECURITY DEFINER'
);

-- Six users so one combination clears k=5 and another does not.
insert into auth.users (id, instance_id, aud, role, email)
select
  ('cccccccc-cccc-cccc-cccc-00000000000' || n)::uuid,
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'retention-' || n || '@smartspend.test'
from generate_series(1, 6) as n
on conflict (id) do nothing;

-- Well past the 90-day window: six users, two events each.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
select
  ('cccccccc-cccc-cccc-cccc-00000000000' || n)::uuid,
  'dddddddd-dddd-dddd-dddd-00000000000' || n,
  'retention_probe_a',
  current_date - 200,
  2
from generate_series(1, 6) as n;

-- Only two users — must be dropped, not carried across.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
select
  ('cccccccc-cccc-cccc-cccc-00000000000' || n)::uuid,
  'dddddddd-dddd-dddd-dddd-00000000000' || n,
  'retention_probe_b',
  current_date - 200,
  7
from generate_series(1, 2) as n;

-- Inside the window: must survive untouched.
insert into public.product_events
  (user_id, device_id, event_key, day, count)
values
  ('cccccccc-cccc-cccc-cccc-000000000001',
   'dddddddd-dddd-dddd-dddd-000000000001',
   'retention_probe_a', current_date - 3, 11);

select lives_ok(
  $$ select public.roll_up_product_events() $$,
  'roll_up_product_events() runs'
);

select is(
  (select total_count::int from public.product_event_daily
    where event_key = 'retention_probe_a' and day = current_date - 200),
  12,
  'a combination above the threshold is rolled up with the summed count'
);

select is(
  (select user_count from public.product_event_daily
    where event_key = 'retention_probe_a' and day = current_date - 200),
  6,
  'the roll-up records how many distinct users were behind the total'
);

select is(
  (select count(*)::int from public.product_event_daily
    where event_key = 'retention_probe_b'),
  0,
  'a combination below k distinct users is dropped, not anonymised'
);

select is(
  (select count(*)::int from public.product_events
    where day < current_date - 90),
  0,
  'every identified row past the retention window is deleted'
);

select is(
  (select count::int from public.product_events
    where event_key = 'retention_probe_a' and day = current_date - 3),
  11,
  'a row inside the retention window is untouched'
);

-- A scheduled job that runs twice must not double the totals.
select lives_ok(
  $$ select public.roll_up_product_events() $$,
  'roll_up_product_events() runs a second time'
);
select is(
  (select total_count::int from public.product_event_daily
    where event_key = 'retention_probe_a' and day = current_date - 200),
  12,
  're-running the roll-up recomputes rather than accumulates'
);
select is(
  (select count(*)::int from public.product_event_daily
    where event_key = 'retention_probe_a'),
  1,
  're-running the roll-up inserts no duplicate row'
);

-- A zero or negative window would delete everything ever collected.
select throws_ok(
  $$ select public.roll_up_product_events(0) $$,
  null,
  null,
  'a retention window below one day is refused'
);

select * from finish();
rollback;
