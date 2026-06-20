// Field names (`_functions`) keep their leading underscore to mark them
// private; named params drop it by convention. The two diverge only in
// underscore, so `prefer_initializing_formals` fires — accept it.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

/// Calls the `gemini-ocr-fallback` Supabase Edge Function.
///
/// The Edge Function (`supabase/functions/gemini-ocr-fallback/index.ts`) is
/// fully implemented — it runs Gemini Vision and returns pre-itemized
/// `items`/`total`/`store_name`/`currency`. This client maps that payload
/// into [OCRResult.structured] so the repository can skip the regex parser.
///
/// **Operational precondition:** the function must be deployed
/// (`supabase functions deploy gemini-ocr-fallback`) and `GEMINI_API_KEY`
/// set as a secret. Absent the key the function returns `CONFIG_MISSING`
/// and the caller silently degrades to the on-device ML Kit result.
///
/// **Security invariants — do NOT break:**
/// - The Gemini API key is never sent from the device. It lives only as a
///   Supabase Edge Function secret (`GEMINI_API_KEY`).
/// - The user JWT is attached automatically by `supabase.functions.invoke`,
///   so the Edge Function can resolve `auth.uid()` and apply RLS-equivalent
///   per-user rate limiting (10 req/min).
/// - The image goes up as base64; we never log the body.
class GeminiOCRDataSource implements OCRDataSource {
  const GeminiOCRDataSource({required FunctionsClient functions})
    : _functions = functions;

  final FunctionsClient _functions;

  /// Matches the slug in `supabase/functions/gemini-ocr-fallback/`.
  static const String _functionName = 'gemini-ocr-fallback';

  @override
  Future<OCRResult> recognizeText(File image) async {
    final List<int> bytes = await image.readAsBytes();
    final String base64Image = base64Encode(bytes);

    try {
      final FunctionResponse response = await _functions.invoke(
        _functionName,
        body: <String, Object?>{
          'image_base64': base64Image,
          'mime_type': 'image/jpeg',
        },
      );

      if (response.status >= 400) {
        throw _mapHttpStatus(response.status, response.data);
      }

      final Object? data = response.data;
      if (data is! Map<String, Object?>) {
        throw const OCRException(
          message: 'Gemini fallback returned an unexpected payload shape.',
        );
      }
      return _parseResponse(data);
    } on OCRException {
      rethrow;
    } on RateLimitException {
      rethrow;
    } on FunctionException catch (e) {
      throw _mapHttpStatus(e.status, e.details);
    } on Exception catch (e) {
      throw OCRException(message: 'Gemini fallback transport error: $e');
    }
  }

  OCRResult _parseResponse(Map<String, Object?> data) {
    // Contract shared with the Edge Function:
    //   {
    //     "data": {
    //       "raw_text": "...", "confidence": 0.93, "store_name": "...",
    //       "currency": "TRY", "total": 12345, "tax": 700,
    //       "items": [{ "name": "...", "qty": 1, "unit_price": 1250,
    //                   "total_price": 1250 }]
    //     },
    //     "error": null
    //   }
    final Object? payload = data['data'];
    if (payload is! Map<String, Object?>) {
      throw const OCRException(
        message: 'Gemini response missing "data" envelope.',
      );
    }

    final String rawText = (payload['raw_text'] as String?) ?? '';
    final double confidence = _readConfidence(payload['confidence']);

    return OCRResult(
      rawText: rawText,
      blocks: <OCRTextBlock>[
        OCRTextBlock(text: rawText, confidence: confidence),
      ],
      confidence: confidence,
      engine: OCREngine.gemini,
      structured: _parseStructured(payload),
    );
  }

  /// Maps the Edge Function's itemized fields into [OCRStructured]. Returns
  /// `null` when nothing structured is worth keeping (no items, no total, no
  /// store) so the caller falls back to parsing [OCRResult.rawText].
  OCRStructured? _parseStructured(Map<String, Object?> payload) {
    final List<OCRStructuredItem> items = <OCRStructuredItem>[];
    final Object? rawItems = payload['items'];
    if (rawItems is List) {
      for (final Object? entry in rawItems) {
        if (entry is! Map) continue;
        final String name = (entry['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        items.add(
          OCRStructuredItem(
            name: name,
            quantity: _readNum(entry['qty']) ?? 1,
            unitPrice: _readInt(entry['unit_price']) ?? 0,
            totalPrice: _readInt(entry['total_price']) ?? 0,
          ),
        );
      }
    }

    final int? total = _readInt(payload['total']);
    final String? storeName = _readString(payload['store_name']);
    final String? currency = _readString(payload['currency']);
    final int? tax = _readInt(payload['tax']);

    if (items.isEmpty && total == null && storeName == null) return null;
    return OCRStructured(
      items: items,
      storeName: storeName,
      total: total,
      tax: tax,
      currency: currency,
    );
  }

  double _readConfidence(Object? raw) {
    if (raw is num) return raw.toDouble().clamp(0.0, 1.0);
    return 0.9; // Gemini is high-quality by default; trust it absent a score.
  }

  num? _readNum(Object? raw) => raw is num ? raw : null;

  int? _readInt(Object? raw) => raw is num ? raw.round() : null;

  String? _readString(Object? raw) {
    if (raw is! String) return null;
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Exception _mapHttpStatus(int status, Object? body) {
    if (status == 429) {
      return const RateLimitException(
        message: 'Daily Gemini OCR limit reached.',
        code: 'gemini_rate_limit',
      );
    }
    if (status == 401 || status == 403) {
      return const OCRException(
        message: 'Edge Function rejected the request (auth).',
        code: 'gemini_unauthorized',
      );
    }
    return OCRException(
      message: 'Gemini fallback failed: HTTP $status ($body)',
      code: 'gemini_http_$status',
    );
  }
}
