/// Kinds of accounting document SmartSpend can hold.
///
/// The set is the union across every market: each [CountryProfile] declares
/// the subset it supports (`documentTypes`). New markets add values here and
/// list them in their own profile — TR code never has to change.
///
/// [wireValue] is the string persisted in Drift and Supabase (`documents
/// .doc_type`, Faz 5) and must stay stable once a row exists.
enum DocumentType {
  /// Cash-register receipt (TR: fiş).
  fis('fis'),

  /// e-Arşiv fatura — invoice issued electronically to a non-e-invoice payer.
  eArsivFatura('eArsivFatura'),

  /// e-Fatura — invoice exchanged between registered e-invoice taxpayers.
  eFatura('eFatura'),

  /// Gider pusulası — expense voucher for purchases from non-taxpayers.
  giderPusulasi('giderPusulasi'),

  /// Anything the market does not model explicitly.
  other('other');

  const DocumentType(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted [wireValue] back to a [DocumentType].
  ///
  /// Returns [DocumentType.other] for values this build does not know — a
  /// newer client may have written a type an older one cannot name, and the
  /// row must still be readable.
  static DocumentType fromWireValue(String? value) {
    for (final DocumentType type in DocumentType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return DocumentType.other;
  }
}
