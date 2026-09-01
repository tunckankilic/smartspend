import 'package:smartspend/core/market/country_profile.dart';
import 'package:smartspend/core/market/document_type.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tr_tax_catalog.dart';

/// Türkiye — the only market enabled in 2.0.0.
///
/// KDV rates as of the 2023 revision: 0%, 1% (basic foodstuffs, some
/// medicine), 10% (reduced list), 20% (general). Rates are basis points.
class TrProfile extends CountryProfile {
  const TrProfile();

  @override
  String get countryCode => 'TR';

  @override
  String get currencyCode => 'TRY';

  @override
  List<int> get vatRatesBp => const <int>[0, 100, 1000, 2000];

  @override
  int get defaultVatRateBp => 2000;

  @override
  List<DocumentType> get documentTypes => const <DocumentType>[
        DocumentType.fis,
        DocumentType.eArsivFatura,
        DocumentType.eFatura,
        DocumentType.giderPusulasi,
        DocumentType.other,
      ];

  @override
  String get defaultLanguageCode => 'tr';

  /// ⚠️ Every deadline in this catalog is unverified — see
  /// `tr_tax_catalog.dart`. The structure is settled; the dates are not.
  @override
  List<TaxObligationSpec> get taxObligations => trTaxObligations;
}
