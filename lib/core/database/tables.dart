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

/// The taxpayer's answers to the eight profile questions (1.3.0, Block 4).
///
/// One row per user — and, from 1.4.0, one per company. The calendar is
/// generated from this row plus the market catalog, so this table is the whole
/// input to the tax feature: no other user data reaches the generator.
///
/// WHY EVERY ANSWER IS NULLABLE TEXT — the wizard is skippable by design. It
/// is also the instrument that answers D-2, and a form that refuses to advance
/// without an answer measures nothing except who tolerates forms. Every column
/// therefore has an "unknown" wire value rather than a NOT NULL constraint,
/// and an unanswered question produces a partial calendar rather than an
/// error. The values are the `wireValue`s of the enums in
/// `lib/core/market/tax/taxpayer_profile.dart`; unrecognised text read back
/// (a row written by a newer client) degrades to "unknown" rather than
/// throwing, which keeps a downgraded install usable.
///
/// WHY THERE IS NO "IS COMPLETE" COLUMN — completeness is a property of the
/// eight answers and is derived on read. Storing it would let it disagree with
/// them, and under last-write-wins the disagreement would sync.
class TaxProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();

  /// NULL for the whole of 1.3.0 — the company (space) model lands in 1.4.0.
  /// Carried now under CLAUDE.md's stated exception so the 1.4.0 backfill has
  /// a column to write into.
  TextColumn get companyId => text().nullable()();

  /// `TaxpayerLegalForm.wireValue`.
  TextColumn get legalForm =>
      text().withDefault(const Constant('belirtilmedi'))();

  /// `VatLiability.wireValue`.
  TextColumn get vatLiability =>
      text().withDefault(const Constant('unknown'))();

  /// `WithholdingLiability.wireValue`.
  TextColumn get withholdingLiability =>
      text().withDefault(const Constant('unknown'))();

  /// `TaxpayerAnswer.wireValue` — employs staff (SGK 4/a employer).
  TextColumn get employsStaff =>
      text().withDefault(const Constant('unknown'))();

  /// `TaxpayerAnswer.wireValue` — pays Bağ-Kur (4/b) personally.
  TextColumn get bagkurInsured =>
      text().withDefault(const Constant('unknown'))();

  /// `TaxpayerAnswer.wireValue` — keeps books as e-Defter.
  TextColumn get usesELedger =>
      text().withDefault(const Constant('unknown'))();

  /// `TaxpayerAnswer.wireValue` — owns a vehicle.
  TextColumn get ownsVehicle =>
      text().withDefault(const Constant('unknown'))();

  /// `TaxpayerAnswer.wireValue` — owns real estate.
  TextColumn get ownsRealEstate =>
      text().withDefault(const Constant('unknown'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.pendingCreate))();
}

/// One instance of one obligation — "the KDV return for August 2026".
///
/// Generated from [TaxProfiles] × the market catalog, then annotated by the
/// user. The generation is deterministic and repeatable, which is why
/// [generationKey] exists: two devices generating the same calendar must
/// produce the same identity for the same item, or the user ends up with the
/// August return twice.
///
/// WHY TWO DUE DATES — filing and payment are separate deadlines and for much
/// of the Turkish catalog they differ. Some obligations have only one of them:
/// Bağ-Kur is assessed and never declared; Ba/Bs listings and the e-ledger
/// berat are declared and never paid. A single "due date" column would make
/// roughly a third of the calendar lie. Both are nullable — an obligation
/// whose rule is not confirmed yet has no date at all, and showing nothing
/// beats showing a guess.
///
/// WHY TWO TIMESTAMPS — filing and paying are separate acts that happen days
/// apart, and "I filed it" must not mark it paid.
///
/// 🚨 WHY THERE IS NO `overdue` COLUMN — because it is a function of the due
/// date and the current time, and both are already here. Storing it would
/// mean a device with a wrong clock, or one that has not synced for a week,
/// computes "overdue" and then *propagates* it: last-write-wins would hand
/// that verdict to every other device, and the user would be told they missed
/// a deadline they did not miss. Derived state stays derived. A test pins the
/// column's absence.
///
/// 🚨 WHY [amountSource] HAS NO `computed` — SmartSpend does not calculate
/// tax. Every amount here was typed by a person; see [TaxAmountSource].
class TaxObligations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text().nullable()();

  /// NULL for the whole of 1.3.0 — see [TaxProfiles.companyId].
  TextColumn get companyId => text().nullable()();

  /// Stable identity of this item within the user's calendar:
  /// `kind|periodStart|installment` for generated rows, a random id for
  /// user-created ones.
  ///
  /// Regeneration matches on this rather than on the row id, so re-running
  /// the generator updates the August return instead of adding a second one —
  /// and so does a pull from a device that generated it independently.
  TextColumn get generationKey => text()();

  /// A `TaxObligationKind.wireValue`.
  TextColumn get kind => text()();

  /// A `TaxPeriodKind.wireValue`.
  TextColumn get periodKind => text()();

  /// First and last day of the period this item covers, UTC.
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();

  /// 0 for a single payment; 1, 2, … for an obligation paid in installments.
  IntColumn get installmentIndex => integer().withDefault(const Constant(0))();

  /// Filing deadline. NULL where the obligation has no filing step, and also
  /// where the catalog rule is not confirmed yet — the UI distinguishes the
  /// two from [kind], and says so rather than inventing a date.
  DateTimeColumn get declarationDueDate => dateTime().nullable()();

  /// Payment deadline. NULL under the same two conditions.
  DateTimeColumn get paymentDueDate => dateTime().nullable()();

  /// A `TaxDueDateSource.wireValue` — shown to the user as a badge.
  TextColumn get dueDateSource =>
      text().withDefault(const Constant('catalog'))();

  /// Amount in the smallest currency unit (kuruş), or NULL when nobody has
  /// said. Nullable is the normal state: the app never fills this in.
  IntColumn get amountMinor => integer().nullable()();

  /// A `TaxAmountSource.wireValue`. Never `computed` — the value does not
  /// exist.
  TextColumn get amountSource =>
      text().withDefault(const Constant('unknown'))();

  /// When the user marked it filed. Separate from [paidAt] on purpose.
  DateTimeColumn get declaredAt => dateTime().nullable()();

  /// When the user marked it paid.
  DateTimeColumn get paidAt => dateTime().nullable()();

  /// When the user said this item does not apply to them.
  ///
  /// A timestamp rather than a boolean: it is also the strongest signal that
  /// the generated calendar is wrong for this taxpayer, and knowing *when*
  /// they dismissed it is what makes that signal readable later.
  DateTimeColumn get dismissedAt => dateTime().nullable()();

  /// The user's own note.
  TextColumn get note => text().nullable()();

  /// Display name for a user-created item; NULL for generated ones, which are
  /// named from the catalog's l10n key so the name follows the app language.
  TextColumn get title => text().nullable()();

  /// True for items the user added themselves; the generator never touches
  /// these.
  BoolColumn get isUserDefined =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(SyncStatus.pendingCreate))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{generationKey},
      ];
}
