part of 'budget_bloc.dart';

/// Inbound events for [BudgetBloc]. Past-tense per CLAUDE.md.
sealed class BudgetEvent extends Equatable {
  const BudgetEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Open both Drift watch streams — fired by the page on first mount.
/// Idempotent: re-subscribing tears down the previous streams.
final class BudgetSubscribed extends BudgetEvent {
  const BudgetSubscribed();
}

/// User submitted the "add budget" bottom sheet. The bloc validates,
/// inserts via [CreateBudgetUseCase], and waits for the Drift stream
/// tick to refresh the UI — no eager state emission.
final class BudgetCreated extends BudgetEvent {
  const BudgetCreated({
    required this.amountMinor,
    required this.period,
    required this.startDate,
    this.categoryId,
  });

  final int amountMinor;
  final BudgetPeriod period;
  final DateTime startDate;

  /// `null` = general / total budget.
  final int? categoryId;

  @override
  List<Object?> get props =>
      <Object?>[amountMinor, period, startDate, categoryId];
}

/// User edited an existing budget. `null` fields mean "leave unchanged".
final class BudgetUpdated extends BudgetEvent {
  const BudgetUpdated({
    required this.id,
    this.amountMinor,
    this.period,
    this.startDate,
    this.isActive,
  });

  final int id;
  final int? amountMinor;
  final BudgetPeriod? period;
  final DateTime? startDate;
  final bool? isActive;

  @override
  List<Object?> get props =>
      <Object?>[id, amountMinor, period, startDate, isActive];
}

/// User swiped a budget tile (or hit the trash icon in the edit sheet).
/// Soft-deletes via [DeleteBudgetUseCase].
final class BudgetDeleted extends BudgetEvent {
  const BudgetDeleted({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}

/// User tapped the "enable notifications" banner. Surfaces the system
/// permission prompt via [NotificationService.requestPermissions].
final class BudgetPermissionRequested extends BudgetEvent {
  const BudgetPermissionRequested();
}

/// Internal: budgets stream emitted. Private so widgets can't dispatch.
final class _BudgetsTicked extends BudgetEvent {
  const _BudgetsTicked();
}

/// Internal: expenses stream emitted.
final class _ExpensesTicked extends BudgetEvent {
  const _ExpensesTicked();
}

/// Internal: one of the watch streams blew up. Surfaces as
/// [BudgetError].
final class _StreamErrored extends BudgetEvent {
  const _StreamErrored(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
