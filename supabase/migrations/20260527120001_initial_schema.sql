-- =============================================================================
-- 20260527120001_initial_schema.sql
-- =============================================================================
-- SmartSpend's authoritative server schema.
--
-- Mirrors the Drift schema in `lib/core/database/tables.dart`, with these
-- deltas:
--   * Primary keys are `uuid` (Supabase canonical), not `int autoIncrement`.
--   * Every user-owned table carries `user_id uuid references auth.users(id)
--     on delete cascade not null`.
--   * Monetary columns are `bigint` (cents/kuruş).
--   * `updated_at` is maintained by the `set_updated_at()` trigger; never set
--     it manually from the client.
--
-- The event trigger installed in 20260527120000_* turns RLS on for each
-- table automatically; the next migration adds policies.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- categories — default + user-defined
-- -----------------------------------------------------------------------------
create table public.categories (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          references auth.users(id) on delete cascade,
  name          text          not null,
  icon          text          not null,
  -- bigint so 32-bit unsigned ARGB values (e.g. 0xFF4CAF50 = 4283215696)
  -- fit. Postgres `integer` is signed 32-bit and overflows on bright colors.
  color         bigint        not null,
  is_custom     boolean       not null default false,
  sort_order    integer       not null default 0,
  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now())
);

create index categories_user_id_idx on public.categories(user_id);
create index categories_sort_order_idx on public.categories(sort_order);

create trigger trg_categories_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

comment on table public.categories is
  'Default categories (user_id IS NULL) ship globally; custom ones are scoped '
  'to the owning user via RLS.';

-- -----------------------------------------------------------------------------
-- receipts
-- -----------------------------------------------------------------------------
create table public.receipts (
  id                    uuid          primary key default gen_random_uuid(),
  user_id               uuid          not null references auth.users(id) on delete cascade,
  store_name            text,
  date                  date          not null,
  total                 bigint        not null,
  currency              text          not null default 'TRY',
  image_path            text,
  storage_object_path   text,
  raw_ocr_text          text,
  confidence_score      real,
  created_at            timestamptz   not null default timezone('utc', now()),
  updated_at            timestamptz   not null default timezone('utc', now())
);

create index receipts_user_id_idx       on public.receipts(user_id);
create index receipts_date_idx          on public.receipts(date desc);
create index receipts_user_date_idx     on public.receipts(user_id, date desc);

create trigger trg_receipts_updated_at
  before update on public.receipts
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- receipt_items
-- -----------------------------------------------------------------------------
create table public.receipt_items (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          not null references auth.users(id) on delete cascade,
  receipt_id    uuid          not null references public.receipts(id) on delete cascade,
  name          text          not null,
  quantity      real          not null default 1.0,
  unit_price    bigint        not null,
  total_price   bigint        not null,
  category_id   uuid          references public.categories(id) on delete set null,
  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now())
);

create index receipt_items_receipt_id_idx  on public.receipt_items(receipt_id);
create index receipt_items_user_id_idx     on public.receipt_items(user_id);
create index receipt_items_category_id_idx on public.receipt_items(category_id);

create trigger trg_receipt_items_updated_at
  before update on public.receipt_items
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- expenses
-- -----------------------------------------------------------------------------
create table public.expenses (
  id                uuid          primary key default gen_random_uuid(),
  user_id           uuid          not null references auth.users(id) on delete cascade,
  amount            bigint        not null,
  category_id       uuid          not null references public.categories(id) on delete restrict,
  receipt_id        uuid          references public.receipts(id) on delete set null,
  note              text,
  date              timestamptz   not null,
  is_manual         boolean       not null default true,
  is_recurring      boolean       not null default false,
  recurring_period  text          check (recurring_period in (null, 'weekly', 'monthly', 'yearly')),
  created_at        timestamptz   not null default timezone('utc', now()),
  updated_at        timestamptz   not null default timezone('utc', now())
);

create index expenses_user_id_idx          on public.expenses(user_id);
create index expenses_date_idx             on public.expenses(date desc);
create index expenses_user_date_idx        on public.expenses(user_id, date desc);
create index expenses_user_category_idx    on public.expenses(user_id, category_id);
create index expenses_receipt_id_idx       on public.expenses(receipt_id) where receipt_id is not null;

create trigger trg_expenses_updated_at
  before update on public.expenses
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- budgets
-- -----------------------------------------------------------------------------
create table public.budgets (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          not null references auth.users(id) on delete cascade,
  category_id   uuid          references public.categories(id) on delete cascade,
  amount        bigint        not null,
  period        text          not null check (period in ('weekly', 'monthly')),
  start_date    date          not null,
  is_active     boolean       not null default true,
  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now())
);

create index budgets_user_id_idx     on public.budgets(user_id);
create index budgets_user_active_idx on public.budgets(user_id, is_active);

create trigger trg_budgets_updated_at
  before update on public.budgets
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- budget_alerts
-- -----------------------------------------------------------------------------
create table public.budget_alerts (
  id                uuid          primary key default gen_random_uuid(),
  user_id           uuid          not null references auth.users(id) on delete cascade,
  budget_id         uuid          not null references public.budgets(id) on delete cascade,
  threshold_percent integer       not null check (threshold_percent between 1 and 200),
  is_triggered      boolean       not null default false,
  triggered_at      timestamptz,
  created_at        timestamptz   not null default timezone('utc', now()),
  updated_at        timestamptz   not null default timezone('utc', now())
);

create index budget_alerts_budget_id_idx on public.budget_alerts(budget_id);
create index budget_alerts_user_id_idx   on public.budget_alerts(user_id);

create trigger trg_budget_alerts_updated_at
  before update on public.budget_alerts
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- tags + expense_tags (join)
-- -----------------------------------------------------------------------------
create table public.tags (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          not null references auth.users(id) on delete cascade,
  name          text          not null,
  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now()),
  unique (user_id, name)
);

create index tags_user_id_idx on public.tags(user_id);

create trigger trg_tags_updated_at
  before update on public.tags
  for each row execute function public.set_updated_at();

create table public.expense_tags (
  expense_id    uuid          not null references public.expenses(id) on delete cascade,
  tag_id        uuid          not null references public.tags(id) on delete cascade,
  user_id       uuid          not null references auth.users(id) on delete cascade,
  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now()),
  primary key (expense_id, tag_id)
);

create index expense_tags_user_id_idx on public.expense_tags(user_id);
create index expense_tags_tag_id_idx  on public.expense_tags(tag_id);

create trigger trg_expense_tags_updated_at
  before update on public.expense_tags
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- user_settings — per-user cross-device preferences
-- -----------------------------------------------------------------------------
create table public.user_settings (
  user_id                 uuid          primary key references auth.users(id) on delete cascade,
  default_currency        text          not null default 'TRY',
  locale                  text          not null default 'tr',
  notifications_enabled   boolean       not null default true,
  dark_mode               boolean       not null default false,
  created_at              timestamptz   not null default timezone('utc', now()),
  updated_at              timestamptz   not null default timezone('utc', now())
);

create trigger trg_user_settings_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- receipt_shares — bill-splitting metadata (Sprint 7)
-- -----------------------------------------------------------------------------
create table public.receipt_shares (
  id                  uuid          primary key default gen_random_uuid(),
  receipt_id          uuid          not null references public.receipts(id) on delete cascade,
  owner_user_id       uuid          not null references auth.users(id) on delete cascade,
  shared_with_email   text          not null,
  share_payload       jsonb         not null,
  created_at          timestamptz   not null default timezone('utc', now()),
  updated_at          timestamptz   not null default timezone('utc', now())
);

create index receipt_shares_receipt_id_idx    on public.receipt_shares(receipt_id);
create index receipt_shares_owner_user_id_idx on public.receipt_shares(owner_user_id);

create trigger trg_receipt_shares_updated_at
  before update on public.receipt_shares
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- rate_limits — token bucket backing for heavy Edge Functions
-- -----------------------------------------------------------------------------
create table public.rate_limits (
  user_id       uuid          not null references auth.users(id) on delete cascade,
  bucket        text          not null,
  tokens        integer       not null,
  refilled_at   timestamptz   not null default timezone('utc', now()),
  primary key (user_id, bucket)
);

comment on table public.rate_limits is
  'Token bucket state per (user_id, bucket). The Postgres function '
  'consume_token() is the only writer; clients must not touch this table '
  'directly — RLS denies all client access.';

-- -----------------------------------------------------------------------------
-- sync_log — server-side audit of sync operations (debugging only)
-- -----------------------------------------------------------------------------
create table public.sync_log (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          references auth.users(id) on delete cascade,
  table_name    text          not null,
  row_id        uuid          not null,
  action        text          not null,
  occurred_at   timestamptz   not null default timezone('utc', now())
);

create index sync_log_user_id_idx     on public.sync_log(user_id);
create index sync_log_occurred_at_idx on public.sync_log(occurred_at desc);
