import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/due_date_shift.dart';
import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/market/tax/tr_tax_catalog.dart';

/// A confirmed monthly obligation, so the resolution paths can be tested
/// before the real catalog has a single verified date in it.
TaxObligationSpec _confirmedMonthly({
  TaxObligationKind kind = TaxObligationKind.kdv1,
  int filingDay = 28,
  int? paymentDay = 28,
  TaxObligationEligibility eligibility = TaxObligationEligibility.everyone,
}) =>
    TaxObligationSpec(
      kind: kind,
      periodKind: TaxPeriodKind.monthly,
      periodSource: TaxPeriodSource.fixed,
      eligibility: eligibility,
      declaration: ConfirmedDueDates(
        installments: <DueRule>[
          DueRule(monthsAfterPeriodEnd: 1, day: FixedDueDay(filingDay)),
        ],
        source: 'test fixture',
      ),
      payment: paymentDay == null
          ? const NoDueDate('nothing is paid')
          : ConfirmedDueDates(
              installments: <DueRule>[
                DueRule(monthsAfterPeriodEnd: 1, day: FixedDueDay(paymentDay)),
              ],
              source: 'test fixture',
            ),
      sourceNote: 'test fixture',
    );

void main() {
  group('period enumeration', () {
    test('should produce one item per month in range', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 10, 31),
      );

      expect(calendar.obligations, hasLength(3));
      expect(
        calendar.obligations
            .map((GeneratedObligation o) => o.periodStart)
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 8),
          DateTime.utc(2026, 9),
          DateTime.utc(2026, 10),
        ],
      );
    });

    test('should close each month on its real last day', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2028, 2),
        rangeEnd: DateTime.utc(2028, 2, 29),
      );

      expect(
        calendar.obligations.single.periodEnd,
        DateTime.utc(2028, 2, 29),
        reason: '2028 is a leap year',
      );
    });

    test('should align quarters to the calendar, not to the range', () {
      // A quarter asked for from mid-February still starts in January.
      // Otherwise the same period would have different boundaries depending
      // on when the screen happened to ask, and two devices would generate
      // two different identities for it.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          const TaxObligationSpec(
            kind: TaxObligationKind.gecici,
            periodKind: TaxPeriodKind.quarterly,
            periodSource: TaxPeriodSource.fixed,
            eligibility: TaxObligationEligibility.everyone,
            declaration: UnverifiedDueDate('filing'),
            payment: UnverifiedDueDate('payment'),
            sourceNote: 'test fixture',
          ),
        ],
        rangeStart: DateTime.utc(2026, 2, 14),
        rangeEnd: DateTime.utc(2026, 5, 1),
      );

      expect(
        calendar.obligations
            .map((GeneratedObligation o) => o.periodStart)
            .toList(),
        <DateTime>[DateTime.utc(2026), DateTime.utc(2026, 4)],
      );
      expect(calendar.obligations.first.periodEnd, DateTime.utc(2026, 3, 31));
    });

    test('should cross a year end without losing a period', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2026, 11),
        rangeEnd: DateTime.utc(2027, 1, 31),
      );

      expect(
        calendar.obligations
            .map((GeneratedObligation o) => o.periodStart)
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 11),
          DateTime.utc(2026, 12),
          DateTime.utc(2027),
        ],
      );
      expect(
        calendar.obligations.last.declarationDueDate,
        DateTime.utc(2027, 2, 28),
      );
    });
  });

  group('deadlines', () {
    test('should resolve filing and payment from their own rules', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          _confirmedMonthly(filingDay: 26, paymentDay: 28),
        ],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      final GeneratedObligation item = calendar.obligations.single;
      expect(item.declarationDueDate, DateTime.utc(2026, 9, 26));
      expect(item.paymentDueDate, DateTime.utc(2026, 9, 28));
    });

    test('should leave a missing step null without calling it unverified', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly(paymentDay: null)],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      final GeneratedObligation item = calendar.obligations.single;
      expect(item.paymentDueDate, isNull);
      expect(
        item.hasUnverifiedRule,
        isFalse,
        reason: '"nothing is paid" is a fact, not a gap in our knowledge',
      );
    });

    test('should produce a dateless item for an unverified rule', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          const TaxObligationSpec(
            kind: TaxObligationKind.kdv1,
            periodKind: TaxPeriodKind.monthly,
            periodSource: TaxPeriodSource.fixed,
            eligibility: TaxObligationEligibility.everyone,
            declaration: UnverifiedDueDate('filing day'),
            payment: UnverifiedDueDate('payment day'),
            sourceNote: 'test fixture',
          ),
        ],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      final GeneratedObligation item = calendar.obligations.single;
      expect(item.declarationDueDate, isNull);
      expect(item.paymentDueDate, isNull);
      expect(item.hasUnverifiedRule, isTrue);
      expect(calendar.isPartial, isTrue);
    });

    test('should apply the deferral hook to every resolved date', () {
      // The generator does not know about weekends or holidays; it takes a
      // function that does.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
        shift: (DateTime d) => TaxDueDateShift(
          original: d,
          effective: d.add(const Duration(days: 2)),
          confidence: TaxDueDateConfidence.complete,
          reasons: const <TaxDueDateShiftReason>[
            TaxDueDateShiftReason.weekend,
          ],
        ),
      );

      final GeneratedObligation item = calendar.obligations.single;
      expect(item.declarationDueDate, DateTime.utc(2026, 9, 30));
      expect(item.dueDateConfidence, TaxDueDateConfidence.complete);
      expect(item.needsDateWarning, isFalse);
    });

    test('should carry the warning when a date could not be deferred', () {
      // The real state today: no year has a verified holiday list, so the
      // shifter hands back the raw legal date. That date must not arrive on
      // screen looking like a confirmed working day.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
        shift: shiftDueDate,
      );

      final GeneratedObligation item = calendar.obligations.single;
      expect(item.declarationDueDate, DateTime.utc(2026, 9, 28));
      expect(item.dueDateConfidence, TaxDueDateConfidence.unavailable);
      expect(item.needsDateWarning, isTrue);
    });

    test('should hedge the whole row when one of its dates is hedged', () {
      // The user reads filing and payment together; one undeferrable date
      // makes the pair untrustworthy, not just itself.
      int call = 0;
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[_confirmedMonthly()],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
        shift: (DateTime d) => TaxDueDateShift(
          original: d,
          effective: d,
          confidence: call++ == 0
              ? TaxDueDateConfidence.complete
              : TaxDueDateConfidence.partial,
          reasons: const <TaxDueDateShiftReason>[],
        ),
      );

      expect(
        calendar.obligations.single.dueDateConfidence,
        TaxDueDateConfidence.partial,
      );
    });

    test('should give one row per installment and file only on the first', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          const TaxObligationSpec(
            kind: TaxObligationKind.mtv,
            periodKind: TaxPeriodKind.annual,
            periodSource: TaxPeriodSource.fixed,
            eligibility: TaxObligationEligibility.everyone,
            declaration: ConfirmedDueDates(
              installments: <DueRule>[
                DueRule(monthsAfterPeriodEnd: 1, day: FixedDueDay(10)),
              ],
              source: 'test fixture',
            ),
            payment: ConfirmedDueDates(
              installments: <DueRule>[
                DueRule(monthsAfterPeriodEnd: 1, day: LastDayOfMonth()),
                DueRule(monthsAfterPeriodEnd: 7, day: LastDayOfMonth()),
              ],
              source: 'test fixture',
            ),
            sourceNote: 'test fixture',
          ),
        ],
        rangeStart: DateTime.utc(2026),
        rangeEnd: DateTime.utc(2026, 12, 31),
      );

      expect(calendar.obligations, hasLength(2));
      expect(calendar.obligations.first.installmentIndex, 1);
      expect(calendar.obligations.last.installmentIndex, 2);
      expect(
        calendar.obligations.first.declarationDueDate,
        DateTime.utc(2027, 1, 10),
      );
      expect(
        calendar.obligations.last.declarationDueDate,
        isNull,
        reason: 'there is one filing, not one per installment',
      );
      expect(
        calendar.obligations.map((GeneratedObligation o) => o.generationKey),
        <String>['mtv|2026-01-01|1', 'mtv|2026-01-01|2'],
      );
    });
  });

  group('the profile decides what is generated', () {
    test('should leave out what the profile rules out', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: const TaxpayerProfile(vatLiability: VatLiability.none),
        catalog: <TaxObligationSpec>[
          _confirmedMonthly(
            eligibility:
                const TaxObligationEligibility(requiresVatLiability: true),
          ),
        ],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      expect(calendar.obligations, isEmpty);
      expect(calendar.gaps, isEmpty, reason: 'ruled out is not missing');
    });

    test('should report, not guess, an unanswered recurrence', () {
      // Defaulting to monthly would put eleven invented deadlines a year in
      // front of someone who never said they file VAT.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          const TaxObligationSpec(
            kind: TaxObligationKind.kdv1,
            periodKind: TaxPeriodKind.monthly,
            periodSource: TaxPeriodSource.vatLiability,
            eligibility:
                TaxObligationEligibility(requiresVatLiability: true),
            declaration: UnverifiedDueDate('filing'),
            payment: UnverifiedDueDate('payment'),
            sourceNote: 'test fixture',
          ),
        ],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      expect(calendar.obligations, isEmpty);
      expect(calendar.gaps.single.kind, TaxObligationKind.kdv1);
      expect(
        calendar.gaps.single.reason,
        TaxCalendarGapReason.applicabilityUnknown,
      );
      expect(calendar.isPartial, isTrue);
    });

    test('should follow the answered frequency', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: const TaxpayerProfile(vatLiability: VatLiability.quarterly),
        catalog: <TaxObligationSpec>[
          const TaxObligationSpec(
            kind: TaxObligationKind.kdv1,
            periodKind: TaxPeriodKind.monthly,
            periodSource: TaxPeriodSource.vatLiability,
            eligibility:
                TaxObligationEligibility(requiresVatLiability: true),
            declaration: UnverifiedDueDate('filing'),
            payment: UnverifiedDueDate('payment'),
            sourceNote: 'test fixture',
          ),
        ],
        rangeStart: DateTime.utc(2026),
        rangeEnd: DateTime.utc(2026, 12, 31),
      );

      expect(calendar.obligations, hasLength(4));
      expect(calendar.obligations.first.periodKind, TaxPeriodKind.quarterly);
    });

    test('should keep an item whose applicability is merely unknown', () {
      // The wizard is skippable. "Might apply to you" stays visible; only an
      // answered no removes it.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: <TaxObligationSpec>[
          _confirmedMonthly(
            eligibility:
                const TaxObligationEligibility(requiresEmployer: true),
          ),
        ],
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      expect(
        calendar.obligations.single.applicability,
        TaxObligationApplicability.unknown,
      );
    });

    test('should never generate the user-defined template', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: TaxpayerProfile.empty,
        catalog: trTaxObligations,
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      expect(
        calendar.obligations
            .where((GeneratedObligation o) =>
                o.kind == TaxObligationKind.custom),
        isEmpty,
      );
    });
  });

  group('against the real catalog', () {
    test('should produce dateless items today, and say so', () {
      // Every rule in the shipped catalog is unverified, so this is the
      // honest output of the whole feature right now: real items, no dates,
      // isPartial true.
      final TaxCalendar calendar = generateTaxCalendar(
        profile: const TaxpayerProfile(
          legalForm: TaxpayerLegalForm.limited,
          vatLiability: VatLiability.monthly,
          withholdingLiability: WithholdingLiability.monthly,
          employsStaff: TaxpayerAnswer.yes,
          bagkurInsured: TaxpayerAnswer.no,
          usesELedger: TaxpayerAnswer.no,
          ownsVehicle: TaxpayerAnswer.no,
          ownsRealEstate: TaxpayerAnswer.no,
        ),
        catalog: trTaxObligations,
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      expect(calendar.obligations, isNotEmpty);
      expect(
        calendar.obligations.every(
          (GeneratedObligation o) =>
              o.declarationDueDate == null && o.paymentDueDate == null,
        ),
        isTrue,
      );
      expect(calendar.isPartial, isTrue);
    });

    test('should be deterministic — same input, same identities', () {
      TaxCalendar run() => generateTaxCalendar(
            profile: const TaxpayerProfile(
              legalForm: TaxpayerLegalForm.sahisSirketi,
              vatLiability: VatLiability.monthly,
            ),
            catalog: trTaxObligations,
            rangeStart: DateTime.utc(2026, 7),
            rangeEnd: DateTime.utc(2026, 9, 30),
          );

      // This is what lets two devices merge their calendars instead of
      // doubling them.
      expect(
        run().obligations.map((GeneratedObligation o) => o.generationKey),
        run().obligations.map((GeneratedObligation o) => o.generationKey),
      );
    });

    test('should mark KDV-2 conditional rather than assert it monthly', () {
      final TaxCalendar calendar = generateTaxCalendar(
        profile: const TaxpayerProfile(vatLiability: VatLiability.monthly),
        catalog: trTaxObligations,
        rangeStart: DateTime.utc(2026, 8),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );

      final GeneratedObligation kdv2 = calendar.obligations.firstWhere(
        (GeneratedObligation o) => o.kind == TaxObligationKind.kdv2,
      );
      expect(kdv2.isConditional, isTrue);
    });
  });
}
