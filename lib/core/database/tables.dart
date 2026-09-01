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
//   `SyncConflictPayloads`, `SyncDeferredRows`) skip the sync columns by
//   design.
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

/// Remote rows this device pulled but could not apply yet, because a parent
/// row they reference is not here.
///
/// Distinct from [SyncConflictPayloads] on purpose. A conflict is two devices
/// disagreeing about the same row, and a human eventually has to pick. This
/// is not a disagreement: the row is perfectly good, it simply arrived before
/// its parent. Filing the two together would put rows in 1.4.0's resolution
/// screen that the user cannot resolve — the only fix is for the parent to
/// show up.
///
/// Why it has to be recorded at all: `pull()` used to `continue` past these,
/// and then advanced `last_sync_at` to now. The next `fetchSince` asks for
/// `updated_at > now`, so the skipped row was never offered again unless
/// something touched it remotely. It is still safe on the server, but this
/// device had stopped asking for it. That is a quieter loss than the conflict
/// one — a conflict at least leaves the newer local row in place, while an
/// orphan leaves nothing.
///
/// 1.3.0 only records them. Replaying a deferred row once its parent lands is
/// 1.4.0's job, which is why [missingParentTable] and
/// [missingParentRemoteId] are stored: the retry needs to know what it is
/// waiting for.
///
/// Local-only, no sync columns. Same `table_name` naming dance as [SyncLog].
class SyncDeferredRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().nullable()();
  TextColumn get deferredTableName => text().named('table_name')();

  /// The unapplied row's Supabase UUID.
  TextColumn get remoteId => text()();

  /// The row as raw JSON, exactly as `fetchSince` returned it.
  TextColumn get remotePayload => text()();

  /// `updated_at` of the row we could not apply.
  DateTimeColumn get remoteUpdatedAt => dateTime()();

  /// Which table the missing parent lives in (`receipts`, `categories`).
  TextColumn get missingParentTable => text()();

  /// The missing parent's remote UUID. Null when the payload carried no
  /// parent reference at all, which should not happen for a NOT NULL remote
  /// column but is recorded rather than assumed away.
  TextColumn get missingParentRemoteId => text().nullable()();

  /// When this device noticed (UTC).
  DateTimeColumn get detectedAt => dateTime()();
}

/// Per-day, per-event product telemetry counters (1.3.0, Block 3).
///
/// 1.3.0's point is not the tax calendar, it is learning: D-2 (who the ICP
/// actually is) is currently answered by two competing guesses, and this is
/// the table that replaces them with evidence.
///
/// WHAT IT MAY NEVER HOLD — counters and closed-vocabulary categorical values
/// only. No free text, no amounts, no document content. That is enforced by
/// construction rather than by review:
///   * [eventKey] is written only from the `ProductEvent` enum and
///     [dimension] only from `TelemetryDimension`, so the compiler rejects a
///     store name or an OCR line at the call site;
///   * the server repeats the guarantee independently with regex CHECK
///     constraints, so a bug on this side still cannot get a phrase through;
///   * there is no amount column, so a lira value has nowhere to land.
/// A scrubber would be the last line of defence. The design is that the event
/// never carries the data in the first place.
///
/// WHY [count] IS ABSOLUTE, NOT A DELTA (D-14) — the sync engine is
/// last-write-wins, and a counter under last-write-wins loses increments
/// whenever two devices count the same day. The fix is that the device is part
/// of the server's unique key `(user_id, device_id, event_key, dimension,
/// day)`: this row holds the total THIS device has observed, the upload
/// overwrites only this device's row, and readers `sum()` across devices.
/// Overwrite is therefore correct, and re-sending the same value is a no-op —
/// which is what makes upload retries, lost responses and duplicated batches
/// harmless without any delta bookkeeping.
///
/// [day] is a `YYYY-MM-DD` string derived from UTC, not a `DateTime`. It is a
/// bucket label, not a timestamp, and keeping it textual means the unique key
/// cannot drift with date formatting or timezone conversion. Per-occurrence
/// timestamps are deliberately absent: they would turn a counter into a
/// timeline of what the user did and when.
///
/// `device_id` is not stored here. It is a property of the install, not of the
/// row, so it lives once in [UserSettings] and is stamped at upload time.
class ProductEventCounters extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();

  /// NULL for the whole of 1.3.0 — the company (space) model lands in 1.4.0.
  /// Carried now under CLAUDE.md's stated exception so the 1.4.0 backfill has
  /// a column to write into.
  TextColumn get companyId => text().nullable()();

  /// A `ProductEvent.key`. Never a caller-supplied string.
  TextColumn get eventKey => text()();

  /// A `TelemetryDimension.value`, or `''` for events without a breakdown.
  ///
  /// Empty string rather than NULL on purpose: the server's ON CONFLICT
  /// target includes this column, and Postgres treats NULLs as distinct, so a
  /// nullable dimension would let the same counter insert twice instead of
  /// updating — quietly reintroducing the double-count this design exists to
  /// prevent. The local unique key mirrors the server's for the same reason.
  TextColumn get dimension => text().withDefault(const Constant(''))();

  /// UTC calendar day, `YYYY-MM-DD`.
  TextColumn get day => text()();

  /// Absolute occurrences observed on this device for this key/day.
  IntColumn get count => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.pendingCreate))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{eventKey, dimension, day},
      ];
}
