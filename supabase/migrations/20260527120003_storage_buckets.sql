-- =============================================================================
-- 20260527120003_storage_buckets.sql
-- =============================================================================
-- Receipts are stored as private objects at:
--     receipts/{user_id}/{receipt_id}/{full|thumb}.jpg
--
-- The first path segment is always the owning auth.uid() — RLS leverages
-- this convention to grant access without joining tables.
--
-- Public read is intentionally OFF. The Flutter client requests a signed
-- URL (1-hour TTL) per render, which lets us pull access at any time.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Bucket
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts',
  'receipts',
  false,
  10 * 1024 * 1024,   -- 10 MiB hard cap (high-res phone JPEG ≈ 4 MiB)
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Policies on storage.objects scoped to the `receipts` bucket
-- -----------------------------------------------------------------------------
-- (storage.foldername(name))[1] = top-level folder, i.e. the owner uuid.
create policy "receipts_storage_select_own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'receipts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "receipts_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'receipts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "receipts_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'receipts'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'receipts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "receipts_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'receipts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
