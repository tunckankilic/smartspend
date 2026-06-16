import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';

/// Adapters between the Drift row, Supabase JSON shape, and the domain
/// [Expense] entity.
///
/// All mappers are `static` — Drift rows are value objects so there's no
/// state to instantiate. The Sprint 8 sync worker will use [toSupabase]
/// when it lands; for now only [fromDriftRow] is on the hot path.
abstract class ExpenseModel {
  ExpenseModel._();

  /// Build a domain [Expense] from a Drift row.
  ///
  /// * [category] — already-loaded category snapshot (the repository
  ///   batches this lookup so the mapper stays sync).
  /// * [currency] — currency to attach to the expense. Scan-flow rows
  ///   inherit it from the parent receipt; manual rows default to TRY
  ///   until Sprint 5 wires user settings.
  static Expense fromDriftRow(
    drift_db.Expense row, {
    required Category category,
    required String currency,
    List<String> tags = const <String>[],
  }) {
    return Expense(
      id: row.id,
      amount: row.amount,
      category: category,
      receiptId: row.receiptId,
      note: row.note,
      date: row.date,
      currency: currency,
      isManual: row.isManual,
      isRecurring: row.isRecurring,
      recurringPeriod: RecurringPeriod.fromName(row.recurringPeriod),
      isPendingSync: SyncStatus.pending.contains(row.syncStatus),
      tags: tags,
    );
  }
}
