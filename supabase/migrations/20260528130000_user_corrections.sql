-- =============================================================================
-- 20260528130000_user_corrections.sql
-- =============================================================================
-- Server mirror of the Drift `UserCorrections` table introduced in Sprint 6
-- (schema v2). The client records every time a user overrides an
-- auto-assigned category (store_name → old_category → new_category) and writes
-- rows with syncStatus = 'pending_create' / 'pending_update'. Until now the
-- Supabase counterpart was missing, so those rows had nowhere to sync. This
-- migration closes that gap.
--
-- Conventions match 20260527120001_initial_schema.sql:
--   * uuid primary key via gen_random_uuid()
--   * user_id uuid not null references auth.users(id) on delete cascade
--   * updated_at maintained by the set_updated_at() trigger
--   * RLS is auto-enabled by the auto_enable_rls() event trigger; we still
--     enable+force explicitly here so this migration is self-contained, then
--     attach the standard owner-only policies.
-- =============================================================================

create table public.user_corrections (
  id                uuid          primary key default gen_random_uuid(),
  user_id           uuid          not null references auth.users(id) on delete cascade,
  store_name        text          not null,
  old_category_id   uuid          references public.categories(id) on delete set null,
  new_category_id   uuid          not null references public.categories(id) on delete cascade,
  count             integer       not null default 1,
  occurred_at       timestamptz   not null,
  created_at        timestamptz   not null default timezone('utc', now()),
  updated_at        timestamptz   not null default timezone('utc', now())
);

create index user_corrections_user_id_idx
  on public.user_corrections(user_id);
create index user_corrections_user_store_idx
  on public.user_corrections(user_id, store_name);

create trigger trg_user_corrections_updated_at
  before update on public.user_corrections
  for each row execute function public.set_updated_at();

comment on table public.user_corrections is
  'Records user category overrides per store (store_name → old → new). Feeds '
  'the on-device categorization learning loop. Owner-only via RLS.';

-- -----------------------------------------------------------------------------
-- RLS — enable + force (belt-and-suspenders; the event trigger already does
-- this) and attach owner-only policies matching 20260527120002_rls_policies.
-- -----------------------------------------------------------------------------
alter table public.user_corrections enable row level security;
alter table public.user_corrections force row level security;

create policy "user_corrections_select_own"
  on public.user_corrections for select
  using (auth.uid() = user_id);
create policy "user_corrections_insert_own"
  on public.user_corrections for insert
  with check (auth.uid() = user_id);
create policy "user_corrections_update_own"
  on public.user_corrections for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "user_corrections_delete_own"
  on public.user_corrections for delete
  using (auth.uid() = user_id);
