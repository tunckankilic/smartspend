import 'package:smartspend/features/expenses/domain/entities/expense.dart';

/// Coarse-grain buckets the list page uses for the sticky group headers.
enum ExpenseGroupKey {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  earlier;

  /// Resolve the bucket [date] (UTC) falls into relative to [now] (UTC).
  static ExpenseGroupKey resolve(DateTime date, {DateTime? now}) {
    final DateTime ref = (now ?? DateTime.now().toUtc()).toUtc();
    final DateTime today = DateTime.utc(ref.year, ref.month, ref.day);
    final DateTime day = DateTime.utc(date.year, date.month, date.day);
    final int diff = today.difference(day).inDays;

    if (diff <= 0) return ExpenseGroupKey.today;
    if (diff == 1) return ExpenseGroupKey.yesterday;
    if (diff < 7) return ExpenseGroupKey.thisWeek;
    if (day.year == today.year && day.month == today.month) {
      return ExpenseGroupKey.thisMonth;
    }
    return ExpenseGroupKey.earlier;
  }
}

/// Convenience record — list page builds a flat list of these from the
/// repository's sorted result so the [ListView] doesn't have to nest.
class ExpenseGroup {
  const ExpenseGroup({required this.key, required this.expenses});

  final ExpenseGroupKey key;
  final List<Expense> expenses;
}

/// Group [expenses] (assumed sorted newest-first) into header buckets,
/// preserving the input order inside each bucket.
List<ExpenseGroup> groupByDate(
  List<Expense> expenses, {
  DateTime? now,
}) {
  if (expenses.isEmpty) return const <ExpenseGroup>[];
  final Map<ExpenseGroupKey, List<Expense>> buckets =
      <ExpenseGroupKey, List<Expense>>{};
  for (final Expense e in expenses) {
    final ExpenseGroupKey k = ExpenseGroupKey.resolve(e.date, now: now);
    buckets.putIfAbsent(k, () => <Expense>[]).add(e);
  }
  // Stable order: today → yesterday → thisWeek → thisMonth → earlier.
  return ExpenseGroupKey.values
      .where(buckets.containsKey)
      .map((ExpenseGroupKey k) => ExpenseGroup(key: k, expenses: buckets[k]!))
      .toList(growable: false);
}
