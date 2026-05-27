part of 'add_expense_bloc.dart';

sealed class AddExpenseEvent extends Equatable {
  const AddExpenseEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Initialize the form for **adding** a new expense. Pulls the latest
/// category list + previously-used tag names.
final class AddExpenseStarted extends AddExpenseEvent {
  const AddExpenseStarted();
}

/// Initialize the form for **editing** [expense]. Same boot path as
/// [AddExpenseStarted] but seeds the field controllers from the row.
final class AddExpenseEditStarted extends AddExpenseEvent {
  const AddExpenseEditStarted({required this.expense});

  final Expense expense;

  @override
  List<Object?> get props => <Object?>[expense];
}

/// Amount field — caller passes the raw input string; the bloc parses it
/// via [parseMinorInput] so validation stays in one place.
final class AddExpenseAmountChanged extends AddExpenseEvent {
  const AddExpenseAmountChanged({required this.input});

  final String input;

  @override
  List<Object?> get props => <Object?>[input];
}

final class AddExpenseCategorySelected extends AddExpenseEvent {
  const AddExpenseCategorySelected({required this.category});

  final Category category;

  @override
  List<Object?> get props => <Object?>[category];
}

/// Push a freshly created category onto the bloc's local list so the
/// inline "+ new category" flow can keep the picker accurate without a
/// round-trip through the repository.
final class AddExpenseCategoryCreated extends AddExpenseEvent {
  const AddExpenseCategoryCreated({required this.category});

  final Category category;

  @override
  List<Object?> get props => <Object?>[category];
}

final class AddExpenseDateSelected extends AddExpenseEvent {
  const AddExpenseDateSelected({required this.date});

  final DateTime date;

  @override
  List<Object?> get props => <Object?>[date];
}

final class AddExpenseNoteChanged extends AddExpenseEvent {
  const AddExpenseNoteChanged({required this.note});

  final String note;

  @override
  List<Object?> get props => <Object?>[note];
}

final class AddExpenseTagAdded extends AddExpenseEvent {
  const AddExpenseTagAdded({required this.tag});

  final String tag;

  @override
  List<Object?> get props => <Object?>[tag];
}

final class AddExpenseTagRemoved extends AddExpenseEvent {
  const AddExpenseTagRemoved({required this.tag});

  final String tag;

  @override
  List<Object?> get props => <Object?>[tag];
}

final class AddExpenseRecurringToggled extends AddExpenseEvent {
  const AddExpenseRecurringToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => <Object?>[value];
}

final class AddExpensePeriodChanged extends AddExpenseEvent {
  const AddExpensePeriodChanged({required this.period});

  final RecurringPeriod period;

  @override
  List<Object?> get props => <Object?>[period];
}

/// Save the current form. Triggers validation; on success the bloc
/// transitions to [AddExpenseSaved] and the page pops.
final class AddExpenseSubmitted extends AddExpenseEvent {
  const AddExpenseSubmitted();
}
