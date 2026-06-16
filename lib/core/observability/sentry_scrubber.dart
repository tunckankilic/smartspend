// Sentry 8.x emits `extra` deprecation hints; Sprint 9 migrates to the
// structured Contexts API. Locally silenced to keep `flutter analyze` clean.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Keys whose values are always replaced with `[Filtered]`, matched as a
/// case-insensitive substring (so `user_access_token` is caught by
/// `access_token`).
const Set<String> kBlacklistedKeys = <String>{
  'password',
  'token',
  'access_token',
  'refresh_token',
  'authorization',
  'apikey',
  'api_key',
  'supabase_anon_key',
  'gemini_api_key',
  'jwt',
};

final RegExp _emailPattern = RegExp(r'[^@\s]+@[^@\s]+\.[^@\s]+');

bool _isSecretKey(String key) {
  final String lower = key.toLowerCase();
  return kBlacklistedKeys.any(lower.contains);
}

/// Partially masks any email addresses inside [value], keeping just the
/// first character of the local part: `alice@example.com` → `a***@example.com`.
///
/// Used so error messages / breadcrumb text that incidentally embed a user
/// email don't ship raw PII to Sentry while still leaving the report
/// debuggable (the domain survives).
String maskEmails(String value) {
  return value.replaceAllMapped(_emailPattern, (Match m) {
    final String email = m.group(0)!;
    final int at = email.indexOf('@');
    final String local = email.substring(0, at);
    final String domain = email.substring(at + 1);
    final String head = local.isEmpty ? '' : local[0];
    return '$head***@$domain';
  });
}

Map<String, dynamic> _scrubMap(Map<String, dynamic> source) {
  final Map<String, dynamic> result = <String, dynamic>{};
  source.forEach((String key, dynamic value) {
    if (_isSecretKey(key)) {
      result[key] = '[Filtered]';
    } else if (value is Map<String, dynamic>) {
      result[key] = _scrubMap(value);
    } else if (value is String) {
      result[key] = maskEmails(value);
    } else {
      result[key] = value;
    }
  });
  return result;
}

/// Strip secrets and mask PII before Sentry sees an event.
///
/// Sentry's docs recommend `sendDefaultPii = false`, but breadcrumbs,
/// extras, and free-form messages can still carry tokens added by SDKs or
/// user emails echoed into error strings. Be paranoid: drop blacklisted
/// keys outright and partially mask any email in a string value or message.
FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  final Map<String, dynamic>? extra = event.extra;
  final SentryMessage? message = event.message;
  return event.copyWith(
    message: message?.copyWith(formatted: maskEmails(message.formatted)),
    extra: extra == null ? null : _scrubMap(extra),
    breadcrumbs: event.breadcrumbs
        ?.map(_scrubBreadcrumb)
        .toList(),
  );
}

Breadcrumb _scrubBreadcrumb(Breadcrumb b) {
  final String? message = b.message;
  final Map<String, dynamic>? data = b.data;
  return b.copyWith(
    message: message == null ? null : maskEmails(message),
    data: data == null ? null : _scrubMap(data),
  );
}
