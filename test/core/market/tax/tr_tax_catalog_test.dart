import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/country_profile.dart';
import 'package:smartspend/core/market/document_type.dart';
import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/market/tax/tr_tax_catalog.dart';
import 'package:smartspend/core/market/tr_profile.dart';

void main() {
  group('trTaxObligations', () {
    test('should cover every obligation kind exactly once', () {
      final List<TaxObligationKind> kinds = trTaxObligations
          .map((TaxObligationSpec spec) => spec.kind)
          .toList();

      expect(kinds.toSet().length, kinds.length, reason: 'duplicate entry');
      expect(kinds.toSet(), TaxObligationKind.values.toSet());
    });

    test('should be what the Turkish profile hands out', () {
      const CountryProfile profile = TrProfile();

      expect(profile.taxObligations, same(trTaxObligations));
    });

    test('should leave other markets without a calendar', () {
      // A market whose deadlines nobody has verified generates nothing. That
      // is the correct output, not a degraded one.
      expect(_UnresearchedProfile().taxObligations, isEmpty);
    });
  });

  group('honesty invariants', () {
    test('should mark every unconfirmed entry so the work is one grep', () {
      for (final TaxObligationSpec spec in trTaxObligations) {
        if (spec.isVerified) {
          continue;
        }
        expect(
          spec.sourceNote,
          contains(kUnverifiedMarker),
          reason: '${spec.kind.wireValue} has unconfirmed deadlines but its '
              'source note does not say so',
        );
      }
    });

    test('should never carry a confirmed deadline without its source', () {
      // The guard that survives verification: once someone replaces an
      // UnverifiedDueDate with real numbers, those numbers have to name where
      // they came from and cannot be an empty installment list.
      for (final TaxObligationSpec spec in trTaxObligations) {
        for (final DueSchedule schedule in <DueSchedule>[
          spec.declaration,
          spec.payment,
        ]) {
          if (schedule is! ConfirmedDueDates) {
            continue;
          }
          expect(
            schedule.installments,
            isNotEmpty,
            reason: '${spec.kind.wireValue} claims confirmed deadlines but '
                'lists no installment',
          );
          expect(
            schedule.source.trim(),
            isNotEmpty,
            reason: '${spec.kind.wireValue} confirms a deadline without '
                'naming a source',
          );
        }
      }
    });

    test('should explain every structurally missing deadline', () {
      for (final TaxObligationSpec spec in trTaxObligations) {
        for (final DueSchedule schedule in <DueSchedule>[
          spec.declaration,
          spec.payment,
        ]) {
          if (schedule is NoDueDate) {
            expect(schedule.reason.trim(), isNotEmpty);
          }
        }
      }
    });

    test('should keep the three known one-sided obligations one-sided', () {
      // Bağ-Kur is assessed, not declared; Ba/Bs and the e-ledger berat are
      // filed and never paid. Modelling either side as a single "due date"
      // would make these three lie, so they are pinned.
      expect(_spec(TaxObligationKind.bagkur).declaration, isA<NoDueDate>());
      expect(_spec(TaxObligationKind.babs).payment, isA<NoDueDate>());
      expect(
        _spec(TaxObligationKind.edefterBerat).payment,
        isA<NoDueDate>(),
      );
    });

    test('should mark KDV-2 as conditional rather than every-period', () {
      expect(
        _spec(TaxObligationKind.kdv2).occursOnlyWhenTransactionsExist,
        isTrue,
      );
      final Iterable<TaxObligationSpec> conditional = trTaxObligations.where(
        (TaxObligationSpec spec) => spec.occursOnlyWhenTransactionsExist,
      );
      expect(
        conditional.map((TaxObligationSpec spec) => spec.kind),
        <TaxObligationKind>[TaxObligationKind.kdv2],
      );
    });

    test('should keep the custom entry out of generated calendars', () {
      final Iterable<TaxObligationSpec> userDefined = trTaxObligations
          .where((TaxObligationSpec spec) => spec.isUserDefined);

      expect(
        userDefined.map((TaxObligationSpec spec) => spec.kind),
        <TaxObligationKind>[TaxObligationKind.custom],
      );
      expect(
        _spec(TaxObligationKind.custom).periodSource,
        TaxPeriodSource.userDefined,
      );
    });
  });

  group('applicability', () {
    test('should be unknown, not absent, for an untouched profile', () {
      // The wizard is skippable. Everything a blank profile cannot rule out
      // has to stay visible as "might apply to you".
      final Iterable<TaxObligationSpec> generated = trTaxObligations
          .where((TaxObligationSpec spec) => !spec.isUserDefined);

      for (final TaxObligationSpec spec in generated) {
        expect(
          spec.eligibility.evaluate(TaxpayerProfile.empty),
          TaxObligationApplicability.unknown,
          reason: '${spec.kind.wireValue} decided something from no answers',
        );
      }
    });

    test('should keep a sole proprietor out of corporate filings', () {
      const TaxpayerProfile soleTrader = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.sahisSirketi,
      );

      expect(
        _spec(TaxObligationKind.kurumlar).eligibility.evaluate(soleTrader),
        TaxObligationApplicability.doesNotApply,
      );
      expect(
        _spec(TaxObligationKind.basitUsul).eligibility.evaluate(soleTrader),
        TaxObligationApplicability.doesNotApply,
      );
    });

    test('should drop the whole calendar of a taxpayer who owes nothing', () {
      const TaxpayerProfile nothing = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.basitUsul,
        vatLiability: VatLiability.none,
        withholdingLiability: WithholdingLiability.none,
        employsStaff: TaxpayerAnswer.no,
        bagkurInsured: TaxpayerAnswer.no,
        usesELedger: TaxpayerAnswer.no,
        ownsVehicle: TaxpayerAnswer.no,
        ownsRealEstate: TaxpayerAnswer.no,
      );

      final Iterable<TaxObligationSpec> applying = trTaxObligations.where(
        (TaxObligationSpec spec) =>
            !spec.isUserDefined &&
            spec.eligibility.evaluate(nothing) !=
                TaxObligationApplicability.doesNotApply,
      );

      expect(
        applying.map((TaxObligationSpec spec) => spec.kind),
        <TaxObligationKind>[TaxObligationKind.basitUsul],
      );
    });
  });

  group('localisation', () {
    for (final String locale in <String>['tr', 'en', 'de']) {
      test('should name every obligation in $locale', () {
        final Map<String, dynamic> arb = jsonDecode(
          File('lib/l10n/app_$locale.arb').readAsStringSync(),
        ) as Map<String, dynamic>;

        for (final TaxObligationKind kind in TaxObligationKind.values) {
          expect(
            arb.containsKey(kind.l10nKey),
            isTrue,
            reason: '${kind.l10nKey} is missing from app_$locale.arb',
          );
          expect((arb[kind.l10nKey] as String).trim(), isNotEmpty);
        }
      });
    }

    test('should give every obligation its own key', () {
      final Set<String> keys = TaxObligationKind.values
          .map((TaxObligationKind kind) => kind.l10nKey)
          .toSet();

      expect(keys.length, TaxObligationKind.values.length);
    });
  });
}

TaxObligationSpec _spec(TaxObligationKind kind) => trTaxObligations
    .firstWhere((TaxObligationSpec spec) => spec.kind == kind);

class _UnresearchedProfile extends CountryProfile {
  @override
  String get countryCode => 'XX';

  @override
  String get currencyCode => 'XXX';

  @override
  List<int> get vatRatesBp => const <int>[0];

  @override
  int get defaultVatRateBp => 0;

  @override
  List<DocumentType> get documentTypes => const <DocumentType>[];

  @override
  String get defaultLanguageCode => 'en';
}
