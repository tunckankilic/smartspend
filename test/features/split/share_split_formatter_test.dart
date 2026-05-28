import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/domain/usecases/share_split_formatter.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  SplitSession session({String currency = 'TRY'}) => SplitSession(
        receiptId: 1,
        storeName: 'Migros',
        receiptDate: DateTime.utc(2026, 5, 28),
        currency: currency,
        totalMinor: 30000,
        items: const <Object>[].cast(),
        participants: const <Participant>[
          Participant(id: 'p1', name: 'Ali'),
          Participant(id: 'p2', name: 'Mehmet'),
        ],
        assignments: const <int, List<String>>{},
        splitType: SplitType.equal,
      );

  group('ShareSplitFormatter.format', () {
    test('should include heading, header, per-person rows and total', () {
      final String out = ShareSplitFormatter.format(
        session: session(),
        totalsMinor: const <String, int>{'p1': 15000, 'p2': 15000},
        locale: 'tr_TR',
        title: 'SmartSpend Hesap Özeti',
        headerBuilder: (String store, String date) => '$store — $date',
        perPersonBuilder: (String name, String amount) => '$name: $amount',
        totalBuilder: (String amount) => 'Toplam: $amount',
      );
      expect(out, contains('SmartSpend Hesap Özeti'));
      expect(out, contains('Migros'));
      expect(out, contains('Ali'));
      expect(out, contains('Mehmet'));
      expect(out, contains('Toplam'));
    });

    test('should render TRY amounts with ₺ glyph', () {
      final String out = ShareSplitFormatter.format(
        session: session(),
        totalsMinor: const <String, int>{'p1': 15000, 'p2': 15000},
        locale: 'tr_TR',
        title: 'X',
        headerBuilder: (String s, String d) => '$s — $d',
        perPersonBuilder: (String n, String a) => '$n: $a',
        totalBuilder: (String a) => 'Toplam: $a',
      );
      expect(out, contains('₺'));
    });

    test('should fall back to bare ISO code for unknown currencies', () {
      final String out = ShareSplitFormatter.format(
        session: session(currency: 'XYZ'),
        totalsMinor: const <String, int>{'p1': 15000, 'p2': 15000},
        locale: 'en_US',
        title: 'X',
        headerBuilder: (String s, String d) => '$s — $d',
        perPersonBuilder: (String n, String a) => '$n: $a',
        totalBuilder: (String a) => 'Total: $a',
      );
      expect(out, contains('XYZ'));
    });
  });
}
