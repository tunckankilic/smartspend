/// The closed vocabulary of tax and payment obligations SmartSpend can put on
/// a calendar.
///
/// Adding a value here is the only way to add an obligation, for the same
/// reason `ProductEvent` is closed: the set is small, it is persisted, and a
/// free-form string would let a typo create a second, silent category.
///
/// The names are Turkish because they name Turkish filings that have no clean
/// English equivalent; each doc comment carries the gloss. Markets other than
/// TR declare their own subset — no value here is assumed to exist elsewhere.
library;

/// One kind of recurring obligation.
enum TaxObligationKind {
  /// KDV-1 — the VAT return a seller files on their own turnover.
  kdv1('kdv1', 'taxObligationKdv1'),

  /// KDV-2 — the VAT return a *buyer* files for withheld (tevkifatlı) VAT.
  /// Only exists in periods with such a transaction.
  kdv2('kdv2', 'taxObligationKdv2'),

  /// MPHB — muhtasar ve prim hizmet beyannamesi, the combined withholding and
  /// SGK service declaration.
  mphb('mphb', 'taxObligationMphb'),

  /// SGK 4/a — the employer's social-security premium payment for staff.
  sgk4a('sgk4a', 'taxObligationSgk4a'),

  /// Bağ-Kur (4/b) — the self-employed person's own premium. Payment only:
  /// there is no declaration step.
  bagkur('bagkur', 'taxObligationBagkur'),

  /// Geçici vergi — quarterly advance income/corporate tax.
  gecici('gecici', 'taxObligationGecici'),

  /// Yıllık gelir vergisi — the annual personal income tax return.
  yillikGv('yillik_gv', 'taxObligationYillikGv'),

  /// Kurumlar vergisi — the annual corporate tax return.
  kurumlar('kurumlar', 'taxObligationKurumlar'),

  /// Damga vergisi — stamp duty, for taxpayers with a continuous liability.
  damga('damga', 'taxObligationDamga'),

  /// Basit usul — the annual return of the simplified regime.
  basitUsul('basit_usul', 'taxObligationBasitUsul'),

  /// e-Defter beratı — the ledger seal uploaded to GİB. Filing only: nothing
  /// is paid.
  edefterBerat('edefter_berat', 'taxObligationEdefterBerat'),

  /// Form Ba/Bs — the purchase and sales listings. Filing only.
  babs('babs', 'taxObligationBabs'),

  /// MTV — motorlu taşıtlar vergisi, paid in installments. No declaration.
  mtv('mtv', 'taxObligationMtv'),

  /// Emlak vergisi — property tax, paid in installments. No declaration.
  emlak('emlak', 'taxObligationEmlak'),

  /// A deadline the user added themselves (4b/T9). Never generated from a
  /// profile; it exists here so a user-defined row has a kind to persist.
  custom('custom', 'taxObligationCustom');

  const TaxObligationKind(this.wireValue, this.l10nKey);

  /// Stable persisted identifier, written to Drift and Supabase. Never rename:
  /// renaming orphans every row a user has already marked as declared or paid.
  final String wireValue;

  /// The ARB key holding this obligation's display name.
  ///
  /// A test asserts the key exists in all three locales, which is what makes
  /// this field worth carrying rather than the presentation layer's switch
  /// being the only place the name lives.
  final String l10nKey;

  /// Parses a persisted [wireValue].
  ///
  /// Returns [custom] for anything this build does not know: a newer client
  /// may have written a kind an older one cannot name, and the row must stay
  /// readable and editable rather than vanishing from the user's calendar.
  static TaxObligationKind fromWireValue(String? value) {
    for (final TaxObligationKind kind in TaxObligationKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return TaxObligationKind.custom;
  }
}
