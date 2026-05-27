import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'tag_dao.g.dart';

/// CRUD for [Tags] and the [ExpenseTags] join.
///
/// Sprint 3.2 wires this so the manual-entry form can attach free-form
/// labels to an expense. Tag rows are deduped by name (case-insensitive)
/// so typing "kahve" twice doesn't create two rows.
@DriftAccessor(tables: <Type>[Tags, ExpenseTags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  // ---------------------------------------------------------------------
  // Tag rows
  // ---------------------------------------------------------------------

  Future<List<Tag>> getAll() {
    return (select(tags)
          ..orderBy(<OrderClauseGenerator<$TagsTable>>[
            ($TagsTable t) => OrderingTerm(expression: t.name),
          ]))
        .get();
  }

  /// Look up a tag by trimmed lower-cased name. Returns `null` if absent.
  Future<Tag?> findByName(String name) {
    final String needle = name.trim().toLowerCase();
    return (select(tags)
          ..where(($TagsTable t) => t.name.lower().equals(needle))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Find-or-create. Returns the row's local id; the row's sync status is
  /// stamped `pending_create` when inserted.
  Future<int> findOrCreate(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'cannot be empty');
    }
    final Tag? existing = await findByName(trimmed);
    if (existing != null) return existing.id;
    return into(tags).insert(
      TagsCompanion.insert(
        name: trimmed,
        updatedAt: DateTime.now().toUtc(),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Join table
  // ---------------------------------------------------------------------

  /// All tags linked to [expenseId]. Empty when none.
  Future<List<Tag>> getForExpense(int expenseId) async {
    final JoinedSelectStatement<HasResultSet, dynamic> q = select(tags).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(
          expenseTags,
          expenseTags.tagId.equalsExp(tags.id),
        ),
      ],
    )..where(expenseTags.expenseId.equals(expenseId));
    final List<TypedResult> rows = await q.get();
    return rows.map((TypedResult r) => r.readTable(tags)).toList();
  }

  /// Batched lookup — returns `expenseId → sorted-tag-names` for every id
  /// in [expenseIds]. Ids with no tags are absent from the map (callers
  /// should treat that as an empty list).
  Future<Map<int, List<String>>> getTagsForExpenseIds(
    List<int> expenseIds,
  ) async {
    if (expenseIds.isEmpty) return <int, List<String>>{};
    final JoinedSelectStatement<HasResultSet, dynamic> q = select(tags).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(
          expenseTags,
          expenseTags.tagId.equalsExp(tags.id),
        ),
      ],
    )..where(expenseTags.expenseId.isIn(expenseIds));
    final List<TypedResult> rows = await q.get();
    final Map<int, List<String>> out = <int, List<String>>{};
    for (final TypedResult r in rows) {
      final Tag tag = r.readTable(tags);
      final ExpenseTag link = r.readTable(expenseTags);
      out.putIfAbsent(link.expenseId, () => <String>[]).add(tag.name);
    }
    for (final List<String> list in out.values) {
      list.sort((String a, String b) =>
          a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return out;
  }

  /// Replace the tag set linked to [expenseId] with [tagIds]. Idempotent.
  ///
  /// Removes obsolete links, inserts new ones. Existing links are left
  /// untouched (sync status preserved) so repeated saves don't flap the
  /// sync queue.
  Future<void> setTagsForExpense(int expenseId, Set<int> tagIds) async {
    final List<ExpenseTag> current = await (select(expenseTags)
          ..where(($ExpenseTagsTable t) => t.expenseId.equals(expenseId)))
        .get();
    final Set<int> existing = current.map((ExpenseTag e) => e.tagId).toSet();
    final Set<int> toDelete = existing.difference(tagIds);
    final Set<int> toInsert = tagIds.difference(existing);

    if (toDelete.isNotEmpty) {
      await (delete(expenseTags)
            ..where(
              ($ExpenseTagsTable t) =>
                  t.expenseId.equals(expenseId) &
                  t.tagId.isIn(toDelete.toList()),
            ))
          .go();
    }
    if (toInsert.isEmpty) return;
    final DateTime now = DateTime.now().toUtc();
    await batch((Batch batch) {
      batch.insertAll(
        expenseTags,
        toInsert.map(
          (int tagId) => ExpenseTagsCompanion.insert(
            expenseId: expenseId,
            tagId: tagId,
            updatedAt: now,
            syncStatus: const Value<String>(SyncStatus.pendingCreate),
          ),
        ),
      );
    });
  }

  /// Convenience — find-or-create each name and then attach via
  /// [setTagsForExpense]. Returns the resolved tag ids.
  Future<Set<int>> resolveAndAttach(
    int expenseId,
    Iterable<String> tagNames,
  ) async {
    final Set<int> ids = <int>{};
    for (final String name in tagNames) {
      final String trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      ids.add(await findOrCreate(trimmed));
    }
    await setTagsForExpense(expenseId, ids);
    return ids;
  }
}
