-- Sprint 7 — Receipt Archive: warranty tracking.
--
-- Adds a nullable `warranty_end_date` column to `public.receipts` so users
-- can record the warranty expiry on a receipt and get a local notification
-- 30 days before it lapses.
--
-- Notes:
--   * Local Drift schema mirrors this in v3 (see lib/core/database/app_database.dart).
--   * RLS policies on `public.receipts` (initial migration) already cover
--     this column — no policy changes required.
--   * No index needed: the column is queried only when rendering a single
--     receipt detail page and the receipts table is already user-id indexed.

alter table public.receipts
  add column if not exists warranty_end_date date;

comment on column public.receipts.warranty_end_date is
  'Optional warranty expiry (date, no timezone). UI schedules a local '
  'reminder 30 days before this date.';
