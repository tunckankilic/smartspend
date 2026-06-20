-- =============================================================================
-- 20260620120000_exports_bucket_allow_pdf.sql
-- =============================================================================
-- The `exports` bucket was created allowing only `text/csv`
-- (20260529120000_exports_bucket.sql), but the `export-pdf` Edge Function
-- uploads `application/pdf`. Storage enforces `allowed_mime_types` on upload,
-- so PDF exports failed with a STORAGE_ERROR before a signed URL was ever
-- produced. Widen the allow-list to cover both export formats.
-- =============================================================================

update storage.buckets
set allowed_mime_types = array['text/csv', 'application/pdf']
where id = 'exports';
