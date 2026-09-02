import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_reminder.dart';
import 'package:smartspend/features/taxes/domain/tax_reminder_planner.dart';

/// The pure half of the reminder feature.
///
/// 🚨 Every date here comes from a fixture, never from the shipped catalog.
/// The catalog's deadlines are unverified and therefore null, so a test that
/// asked it for a date would be asserting on `null` and passing for the wrong
/// reason — and would start failing the day a real date lands.
void main() {
  late tz.Location istanbul;

  setUpAll(() {
    tz_data.initializeTimeZones();
    istanbul = tz.getLocation('Europe/Istanbul');
  });

  // Well before every deadline used below, so nothing is filtered as past
  // unless a test means it to be.
  final DateTime now = DateTime.utc(2026, 9, 1, 10);

  TaxCalendarItem item({
    int id = 1,
    TaxObligationKind kind = TaxObligationKind.kdv1,
    DateTime? declarationDue,
    DateTime? paymentDue,
    bool hasDeclarationStep = true,
    bool hasPaymentStep = true,
    DateTime? declaredAt,
    DateTime? paidAt,
    DateTime? dismissedAt,
    int? amountMinor,
    TaxAmountSource amountSource = TaxAmountSource.unknown,
    String? title,
  }) =>
      TaxCalendarItem(
        id: id,
        kind: kind,
        nameL10nKey: kind.l10nKey,
        title: title,
        periodKind: TaxPeriodKind.monthly,
        periodStart: DateTime.utc(2026, 9),
        periodEnd: DateTime.utc(2026, 9, 30),
        installmentIndex: 0,
        dueDateSource: TaxDueDateSource.catalog,
        amountSource: amountSource,
        amountMinor: amountMinor,
        hasDeclarationStep: hasDeclarationStep,
        hasPaymentStep: hasPaymentStep,
        isConditional: false,
        needsDateWarning: true,
        isUserDefined: false,
        declarationDueDate: declarationDue,
        paymentDueDate: paymentDue,
        declaredAt: declaredAt,
        paidAt: paidAt,
        dismissedAt: dismissedAt,
      );

  List<TaxReminder> plan(
    List<TaxCalendarItem> items, {
    DateTime? at,
    int maxReminders = kMaxTaxReminders,
  }) =>
      planTaxReminders(
        items: items,
        now: at ?? now,
        location: istanbul,
        maxReminders: maxReminders,
      );

  group('what produces no reminder at all', () {
    test('should stay silent for an item with no known deadline', () async {
      // This is most of the calendar today: the catalog ships unverified, so
      // the honest state of an obligation is "no date". Inventing one here
      // would tell someone a deadline they cannot miss is upon them.
      expect(plan(<TaxCalendarItem>[item()]), isEmpty);
    });

    test('should stay silent for an item the user dismissed', () {
      expect(
        plan(<TaxCalendarItem>[
          item(
            declarationDue: DateTime.utc(2026, 9, 26),
            dismissedAt: DateTime.utc(2026, 8, 1),
          ),
        ]),
        isEmpty,
      );
    });

    test('should not remind about a step the obligation does not have', () {
      // Bağ-Kur is assessed and never declared. A filing reminder for it
      // would be an instruction to do something that does not exist.
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(
          kind: TaxObligationKind.bagkur,
          hasDeclarationStep: false,
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 30),
        ),
      ]);

      expect(
        result.every((TaxReminder r) => r.step == TaxDeadlineStep.payment),
        isTrue,
      );
    });

    test('should drop the half the user has already done', () {
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 26),
          declaredAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      // Filed but not paid: the payment reminders stand, the filing ones go.
      expect(
        result.every((TaxReminder r) => r.step == TaxDeadlineStep.payment),
        isTrue,
      );
      expect(result, hasLength(3));
    });

    test('should never fire in the past', () {
      // A deadline already gone produces nothing. `overdue` is not stored and
      // is not reconstructed here either — a reminder that arrives late only
      // tells the user they failed.
      expect(
        plan(
          <TaxCalendarItem>[item(paymentDue: DateTime.utc(2026, 9, 26))],
          at: DateTime.utc(2026, 9, 27, 10),
        ),
        isEmpty,
      );
    });
  });

  group('when a reminder fires', () {
    test('should give three lead times for one deadline', () {
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(paymentDue: DateTime.utc(2026, 9, 26), hasDeclarationStep: false),
      ]);

      expect(
        result.map((TaxReminder r) => r.lead).toSet(),
        TaxReminderLead.values.toSet(),
      );
    });

    test('should fire at 09:00 in the market, not on the device', () {
      // Europe/Istanbul is UTC+3, so 09:00 there is 06:00Z. A user in Berlin
      // has the same Turkish deadline and must get the same instant.
      final TaxReminder dayOf = plan(<TaxCalendarItem>[
        item(paymentDue: DateTime.utc(2026, 9, 26), hasDeclarationStep: false),
      ]).firstWhere((TaxReminder r) => r.lead == TaxReminderLead.dayOf);

      expect(dayOf.fireAt, DateTime.utc(2026, 9, 26, 6));
      expect(dayOf.fireAt.isUtc, isTrue);
    });

    test('should cross a month boundary by calendar, not by subtraction', () {
      // A week before 3 September is 27 August, and reaching it by
      // normalising the day-of-month is what keeps it right across a DST
      // boundary — where subtracting `Duration(days: 7)` from the instant
      // would land an hour off.
      final TaxReminder week = plan(
        <TaxCalendarItem>[
          item(paymentDue: DateTime.utc(2026, 9, 3), hasDeclarationStep: false),
        ],
        at: DateTime.utc(2026, 8, 20, 10),
      ).firstWhere((TaxReminder r) => r.lead == TaxReminderLead.sevenDays);

      expect(week.fireAt, DateTime.utc(2026, 8, 27, 6));
    });

    test('should keep filing and payment apart', () {
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 30),
        ),
      ]);

      // Two separate acts, days apart. Six reminders, not three.
      expect(result, hasLength(6));
      expect(
        result
            .where((TaxReminder r) => r.step == TaxDeadlineStep.declaration)
            .map((TaxReminder r) => r.dueDate)
            .toSet(),
        <DateTime>{DateTime.utc(2026, 9, 26)},
      );
    });
  });

  group('the amount', () {
    test('should be named only when the accountant gave it', () {
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(
          paymentDue: DateTime.utc(2026, 9, 26),
          hasDeclarationStep: false,
          amountMinor: 125000,
          amountSource: TaxAmountSource.accountant,
        ),
      ]);

      expect(result.every((TaxReminder r) => r.amountMinor == 125000), isTrue);
    });

    test('should be withheld when the user typed it themselves', () {
      // Their own note to self, not a figure we checked. On a lock screen any
      // number reads as an amount due, and the app does not compute tax.
      final List<TaxReminder> result = plan(<TaxCalendarItem>[
        item(
          paymentDue: DateTime.utc(2026, 9, 26),
          hasDeclarationStep: false,
          amountMinor: 125000,
          amountSource: TaxAmountSource.user,
        ),
      ]);

      expect(result.every((TaxReminder r) => r.amountMinor == null), isTrue);
    });
  });

  test('should produce the same plan twice for the same calendar', () {
    // The scheduler decides whether to touch the OS by comparing the new plan
    // against the last one it scheduled. If planning were not deterministic,
    // that comparison would never match and every tick would cancel and
    // rewrite every reminder.
    final List<TaxCalendarItem> calendar = <TaxCalendarItem>[
      item(id: 1, paymentDue: DateTime.utc(2026, 9, 26)),
      item(id: 2, declarationDue: DateTime.utc(2026, 9, 26)),
    ];

    expect(plan(calendar), equals(plan(calendar)));
  });

  group('the iOS pending-notification budget', () {
    test('should spend it on the soonest deadlines', () {
      // 🚨 iOS silently drops pending local notifications past 64, and not
      // the ones you would choose. Two obligations, six reminders each, a
      // budget of four: the four that survive must be the earliest.
      final List<TaxReminder> result = plan(
        <TaxCalendarItem>[
          item(
            id: 1,
            paymentDue: DateTime.utc(2026, 12, 20),
            hasDeclarationStep: false,
          ),
          item(
            id: 2,
            paymentDue: DateTime.utc(2026, 9, 26),
            hasDeclarationStep: false,
          ),
        ],
        maxReminders: 4,
      );

      expect(result, hasLength(4));
      expect(
        result.take(3).every((TaxReminder r) => r.itemId == 2),
        isTrue,
        reason: 'September must outrank December',
      );
      final List<DateTime> sorted =
          result.map((TaxReminder r) => r.fireAt).toList()..sort();
      expect(result.map((TaxReminder r) => r.fireAt), orderedEquals(sorted));
    });
  });
}
