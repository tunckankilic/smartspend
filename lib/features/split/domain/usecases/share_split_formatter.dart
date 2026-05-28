import 'package:intl/intl.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';

/// Builds the share-sheet payload from a `SplitSession` + the calculator's
/// totals (Sprint 7).
///
/// `share_plus`'s `Share.share(text)` API hands the platform a single
/// string. Locale-aware formatting (decimal separator, currency glyph,
/// date) lives here so the bloc stays testable and the widget can
/// `share_plus` without juggling NumberFormat instances.
///
/// Localization is supplied by the **caller** via three builder
/// closures — the presentation layer wraps `AppLocalizations.of(context)`
/// methods so this module has zero dependency on the generated l10n
/// classes and unit tests can pass plain Dart closures.
class ShareSplitFormatter {
  const ShareSplitFormatter._();

  /// Builds the share string.
  ///
  /// Example output for `locale = 'tr_TR'`:
  ///
  ///     SmartSpend Hesap Özeti
  ///     Migros — 28.05.2026
  ///
  ///     Ali: 145,00 ₺
  ///     Mehmet: 210,50 ₺
  ///     Sen: 95,00 ₺
  ///
  ///     Toplam: 450,50 ₺
  static String format({
    required SplitSession session,
    required Map<String, int> totalsMinor,
    required String locale,
    required String title,
    required String Function(String store, String date) headerBuilder,
    required String Function(String name, String amount) perPersonBuilder,
    required String Function(String amount) totalBuilder,
  }) {
    final DateFormat dateFmt = DateFormat.yMd(locale);
    final NumberFormat moneyFmt = NumberFormat.currency(
      locale: locale,
      symbol: _symbolFor(session.currency),
      decimalDigits: 2,
    );
    final String dateStr = dateFmt.format(session.receiptDate.toLocal());
    final String header = headerBuilder(session.storeName, dateStr);

    final StringBuffer buffer = StringBuffer()
      ..writeln(title)
      ..writeln(header)
      ..writeln();

    for (final Participant p in session.participants) {
      final int minor = totalsMinor[p.id] ?? 0;
      buffer.writeln(
        perPersonBuilder(p.name, moneyFmt.format(minor / 100.0)),
      );
    }

    buffer
      ..writeln()
      ..writeln(totalBuilder(moneyFmt.format(session.totalMinor / 100.0)));

    return buffer.toString().trimRight();
  }

  /// Maps ISO 4217 currency codes to display glyphs. Falls back to the
  /// code itself when unknown — `NumberFormat.currency` then renders
  /// it as a trailing string ("450,50 USD").
  static String _symbolFor(String currency) {
    switch (currency.toUpperCase()) {
      case 'TRY':
        return '₺';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'USD':
        return r'$';
      default:
        return currency;
    }
  }
}
