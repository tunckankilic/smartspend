// ignore_for_file: prefer_initializing_formals — see scan_bloc.dart for
// the rationale on private fields vs. named params.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

/// Decision threshold: ML Kit results below this score escalate to the
/// Gemini Edge Function when the device is online. Tuned conservatively —
/// receipt OCR is bursty and a single bad block can wreck total parsing.
const double kOcrConfidenceThreshold = 0.70;

/// Routes a scan through the cheapest engine that can produce a usable
/// result.
///
/// Strategy:
/// 1. Always run ML Kit first — on-device, free, sub-second.
/// 2. If the result is good enough (≥ [kOcrConfidenceThreshold]) → return.
/// 3. Else, if online → escalate to Gemini Edge Function (rate-limited
///    server-side at 10 req/min/user; client side enforces 1 fallback per
///    scan).
/// 4. Else, if offline → return the ML Kit result anyway. The user gets
///    something to edit; better than failing the scan.
/// 5. If ML Kit throws → still try Gemini if online; only then surface
///    [OCRException].
class HybridOCRDataSource implements OCRDataSource {
  HybridOCRDataSource({
    required OCRDataSource mlKit,
    required OCRDataSource gemini,
    required Connectivity connectivity,
    Logger? logger,
  }) : _mlKit = mlKit,
       _gemini = gemini,
       _connectivity = connectivity,
       _logger = logger;

  final OCRDataSource _mlKit;
  final OCRDataSource _gemini;
  final Connectivity _connectivity;
  final Logger? _logger;

  @override
  Future<OCRResult> recognizeText(File image) async {
    OCRResult? primary;
    Object? primaryError;

    try {
      primary = await _mlKit.recognizeText(image);
      if (primary.confidence >= kOcrConfidenceThreshold) {
        return primary;
      }
      _logger?.i(
        'ML Kit confidence ${primary.confidence} below threshold '
        '$kOcrConfidenceThreshold — considering Gemini fallback.',
      );
    } on Exception catch (e) {
      primaryError = e;
      _logger?.w('ML Kit failed: $e — considering Gemini fallback.');
    }

    if (!await _isOnline()) {
      _logger?.i('Offline — skipping Gemini fallback.');
      if (primary != null) return primary;
      throw OCRException(
        message: 'OCR failed offline: $primaryError',
        code: 'mlkit_offline_failure',
      );
    }

    try {
      final OCRResult fallback = await _gemini.recognizeText(image);
      return fallback;
    } on RateLimitException {
      // Rate-limited: gracefully degrade to ML Kit result if we had one.
      if (primary != null) {
        _logger?.w('Gemini rate-limited — returning ML Kit result.');
        return primary;
      }
      rethrow;
    } on Exception catch (e) {
      if (primary != null) {
        _logger?.w('Gemini failed ($e) — returning ML Kit result.');
        return primary;
      }
      throw OCRException(
        message: 'Both OCR engines failed. ML Kit: $primaryError; '
            'Gemini: $e',
      );
    }
  }

  Future<bool> _isOnline() async {
    final List<ConnectivityResult> result =
        await _connectivity.checkConnectivity();
    return result.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
  }
}
