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
  });
}
