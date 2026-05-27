import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';

/// Contract for the expenses feature's data access.
///
/// Implementations live in `data/`. Per Sprint 3 prompt: read-side calls
/// always come from Drift (offline-first); write-side calls mutate Drift
/// with a `pending_*` sync status — the background sync worker (Sprint 8)
/// pushes those rows to Supabase later.
abstract class ExpenseRepository {
  /// Snapshot read for the list view, filtered + sorted.
  Future<Either<Failure, List<Expense>>> getExpenses(ExpenseFilter filter);

  /// Reactive stream — re-emits whenever the underlying expenses or
  /// categories tables change. The list page subscribes via the bloc to
  /// stay in sync with scan-flow saves and recurring-expense generation.
  Stream<List<Expense>> watchExpenses(ExpenseFilter filter);

  /// Single-row read for the detail page.
  Future<Either<Failure, Expense?>> getExpenseById(int id);

  /// Aggregated totals for the matched window.
  Future<Either<Failure, ExpenseSummary>> getSummary(ExpenseFilter filter);

  /// Insert a manual expense (Sprint 3.2). Returns the local Drift PK.
  ///
  /// The row is stamped `pending_create`; the sync engine (Sprint 8)
  /// pushes it upstream later. Tag names are resolved (or created) and
  /// linked atomically with the insert.
  Future<Either<Failure, int>> addExpense({
    required int amount,
    required int categoryId,
    required DateTime date,
    required bool isManual,
    String? note,
    int? receiptId,
    bool isRecurring = false,
    String? recurringPeriod,
    List<String> tags = const <String>[],
  });

  /// Update an existing expense — stamps `pending_update`.
  ///
  /// Passing [tags] (even an empty list) **replaces** the row's tag set;
  /// pass `null` to leave tags untouched.
  Future<Either<Failure, void>> updateExpense({
    required int id,
    int? amount,
    int? categoryId,
    DateTime? date,
    String? note,
    bool clearNote = false,
    bool? isRecurring,
    String? recurringPeriod,
    bool clearRecurringPeriod = false,
    List<String>? tags,
  });

  /// All tag names a user has typed so far — used to autocomplete the
  /// Sprint 3.2 chip input. Sorted alphabetically.
  Future<Either<Failure, List<String>>> getAllTagNames();

  /// Soft-delete — sets `sync_status = 'pending_delete'`. The list
  /// repository filters these out automatically; sync worker hard-deletes
  /// after the remote acknowledges.
  Future<Either<Failure, void>> deleteExpense(int id);
}
