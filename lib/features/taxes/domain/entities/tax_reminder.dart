import 'package:equatable/equatable.dart';

import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';

/// Which of an obligation's two deadlines a reminder is about.
///
/// Separate because filing and paying are separate acts, days apart, and a
/// reminder that conflated them would tell a user who has already filed that
/// they still have to file.
enum TaxDeadlineStep {
  declaration,
  payment;
}

/// How far ahead of the deadline a reminder fires.
///
/// Three, not one. A single day-of reminder is useless for an obligation that
/// needs a document from an accountant, and a single week-ahead one is
/// forgotten by the day it matters.
enum TaxReminderLead {
  /// A week out — enough time to ask someone for a number.
  sevenDays(7),

  /// The day before.
  oneDay(1),

  /// The morning of.
  dayOf(0);

  const TaxReminderLead(this.days);

  /// Days before the deadline.
  final int days;
}

/// One scheduled reminder, fully resolved.
///
/// [fireAt] is an **absolute instant in UTC**, already converted out of the
/// market's timezone by the planner. Nothing downstream re-interprets it, and
/// nothing downstream consults the device's zone.
class TaxReminder extends Equatable {
  const TaxReminder({
    required this.itemId,
    required this.kind,
    required this.step,
    required this.lead,
    required this.dueDate,
    required this.fireAt,
    this.title,
    this.amountMinor,
  });

  /// Local Drift row id of the obligation.
  final int itemId;

  /// Which obligation, for the notification's title.
  final TaxObligationKind kind;

  /// The user's own name, for an item they created themselves.
  final String? title;

  /// Filing or payment.
  final TaxDeadlineStep step;

  /// Which of the three reminders this is.
  final TaxReminderLead lead;

  /// The deadline itself, UTC midnight.
  final DateTime dueDate;

  /// When to fire, as an absolute instant in UTC.
  final DateTime fireAt;

  /// The amount to name in the notification, or null when there is none to
  /// name.
  ///
  /// 🚨 Null unless a person with standing said the number. The planner drops
  /// an amount whose source is anything but the accountant: a figure in a
  /// notification reads as an instruction to pay, and SmartSpend does not
  /// compute tax. See `TaxAmountSource`.
  final int? amountMinor;

  @override
  List<Object?> get props => <Object?>[
        itemId,
        kind,
        title,
        step,
        lead,
        dueDate,
        fireAt,
        amountMinor,
      ];
}
