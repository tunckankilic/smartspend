-- =============================================================================
-- 20260529120000_exports_bucket.sql
-- =============================================================================
-- CSV exports produced by the `export-csv` Edge Function are written to:
--     exports/{user_id}/{timestamp}.csv
--
-- Same convention as the `receipts` bucket: the first path segment is the
-- owning auth.uid(), so RLS grants access without joining tables. Private
-- bucket — the client only ever receives a short-lived (24h) signed URL.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'exports',
  'exports',
  false,
  50 * 1024 * 1024,   -- 50 MiB; a CSV of years of expenses stays well under.
  array['text/csv']
)
on conflict (id) do nothing;

create policy "exports_storage_select_own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'exports'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "exports_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'exports'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "exports_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'exports'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'exports'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "exports_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'exports'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
