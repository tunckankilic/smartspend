-- Drift schema snapshot: v4.
--
-- This is the schema every shipped SmartSpend carries. It is not "the 1.2.0
-- schema" by coincidence: `schemaVersion` has been 4 since before 1.0.0 hit
-- the App Store (v1→v2, v2→v3 and v3→v4 all landed during Sprints 6/7/9,
-- pre-release), and `tables.dart` is byte-identical across 1.0.0, 1.0.1,
-- 1.1.0, 1.2.0 and 1.2.1. So a device upgrading to 1.3.0 from ANY published
-- version starts here, and this one file covers the whole install base.
--
-- Captured from `AppDatabase` at commit c44d5f6 (the last v4 commit) by
-- dumping `sqlite_master` from a freshly created in-memory database.
--
-- `sqlite_sequence` is deliberately absent: SQLite creates it on its own for
-- AUTOINCREMENT tables and executing its DDL by hand is an error.
--
-- Used by `migration_v4_to_v5_test.dart` to build a genuine v4 database and
-- run the real migration against it. Do not edit to match a newer schema —
-- that is the one change that would make the migration test stop testing
-- anything. New schema versions get their own snapshot file.

CREATE TABLE "budget_alerts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "budget_id" INTEGER NOT NULL REFERENCES budgets (id), "threshold_percent" INTEGER NOT NULL, "is_triggered" INTEGER NOT NULL DEFAULT 0 CHECK ("is_triggered" IN (0, 1)), "triggered_at" TEXT NULL, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "budgets" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "category_id" INTEGER NULL REFERENCES categories (id), "amount" INTEGER NOT NULL, "period" TEXT NOT NULL, "start_date" TEXT NOT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "name" TEXT NOT NULL, "icon" TEXT NOT NULL, "color" INTEGER NOT NULL, "is_custom" INTEGER NOT NULL DEFAULT 0 CHECK ("is_custom" IN (0, 1)), "sort_order" INTEGER NOT NULL DEFAULT 0, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "expense_tags" ("expense_id" INTEGER NOT NULL REFERENCES expenses (id), "tag_id" INTEGER NOT NULL REFERENCES tags (id), "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced', PRIMARY KEY ("expense_id", "tag_id"));
CREATE TABLE "expenses" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "amount" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "receipt_id" INTEGER NULL REFERENCES receipts (id), "note" TEXT NULL, "date" TEXT NOT NULL, "is_manual" INTEGER NOT NULL DEFAULT 1 CHECK ("is_manual" IN (0, 1)), "is_recurring" INTEGER NOT NULL DEFAULT 0 CHECK ("is_recurring" IN (0, 1)), "recurring_period" TEXT NULL, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "receipt_items" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "receipt_id" INTEGER NOT NULL REFERENCES receipts (id), "name" TEXT NOT NULL, "quantity" REAL NOT NULL DEFAULT 1.0, "unit_price" INTEGER NOT NULL, "total_price" INTEGER NOT NULL, "category_id" INTEGER NULL REFERENCES categories (id), "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "receipts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "store_name" TEXT NULL, "date" TEXT NOT NULL, "total" INTEGER NOT NULL, "currency" TEXT NOT NULL DEFAULT 'TRY', "image_path" TEXT NULL, "storage_object_path" TEXT NULL, "raw_ocr_text" TEXT NULL, "confidence_score" REAL NULL, "warranty_end_date" TEXT NULL, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "sync_log" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" TEXT NULL, "table_name" TEXT NOT NULL, "record_id" TEXT NOT NULL, "operation" TEXT NOT NULL, "attempted_at" TEXT NOT NULL, "success" INTEGER NOT NULL CHECK ("success" IN (0, 1)), "error_message" TEXT NULL);
CREATE TABLE "tags" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "name" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "user_corrections" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "remote_id" TEXT NULL, "user_id" TEXT NULL, "store_name" TEXT NOT NULL, "old_category_id" INTEGER NULL REFERENCES categories (id), "new_category_id" INTEGER NOT NULL REFERENCES categories (id), "count" INTEGER NOT NULL DEFAULT 1, "occurred_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'synced');
CREATE TABLE "user_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, "updated_at" TEXT NOT NULL, PRIMARY KEY ("key"));
CREATE INDEX idx_expenses_category ON expenses (category_id);
CREATE INDEX idx_expenses_date ON expenses (date);
CREATE INDEX idx_receipts_date ON receipts (date);
