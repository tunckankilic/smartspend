-- =============================================================================
-- 20260527120002_rls_policies.sql
-- =============================================================================
-- Owner-only RLS for every public table. RLS is already enabled by the
-- auto_enable_rls() event trigger — this file just attaches policies.
--
-- Pattern:
--   * select  → auth.uid() = user_id
--   * insert  → with check auth.uid() = user_id
--   * update  → using + with check auth.uid() = user_id
--   * delete  → using auth.uid() = user_id
--
-- Special cases:
--   * categories          — defaults (user_id IS NULL) readable by everyone,
--                           only own customs are writable.
--   * receipt_items / expense_tags — owner is the parent row's user_id; we
--                           still store user_id directly for fast filters.
--   * receipt_shares      — owner can manage; sharing-recipient access lands
--                           in Sprint 7 with email-based join.
--   * rate_limits         — clients have ZERO access. consume_token() runs
--                           SECURITY DEFINER as the table owner.
--   * sync_log            — read-only for the owning user; the Edge Function
--                           writes via service_role.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- categories
-- -----------------------------------------------------------------------------
create policy "categories_select_default_or_own"
  on public.categories
  for select
  using (user_id is null or auth.uid() = user_id);

create policy "categories_insert_own"
  on public.categories
  for insert
  with check (auth.uid() = user_id and is_custom = true);

create policy "categories_update_own"
  on public.categories
  for update
  using (auth.uid() = user_id and is_custom = true)
  with check (auth.uid() = user_id and is_custom = true);

create policy "categories_delete_own"
  on public.categories
  for delete
  using (auth.uid() = user_id and is_custom = true);

-- -----------------------------------------------------------------------------
-- receipts
-- -----------------------------------------------------------------------------
create policy "receipts_select_own"
  on public.receipts for select
  using (auth.uid() = user_id);
create policy "receipts_insert_own"
  on public.receipts for insert
  with check (auth.uid() = user_id);
create policy "receipts_update_own"
  on public.receipts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "receipts_delete_own"
  on public.receipts for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- receipt_items
-- -----------------------------------------------------------------------------
create policy "receipt_items_select_own"
  on public.receipt_items for select
  using (auth.uid() = user_id);
create policy "receipt_items_insert_own"
  on public.receipt_items for insert
  with check (auth.uid() = user_id);
create policy "receipt_items_update_own"
  on public.receipt_items for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "receipt_items_delete_own"
  on public.receipt_items for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- expenses
-- -----------------------------------------------------------------------------
create policy "expenses_select_own"
  on public.expenses for select
  using (auth.uid() = user_id);
create policy "expenses_insert_own"
  on public.expenses for insert
  with check (auth.uid() = user_id);
create policy "expenses_update_own"
  on public.expenses for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "expenses_delete_own"
  on public.expenses for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- budgets
-- -----------------------------------------------------------------------------
create policy "budgets_select_own"
  on public.budgets for select
  using (auth.uid() = user_id);
create policy "budgets_insert_own"
  on public.budgets for insert
  with check (auth.uid() = user_id);
create policy "budgets_update_own"
  on public.budgets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "budgets_delete_own"
  on public.budgets for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- budget_alerts
-- -----------------------------------------------------------------------------
create policy "budget_alerts_select_own"
  on public.budget_alerts for select
  using (auth.uid() = user_id);
create policy "budget_alerts_insert_own"
  on public.budget_alerts for insert
  with check (auth.uid() = user_id);
create policy "budget_alerts_update_own"
  on public.budget_alerts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "budget_alerts_delete_own"
  on public.budget_alerts for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- tags
-- -----------------------------------------------------------------------------
create policy "tags_select_own"
  on public.tags for select
  using (auth.uid() = user_id);
create policy "tags_insert_own"
  on public.tags for insert
  with check (auth.uid() = user_id);
create policy "tags_update_own"
  on public.tags for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "tags_delete_own"
  on public.tags for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- expense_tags
-- -----------------------------------------------------------------------------
create policy "expense_tags_select_own"
  on public.expense_tags for select
  using (auth.uid() = user_id);
create policy "expense_tags_insert_own"
  on public.expense_tags for insert
  with check (auth.uid() = user_id);
create policy "expense_tags_update_own"
  on public.expense_tags for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "expense_tags_delete_own"
  on public.expense_tags for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- user_settings
-- -----------------------------------------------------------------------------
create policy "user_settings_select_own"
  on public.user_settings for select
  using (auth.uid() = user_id);
create policy "user_settings_insert_own"
  on public.user_settings for insert
  with check (auth.uid() = user_id);
create policy "user_settings_update_own"
  on public.user_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "user_settings_delete_own"
  on public.user_settings for delete
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- receipt_shares — owner-only for Sprint 1; recipient access in Sprint 7.
-- -----------------------------------------------------------------------------
create policy "receipt_shares_select_owner"
  on public.receipt_shares for select
  using (auth.uid() = owner_user_id);
create policy "receipt_shares_insert_owner"
  on public.receipt_shares for insert
  with check (auth.uid() = owner_user_id);
create policy "receipt_shares_update_owner"
  on public.receipt_shares for update
  using (auth.uid() = owner_user_id)
  with check (auth.uid() = owner_user_id);
create policy "receipt_shares_delete_owner"
  on public.receipt_shares for delete
  using (auth.uid() = owner_user_id);

-- -----------------------------------------------------------------------------
-- rate_limits — no client access at all
-- -----------------------------------------------------------------------------
-- RLS is on (auto trigger). Intentionally NO policies attached — every
-- client query returns "0 rows" / fails. The only legitimate writer is
-- public.consume_token() which is SECURITY DEFINER.

-- -----------------------------------------------------------------------------
-- sync_log — read-only for the row's owner; writes happen via service_role
-- -----------------------------------------------------------------------------
create policy "sync_log_select_own"
  on public.sync_log for select
  using (auth.uid() = user_id);
-- No insert / update / delete policy — clients can never write.
