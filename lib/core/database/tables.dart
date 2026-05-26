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
//   `updatedAt`. Local-only tables (`UserSettings`, `SyncLog`) skip the sync
//   columns by design.
// * Drift's code generator inspects this file via `app_database.dart`'s
//   `@DriftDatabase` annotation. Keep ordering stable to minimize diff churn
//   in generated code.

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
