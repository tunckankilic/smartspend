// SentryEvent.extra is deprecated in Sentry 8.x; we still assert on it
// because the production scrubber targets it until the Sprint 10 Contexts
// migration. Silenced locally to keep the suite analyze-clean.
// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:smartspend/core/observability/sentry_scrubber.dart';

void main() {
  group('maskEmails', () {
    test('should keep only the first local char and the domain', () {
      expect(maskEmails('alice@example.com'), 'a***@example.com');
    });

    test('should mask every email embedded in a longer string', () {
      expect(
        maskEmails('contact bob@x.io or carol@y.org'),
        'contact b***@x.io or c***@y.org',
      );
    });

    test('should leave strings without an email untouched', () {
      expect(maskEmails('no email here'), 'no email here');
    });
  });

  group('maskTurkishIds', () {
    test('should mask a 10-digit VKN and keep its length', () {
      expect(maskTurkishIds('VKN 1234567890'), 'VKN **********');
    });

    test('should mask an 11-digit TCKN and keep its length', () {
      expect(maskTurkishIds('TCKN 12345678901'), 'TCKN ***********');
    });

    test('should mask every id embedded in a longer string', () {
      expect(
        maskTurkishIds('satici 1234567890 alici 10987654321'),
        'satici ********** alici ***********',
      );
    });

    test('should leave digit runs outside the 10-11 range untouched', () {
      // Short ones (prices, quantities) and long ones (epoch millis) are not
      // identifiers; only whole 10/11-digit runs are.
      expect(maskTurkishIds('total 12345'), 'total 12345');
      expect(maskTurkishIds('at 1754620000123'), 'at 1754620000123');
    });

    test('should not eat part of a longer digit run', () {
      expect(maskTurkishIds('ref 123456789012345'), 'ref 123456789012345');
    });

    test('should leave strings without digits untouched', () {
      expect(maskTurkishIds('no id here'), 'no id here');
    });
  });

  group('scrubSentryEvent', () {
    test('should filter blacklisted keys in extra', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{
          'access_token': 'secret-jwt',
          'note': 'harmless',
        },
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;

      expect(out!.extra!['access_token'], '[Filtered]');
      expect(out.extra!['note'], 'harmless');
    });

    test('should recurse into nested maps', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{
          'outer': <String, dynamic>{'password': 'hunter2', 'ok': 1},
        },
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      final Map<String, dynamic> outer =
          out!.extra!['outer'] as Map<String, dynamic>;
      expect(outer['password'], '[Filtered]');
      expect(outer['ok'], 1);
    });

    test('should mask emails in string extra values', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{'who': 'dave@acme.com signed in'},
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.extra!['who'], 'd***@acme.com signed in');
    });

    test('should mask emails in the event message', () {
      final SentryEvent event = SentryEvent(
        message: SentryMessage('login failed for eve@corp.net'),
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.message!.formatted, 'login failed for e***@corp.net');
    });

    test('should scrub breadcrumb data and message', () {
      final SentryEvent event = SentryEvent(
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(
            message: 'user frank@dev.io tapped',
            data: <String, dynamic>{'token': 'abc'},
          ),
        ],
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      final Breadcrumb b = out!.breadcrumbs!.first;
      expect(b.message, 'user f***@dev.io tapped');
      expect(b.data!['token'], '[Filtered]');
    });

    test('should filter raw OCR text carried in a breadcrumb', () {
      final SentryEvent event = SentryEvent(
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(
            message: 'gemini fallback returned',
            data: <String, dynamic>{
              'raw_text': 'MIGROS TIC. A.S.\nVKN 1234567890\nTOPLAM *153,11',
              'confidence': 0.93,
            },
          ),
        ],
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      final Breadcrumb b = out!.breadcrumbs!.first;
      expect(b.data!['raw_text'], '[Filtered]');
      expect(b.data!['confidence'], 0.93);
    });

    test('should filter document-bearing keys whatever their casing', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{
          'rawText': 'ABC LTD STI',
          'imagePath': '/tmp/scan.jpg',
          'documentType': 'eArsivFatura',
          'invoiceLines': 3,
          'step': 'parse',
        },
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.extra!['rawText'], '[Filtered]');
      expect(out.extra!['imagePath'], '[Filtered]');
      expect(out.extra!['documentType'], '[Filtered]');
      expect(out.extra!['invoiceLines'], '[Filtered]');
      expect(out.extra!['step'], 'parse');
    });

    test('should mask a VKN in a free-text breadcrumb message', () {
      final SentryEvent event = SentryEvent(
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(message: 'contact lookup failed for VKN 1234567890'),
        ],
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(
        out!.breadcrumbs!.first.message,
        'contact lookup failed for VKN **********',
      );
    });

    test('should mask a TCKN in a free-text extra value', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{'note': 'sahis sirketi 12345678901 eslesti'},
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.extra!['note'], 'sahis sirketi *********** eslesti');
    });

    test('should mask ids in the event message', () {
      final SentryEvent event = SentryEvent(
        message: SentryMessage('export failed for 1234567890'),
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.message!.formatted, 'export failed for **********');
    });

    test('should scrub strings and maps nested inside lists', () {
      final SentryEvent event = SentryEvent(
        extra: <String, dynamic>{
          'blocks': <dynamic>[
            'satici 1234567890',
            <String, dynamic>{'raw_text': 'MIGROS', 'index': 0},
          ],
        },
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      final List<dynamic> blocks = out!.extra!['blocks'] as List<dynamic>;
      expect(blocks.first, 'satici **********');
      final Map<String, dynamic> nested = blocks[1] as Map<String, dynamic>;
      expect(nested['raw_text'], '[Filtered]');
      expect(nested['index'], 0);
    });

    test('should leave payloads without PII untouched', () {
      final SentryEvent event = SentryEvent(
        message: SentryMessage('sync completed'),
        extra: <String, dynamic>{
          'durationMs': 1240,
          'step': 'push',
          'counts': <String, dynamic>{'pushed': 12, 'pulled': 3},
        },
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(
            message: 'sync started',
            data: <String, dynamic>{'trigger': 'manual'},
          ),
        ],
      );

      final SentryEvent? out =
          scrubSentryEvent(event, Hint()) as SentryEvent?;
      expect(out!.message!.formatted, 'sync completed');
      expect(out.extra!['durationMs'], 1240);
      expect(out.extra!['step'], 'push');
      expect(
        (out.extra!['counts'] as Map<String, dynamic>)['pushed'],
        12,
      );
      expect(out.breadcrumbs!.first.message, 'sync started');
      expect(out.breadcrumbs!.first.data!['trigger'], 'manual');
    });
  });
}
