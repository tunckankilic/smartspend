import 'package:equatable/equatable.dart';

import 'package:smartspend/features/budget/domain/entities/budget_period.dart';

/// A user-configured spending cap.
///
/// `categoryId == null` is the **general** budget — applies to every
/// expense in the matching window. Sprint 6 only allows one active
/// general budget + one per category, but the model doesn't enforce
/// that (BudgetBloc does on create).
///
/// Monetary amounts are integers in **minor units** (kuruş for TRY,
/// cents otherwise). Dates are UTC; the presentation layer formats
/// them in the device's locale.
class Budget extends Equatable {
  const Budget({
    required this.id,
    required this.amountMinor,
    required this.period,
    required this.startDate,
    required this.isActive,
    this.categoryId,
    this.currency = 'TRY',
    this.isPendingSync = false,
  });

  /// Local Drift PK.
  final int id;

  /// Spending cap in minor units. Always positive — the create use case
  /// rejects zero/negative amounts.
  final int amountMinor;

  /// Currency code (ISO 4217). Sprint 6 hard-codes TRY; Sprint 7 will
  /// read this from `user_settings.default_currency`.
  final String currency;

  /// Reset cadence.
  final BudgetPeriod period;

  /// Anchor instant. The current-period window is computed relative to
  /// this (e.g. monthly budgets anchor on `startDate.day`).
  final DateTime startDate;

  /// Soft-active flag. Deactivated budgets are kept in the table for
  /// historical reports but excluded from the active list.
  final bool isActive;

  /// `null` = general / total budget. Otherwise targets a single
  /// category id.
  final int? categoryId;

  /// `true` when the row is queued for the Supabase sync engine (Sprint
  /// 8). Surface this in the UI so users know a write is in flight.
  final bool isPendingSync;

  bool get isGeneral => categoryId == null;

  Budget copyWith({
    int? id,
    int? amountMinor,
    String? currency,
    BudgetPeriod? period,
    DateTime? startDate,
    bool? isActive,
    int? categoryId,
    bool? clearCategory,
    bool? isPendingSync,
  }) {
    return Budget(
      id: id ?? this.id,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      period: period ?? this.period,
      startDate: startDate ?? this.startDate,
      isActive: isActive ?? this.isActive,
      categoryId:
          (clearCategory ?? false) ? null : (categoryId ?? this.categoryId),
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        amountMinor,
        currency,
        period,
        startDate,
        isActive,
        categoryId,
        isPendingSync,
      ];
}
