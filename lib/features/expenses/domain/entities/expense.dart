import 'package:equatable/equatable.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';

/// A single expense row.
///
/// Sprint 2.3's receipt-save flow writes one [Expense] per receipt line
/// item, so the list view is naturally line-grained (good for category
/// analytics). Manual entries (Sprint 3.2) create a single row with
/// [isManual] = `true` and no [receiptId].
///
/// Money fields are integers in **minor units** (kuruş for TRY, cents
/// otherwise). Dates are UTC; the presentation layer formats them in the
/// device's locale.
class Expense extends Equatable {
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    required this.currency,
    required this.isManual,
    required this.isRecurring,
    required this.isPendingSync,
    this.receiptId,
    this.note,
    this.recurringPeriod,
    this.tags = const <String>[],
  });

  /// Local Drift PK.
  final int id;

  /// Amount in minor units. Always non-negative; SmartSpend doesn't model
  /// refunds as negative numbers (it stores a refund as a separate row in
  /// a future sprint).
  final int amount;

  /// Denormalized snapshot of the row's category. Repositories build this
  /// by joining `expenses` → `categories` so the UI can render the icon
  /// and name without a second query.
  final Category category;

  /// Receipt this expense came from, or `null` for manual entries.
  final int? receiptId;

  /// Free-form note. Scan-flow expenses inherit the receipt-item name
  /// here so the list still has a meaningful label.
  final String? note;

  /// Expense date — same as the parent receipt date when there is one.
  final DateTime date;

  /// ISO-4217 currency. Sprint 3 reads this from the parent receipt when
  /// available, else falls back to the user's default (TRY for now;
  /// `user_settings` lands in Sprint 5).
  final String currency;

  /// Set by the AddExpense flow (Sprint 3.2). `false` for scan-flow rows.
  final bool isManual;

  final bool isRecurring;

  /// `null` unless [isRecurring] is `true`.
  final RecurringPeriod? recurringPeriod;

  /// `true` when this row hasn't yet been pushed to Supabase
  /// (`pending_create` / `pending_update` / `pending_delete`). The list
  /// shows a small clock badge for these.
  final bool isPendingSync;

  /// Free-form labels attached via Sprint 3.2's chip input. Always
  /// sorted alphabetically by the repository so equality is stable.
  final List<String> tags;

  Expense copyWith({
    int? id,
    int? amount,
    Category? category,
    int? receiptId,
    String? note,
    DateTime? date,
    String? currency,
    bool? isManual,
    bool? isRecurring,
    RecurringPeriod? recurringPeriod,
    bool? isPendingSync,
    List<String>? tags,
    bool clearReceipt = false,
    bool clearNote = false,
    bool clearRecurringPeriod = false,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      receiptId: clearReceipt ? null : (receiptId ?? this.receiptId),
      note: clearNote ? null : (note ?? this.note),
      date: date ?? this.date,
      currency: currency ?? this.currency,
      isManual: isManual ?? this.isManual,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPeriod: clearRecurringPeriod
          ? null
          : (recurringPeriod ?? this.recurringPeriod),
      isPendingSync: isPendingSync ?? this.isPendingSync,
      tags: tags ?? this.tags,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        amount,
        category,
        receiptId,
        note,
        date,
        currency,
        isManual,
        isRecurring,
        recurringPeriod,
        isPendingSync,
        tags,
      ];
}
