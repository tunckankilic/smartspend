import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smartspend/core/database/daos/budget_dao.dart';
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/database/daos/sync_log_dao.dart';
import 'package:smartspend/core/database/daos/tag_dao.dart';
import 'package:smartspend/core/database/daos/user_correction_dao.dart';
import 'package:smartspend/core/database/default_categories.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

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
  ],
  daos: <Type>[
    ReceiptDao,
    ExpenseDao,
    BudgetDao,
    CategoryDao,
    SyncLogDao,
    TagDao,
    UserCorrectionDao,
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
  @override
  int get schemaVersion => 2;

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
        },
      );

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
