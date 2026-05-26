import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: <Type>[Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// Default (seeded) + custom categories, ordered by `sortOrder`.
  Future<List<Category>> getAll() {
    return (select(categories)
          ..orderBy(<OrderClauseGenerator<$CategoriesTable>>[
            ($CategoriesTable t) => OrderingTerm(expression: t.sortOrder),
          ]))
        .get();
  }

  /// Global default categories (userId is NULL).
  Future<List<Category>> getDefaults() {
    return (select(categories)
          ..where(($CategoriesTable t) => t.userId.isNull())
          ..orderBy(<OrderClauseGenerator<$CategoriesTable>>[
            ($CategoriesTable t) => OrderingTerm(expression: t.sortOrder),
          ]))
        .get();
  }

  /// User-defined categories. Always paired with a [userId].
  Future<List<Category>> getCustomForUser(String userId) {
    return (select(categories)
          ..where(
            ($CategoriesTable t) =>
                t.userId.equals(userId) & t.isCustom.equals(true),
          ))
        .get();
  }

  Future<Category?> getById(int id) {
    return (select(categories)..where(($CategoriesTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertCustom(CategoriesCompanion entry) {
    return into(categories).insert(
      entry.copyWith(
        isCustom: const Value<bool>(true),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  Future<int> updateCategory(int id, CategoriesCompanion patch) {
    return (update(categories)
          ..where(($CategoriesTable t) => t.id.equals(id)))
        .write(
      patch.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingUpdate),
      ),
    );
  }

  Future<List<Category>> getPendingSync() {
    return (select(categories)
          ..where(
            ($CategoriesTable t) => t.syncStatus.isIn(SyncStatus.pending),
          ))
        .get();
  }
}
