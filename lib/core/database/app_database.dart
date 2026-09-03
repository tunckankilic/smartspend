import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smartspend/core/database/daos/budget_dao.dart';
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/product_event_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/database/daos/sync_dao.dart';
import 'package:smartspend/core/database/daos/sync_log_dao.dart';
import 'package:smartspend/core/database/daos/tag_dao.dart';
import 'package:smartspend/core/database/daos/tax_calendar_override_dao.dart';
import 'package:smartspend/core/database/daos/tax_obligation_dao.dart';
import 'package:smartspend/core/database/daos/tax_profile_dao.dart';
import 'package:smartspend/core/database/daos/user_correction_dao.dart';
import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/database/default_categories.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';
import 'package:smartspend/core/services/tax_reminder_scheduler.dart';
import 'package:smartspend/core/services/telemetry_service_impl.dart';

part 'app_database.g.dart';

/// SmartSpend's local persistence layer.
///
/// Drift owns offline-first reads. Repositories read Drift unconditionally
/// and let `SyncService` (Sprint 8) reconcile with Supabase in the
/// background. Writes go to Drift first with `pending_*` status; the sync
/// engine drains the queue when the network is available.
@DriftDatabase(
  tables: <Type>[
    Receipts,
    ReceiptItems,
    Categories,
    Expenses,
    Budgets,
    BudgetAlerts,
    Tags,
    ExpenseTags,
    UserSettings,
    SyncLog,
    UserCorrections,
    SyncConflictPayloads,
    SyncDeferredRows,
    ProductEventCounters,
    TaxProfiles,
    TaxObligations,
    TaxCalendarOverrides,
  ],
  daos: <Type>[
    ReceiptDao,
    ExpenseDao,
    BudgetDao,
    CategoryDao,
    SyncDao,
    SyncLogDao,
    TagDao,
    UserCorrectionDao,
    UserSettingsDao,
    ProductEventDao,
    TaxProfileDao,
    TaxObligationDao,
    TaxCalendarOverrideDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test-only ctor — caller supplies an in-memory [NativeDatabase].
  AppDatabase.forTesting(super.executor);

  /// Schema history:
  ///   v1 — Sprint 1 initial set (receipts, expenses, budgets, ...).
  ///   v2 — Sprint 6 adds `user_corrections` to persist the per-user
  ///        category-override learning signal that Sprint 4 was logging
  ///        only via the structured logger.
  ///   v3 — Sprint 7 adds `receipts.warranty_end_date` for the receipt
  ///        archive's warranty-reminder feature. Nullable; older rows
  ///        upgrade with `null` and behave as "no warranty".
  ///   v4 — Sprint 9 adds covering indexes on the list-screen hot paths:
  ///        `expenses.date`, `expenses.category_id`, and `receipts.date`.
  ///        No data change; pure read-performance migration.
  ///   v5 — 1.3.0 adds the two tables that stop `pull()` from dropping
  ///        remote rows on the floor. `sync_conflict_payloads` keeps the
  ///        version last-write-wins discards; `sync_deferred_rows` keeps the
  ///        ones skipped because a parent had not arrived, which the pull
  ///        loop used to `continue` past before advancing the watermark past
  ///        them for good. Additive tables only, so v4 data upgrades
  ///        untouched.
  ///   v6 — 1.3.0 Block 3 adds `product_event_counters`, the device-local
  ///        half of product telemetry. Additive table only. Note that v5 was
  ///        never published: 1.3.0 is the first release to carry either of
  ///        these tables, so no device can ever upgrade *from* v5 and there is
  ///        no v5 snapshot to test against — `v4.sql` remains the only real
  ///        starting point, and the v4 → v6 chain is what a real device runs.
  ///   v7 — 1.3.0 Block 4 adds the tax calendar's own tables. Additive only.
  ///        v5, v6 and v7 are all unpublished, so the same reasoning applies:
  ///        `v4.sql` is still the only snapshot that describes a schema a real
  ///        device can be sitting on, and v4 → v7 is the one upgrade path that
  ///        has to work.
  ///   v8 — 1.3.0 Block 4 (T10) adds `tax_calendar_overrides`, the local copy
  ///        of the server's deadline corrections. Additive, unpublished like
  ///        v5–v7, and empty on every device until the first pull — an
  ///        override that has not been fetched is simply absent, and the
  ///        calendar shows the catalog date it would have shown anyway.
  ///
  /// Every published version (1.0.0 through 1.2.1) ships schema v4 — the
  /// v1→v4 steps all landed pre-release — so `from == 4` is the only upgrade
  /// path a real device can take into 1.3.0. `migration_v4_to_v8_test.dart`
  /// exercises it against a snapshot of the real v4 schema.
  @override
  int get schemaVersion => 8;

  /// Store `DateTime` columns as ISO-8601 text so timezone information
  /// survives a write/read round-trip. CLAUDE.md mandates UTC storage; the
  /// default unix-timestamp mode silently converts to the device's local TZ
  /// on read.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _seedDefaultCategories();
        },
        // Step-by-step migrations get plugged in here as `schemaVersion` grows.
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 → v2: add user_corrections table (Sprint 6).
          if (from < 2) {
            await m.createTable(userCorrections);
          }
          // v2 → v3: add receipts.warranty_end_date (Sprint 7). Nullable
          // column so existing rows survive the upgrade with no default.
          if (from < 3) {
            await m.addColumn(receipts, receipts.warrantyEndDate);
          }
          // v3 → v4: create the Sprint 9 read-path indexes on existing
          // installs (fresh installs get them via createAll).
          if (from < 4) {
            await m.create(idxExpensesDate);
            await m.create(idxExpensesCategory);
            await m.create(idxReceiptsDate);
          }
          // v4 → v5: add sync_conflict_payloads (1.3.0). Purely additive —
          // no existing row is read or rewritten, so an interrupted upgrade
          // cannot corrupt user data.
          if (from < 5) {
            await m.createTable(syncConflictPayloads);
            await m.createTable(syncDeferredRows);
          }
          // v5 → v6: add product_event_counters (1.3.0, Block 3). Additive,
          // and the table starts empty on every device — telemetry counts
          // forward from the upgrade, it does not backfill history it never
          // observed.
          if (from < 6) {
            await m.createTable(productEventCounters);
          }
          // v6 → v7: add the tax calendar tables (1.3.0, Block 4). Additive,
          // and both start empty: the calendar is generated from the user's
          // profile after the upgrade, never backfilled for periods that
          // passed before the feature existed.
          if (from < 7) {
            await m.createTable(taxProfiles);
            await m.createTable(taxObligations);
          }
          // v7 → v8: add tax_calendar_overrides (1.3.0, Block 4, T10).
          // Additive, and it starts empty on every device: overrides are
          // pulled, never backfilled. An empty table means the generator
          // applies nothing and the calendar shows catalog dates — the exact
          // behaviour of a build without the feature.
          if (from < 8) {
            await m.createTable(taxCalendarOverrides);
          }
        },
      );

  /// Wipes every user-owned row on sign-out so the next account starts from
  /// a clean local cache. The global seed categories (`userId == null`,
  /// non-custom) are preserved so the app still has its category set, and
  /// device-local [UserSettings] (theme / locale) survive a session change.
  /// Children are deleted before parents to respect foreign keys.
  Future<void> clearUserData() async {
    await transaction(() async {
      await delete(expenseTags).go();
      await delete(receiptItems).go();
      await delete(budgetAlerts).go();
      await delete(userCorrections).go();
      await delete(expenses).go();
      await delete(budgets).go();
      await delete(receipts).go();
      await delete(tags).go();
      await delete(syncLog).go();
      // Quarantined conflict payloads and deferred rows hold the user's own
      // financial rows as raw JSON, so they leave with the rest of the
      // account's data.
      await delete(syncConflictPayloads).go();
      await delete(syncDeferredRows).go();
      // Telemetry counters describe the departing account's behaviour and
      // must not travel into the next one signed in on this device.
      await delete(productEventCounters).go();
      // The taxpayer profile is the most identifying row the app holds: legal
      // form, whether they employ anyone, what they own. It leaves with the
      // account together with the calendar generated from it, and for the same
      // reason the financial rows do — the next person to sign in on this
      // phone must not inherit someone else's deadlines, or the notes and
      // amounts they wrote against them.
      await delete(taxObligations).go();
      await delete(taxProfiles).go();
      // taxCalendarOverrides is deliberately NOT cleared. It holds no personal
      // data — a filing extension is published regulatory fact, the same for
      // everyone — and dropping it would leave the next account showing stale
      // catalog dates until its first successful pull, for no privacy gain.
      //
      // 🚨 The reminder fingerprint DOES go, and not for privacy: sign-out
      // cancels the scheduled notifications, so a surviving fingerprint would
      // tell the scheduler its work was already done and the same user signing
      // back in would silently never get their reminders again.
      await (delete(userSettings)
            ..where(
              ($UserSettingsTable t) =>
                  t.key.equals(kTaxRemindersFingerprintKey),
            ))
          .go();

      // Reset the pull watermark so the next sign-in performs a full pull.
      // lastSyncAt lives in userSettings, not the data tables wiped above; if
      // it survived, the next session's incremental pull
      // (`updated_at > lastSyncAt`) would return nothing and the dashboard
      // would stay empty until a remote row happened to change. Theme/locale
      // keys in userSettings are left untouched.
      await (delete(userSettings)
            ..where((UserSettings t) => t.key.equals(SyncDao.kLastSyncAtKey)))
          .go();
      // Rotate the telemetry install id. It is device-local, not account
      // data, so it *could* survive — but then two accounts used on this
      // phone would share a device_id on the server, and anyone reading that
      // table could tell they were the same person's device. Rotating costs
      // nothing: each account's rows already carry their own absolute counts,
      // so a fresh id starts a fresh row and the server-side sum stays
      // correct. The opt-out preference is deliberately NOT cleared — a user
      // who switched telemetry off should not find it back on after signing
      // out.
      await (delete(userSettings)
            ..where(
              (UserSettings t) =>
                  t.key.equals(TelemetryServiceImpl.kDeviceIdKey),
            ))
          .go();
      await (delete(categories)
            ..where(
              (Categories t) => t.userId.isNotNull() | t.isCustom.equals(true),
            ))
          .go();
    });
  }

  Future<void> _seedDefaultCategories() async {
    final DateTime now = DateTime.now().toUtc();
    await batch((Batch batch) {
      batch.insertAll(
        categories,
        kDefaultCategories
            .map(
              (DefaultCategoryDefinition c) => CategoriesCompanion.insert(
                remoteId: Value<String?>(c.remoteId),
                userId: const Value<String?>(null),
                name: c.name,
                icon: c.icon,
                color: c.color,
                isCustom: const Value<bool>(false),
                sortOrder: Value<int>(c.sortOrder),
                updatedAt: now,
                syncStatus: const Value<String>(SyncStatus.synced),
              ),
            )
            .toList(),
      );
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dbFolder = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dbFolder.path, 'smartspend.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
