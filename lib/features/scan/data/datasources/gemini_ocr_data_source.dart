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
/// **What ships here vs Sprint 8:**
/// - Sprint 2.2 (this file): client wiring + response parsing. Tests run
///   against an injected mock [FunctionsClient].
/// - Sprint 8: deploy the Edge Function itself (it lives as a placeholder
///   at `supabase/functions/gemini-ocr-fallback/index.ts` for now).
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
    // Contract shared with the Edge Function (Sprint 8):
    //   {
    //     "data": {
    //       "raw_text": "...",
    //       "confidence": 0.93,
    //       "store_name": "...",  ← used by parser layer, not OCRResult
    //       "items": [...],
    //       "total": 12345
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
    );
  }

  double _readConfidence(Object? raw) {
    if (raw is num) return raw.toDouble().clamp(0.0, 1.0);
    return 0.9; // Gemini is high-quality by default; trust it absent a score.
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
