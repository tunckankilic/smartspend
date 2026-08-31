// coverage:ignore-file
// Drift schema declarations consumed by the code generator, not executable
// unit-test logic. Exercised indirectly by every DAO test through the
// generated database.
import 'package:drift/drift.dart';

import 'package:smartspend/core/database/sync_status.dart';

// ---------------------------------------------------------------------------
// Conventions
// ---------------------------------------------------------------------------
// * Monetary amounts are integers in *minor units* (kuruş for TRY, cents for
//   EUR/USD). Never use real/double for money.
// * Timestamps are stored as UTC `DateTime`; display layer converts to the
//   user's locale.
// * Every syncable table carries: `remoteId`, `userId`, `syncStatus`,
//   `updatedAt`. Local-only tables (`UserSettings`, `SyncLog`,
//   `SyncConflictPayloads`) skip the sync columns by design.
// * Drift's code generator inspects this file via `app_database.dart`'s
//   `@DriftDatabase` annotation. Keep ordering stable to minimize diff churn
//   in generated code.

@TableIndex(name: 'idx_receipts_date', columns: <Symbol>{#date})
class Receipts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get storeName => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get total => integer()();
  TextColumn get currency => text().withDefault(const Constant('TRY'))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get storageObjectPath => text().nullable()();
  TextColumn get rawOcrText => text().nullable()();
  RealColumn get confidenceScore => real().nullable()();
  /// Sprint 7 — receipt archive warranty tracking. UTC end-of-warranty
  /// date; null for receipts without an attached warranty. The reminder
  /// notification fires 30 days before this date (see
  /// `AddWarrantyUseCase`).
  DateTimeColumn get warrantyEndDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class ReceiptItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  IntColumn get receiptId => integer().references(Receipts, #id)();
  TextColumn get name => text()();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  IntColumn get unitPrice => integer()();
  IntColumn get totalPrice => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

@TableIndex(name: 'idx_expenses_date', columns: <Symbol>{#date})
@TableIndex(name: 'idx_expenses_category', columns: <Symbol>{#categoryId})
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  IntColumn get amount => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get receiptId => integer().nullable().references(Receipts, #id)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get isManual => boolean().withDefault(const Constant(true))();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurringPeriod => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amount => integer()();
  TextColumn get period => text()(); // weekly | monthly
  DateTimeColumn get startDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class BudgetAlerts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  IntColumn get budgetId => integer().references(Budgets, #id)();
  IntColumn get thresholdPercent => integer()();
  BoolColumn get isTriggered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get triggeredAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

class ExpenseTags extends Table {
  IntColumn get expenseId => integer().references(Expenses, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{expenseId, tagId};
}

/// Local-only key/value preferences (theme, locale, last-sync timestamp).
/// Not synced to Supabase — the server keeps a row-shaped `user_settings`
/// table for cross-device prefs; Drift holds device-local state.
class UserSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Records each time the user overrides the categorizer's suggestion for a
/// given store. The hybrid engine (Sprint 4) consults the highest-count row
/// for a store name before falling back to the keyword/TFLite engines, so
/// the categorizer "learns" per-user mappings.
///
/// Sprint 6 introduces this table (schema v2). Sprint 8 will push it to
/// Supabase via the standard `syncStatus` pipeline.
class UserCorrections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get storeName => text()();
  IntColumn get oldCategoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get newCategoryId => integer().references(Categories, #id)();
  IntColumn get count => integer().withDefault(const Constant(1))();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.synced))();
}

/// Audit trail of sync attempts — debugging only, never synced.
///
/// Note: Drift's [Table] base class exposes a `String? get tableName` used
/// internally to resolve the SQL table identifier. Declaring a `TextColumn`
/// with the same Dart name collides with that getter and fails to compile.
/// We keep the SQL column called `table_name` (matches the Supabase
/// `sync_log` migration in Sprint 8) but expose it in Dart as
/// `logTableName`. The DAO surface still accepts a `tableName:` parameter
/// so callers never see this quirk.
class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().nullable()();
  TextColumn get logTableName => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get operation => text()();
  DateTimeColumn get attemptedAt => dateTime()();
  BoolColumn get success => boolean()();
  TextColumn get errorMessage => text().nullable()();
}

/// Quarantine for the remote version that last-write-wins threw away.
///
/// When a pulled row is not newer than the local copy, every
/// `SyncDao.apply*FromRemote` keeps local and returns `false`. Before 1.3.0
/// that decision was silent in the worst way: `sync_log` recorded *that* a
/// conflict happened, but the losing data itself was never written anywhere.
/// One user with two devices could lose an edit made on the other device and
/// have no way to see it, let alone get it back.
///
/// This table is the receipt for that decision. It keeps the remote row
/// exactly as it arrived ([remotePayload], raw JSON) together with both
/// sides' `updated_at`, so 1.4.0's conflict screen can show what was
/// discarded and offer to replay it. 1.3.0 only stops the loss — it does not
/// resolve anything.
///
/// Local-only and never pushed: this is forensic state about *this device's*
/// sync decisions, so it deliberately carries no sync columns. It does carry
/// [userId], because the payload holds the user's own financial data and has
/// to be wiped on sign-out with everything else (`AppDatabase.clearUserData`).
///
/// Like [SyncLog], the SQL column is `table_name` while the Dart getter is
/// `conflictTableName`: Drift's [Table] base class already defines
/// `tableName` and redeclaring it fails to compile.
class SyncConflictPayloads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().nullable()();
  TextColumn get conflictTableName => text().named('table_name')();

  /// The losing row's Supabase UUID.
  TextColumn get remoteId => text()();

  /// The remote row as raw JSON, exactly as `fetchSince` returned it —
  /// unmapped, so foreign keys are still remote UUIDs rather than local ids.
  TextColumn get remotePayload => text()();

  /// `updated_at` of the local row that won.
  DateTimeColumn get localUpdatedAt => dateTime()();

  /// `updated_at` of the remote row that lost.
  DateTimeColumn get remoteUpdatedAt => dateTime()();

  /// When this device noticed the conflict (UTC).
  DateTimeColumn get detectedAt => dateTime()();
}
