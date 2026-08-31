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

/// Keys whose values carry **document content** rather than secrets, matched
/// the same case-insensitive substring way.
///
/// Scanned documents are the app's densest PII: a receipt's raw OCR text
/// already carries a merchant's tax number, and an e-Arşiv invoice carries
/// the counterparty's VKN/TCKN, trade name and address **by design** — data
/// belonging to someone who is not our user and cannot consent to it leaving
/// the country. `gemini-ocr-fallback` returns that text as `raw_text`, so it
/// is a live object in the app and one breadcrumb away from Sentry.
///
/// Filtered wholesale rather than masked: there is no version of a document
/// dump that is both useful in a crash report and safe to ship offshore.
/// Over-filtering is the intended direction — `documentCount` losing its
/// value costs a debugging hint, a leaked TCKN cannot be taken back.
const Set<String> kDocumentPiiKeys = <String>{
  'ocr',
  'raw_text',
  'rawtext',
  'image',
  'document',
  'receipt',
  'invoice',
  'fatura',
  'belge',
};

final RegExp _emailPattern = RegExp(r'[^@\s]+@[^@\s]+\.[^@\s]+');

/// A standalone run of exactly 10 or 11 digits — VKN (tax number, 10) and
/// TCKN (national id, 11). The boundaries keep longer runs (card-ish numbers,
/// epoch milliseconds) from being partially eaten.
final RegExp _turkishIdPattern = RegExp(r'(?<!\d)\d{10,11}(?!\d)');

bool _isFilteredKey(String key) {
  final String lower = key.toLowerCase();
  return kBlacklistedKeys.any(lower.contains) ||
      kDocumentPiiKeys.any(lower.contains);
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

/// Masks Turkish tax (VKN) and national (TCKN) id numbers, keeping the digit
/// count so a reader can still tell the two apart: `12345678901` →
/// `***********`.
///
/// Same bargain as [maskEmails] — keep the shape that makes a report
/// debuggable, drop the part that identifies a person. No digits survive:
/// a partially revealed id is still an identifier when combined with the
/// merchant name sitting next to it in the same breadcrumb.
///
/// Deliberately over-eager: a bare 10-digit epoch-seconds timestamp in free
/// text gets masked too. Losing a timestamp from a crash report is cheap;
/// this runs fail-closed on purpose.
String maskTurkishIds(String value) {
  return value.replaceAllMapped(
    _turkishIdPattern,
    (Match m) => '*' * m.group(0)!.length,
  );
}

String _scrubString(String value) => maskTurkishIds(maskEmails(value));

/// Recurses through maps **and lists** — Sentry payloads nest freely, and a
/// list of OCR blocks under an innocuous key would otherwise sail through
/// untouched.
dynamic _scrubValue(dynamic value) {
  if (value is Map<String, dynamic>) return _scrubMap(value);
  if (value is List<dynamic>) return value.map(_scrubValue).toList();
  if (value is String) return _scrubString(value);
  return value;
}

Map<String, dynamic> _scrubMap(Map<String, dynamic> source) {
  final Map<String, dynamic> result = <String, dynamic>{};
  source.forEach((String key, dynamic value) {
    result[key] = _isFilteredKey(key) ? '[Filtered]' : _scrubValue(value);
  });
  return result;
}

/// Strip secrets and mask PII before Sentry sees an event.
///
/// Sentry's docs recommend `sendDefaultPii = false`, but breadcrumbs,
/// extras, and free-form messages can still carry tokens added by SDKs,
/// user emails echoed into error strings, or scanned-document text. Be
/// paranoid: drop blacklisted and document-bearing keys outright, and mask
/// emails and Turkish id numbers in every string that survives — message,
/// extras, breadcrumb messages and breadcrumb data alike.
FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  final Map<String, dynamic>? extra = event.extra;
  final SentryMessage? message = event.message;
  return event.copyWith(
    message: message?.copyWith(formatted: _scrubString(message.formatted)),
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
    message: message == null ? null : _scrubString(message),
    data: data == null ? null : _scrubMap(data),
  );
}
