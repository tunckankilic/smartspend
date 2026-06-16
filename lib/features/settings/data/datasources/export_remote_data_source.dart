// Private `_functions` field assigned from a like-named param — the two
// diverge only in underscore, so `prefer_initializing_formals` fires. Accept
// it, matching `gemini_ocr_data_source.dart`.
// ignore_for_file: prefer_initializing_formals

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/constants/supabase_constants.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';

/// Calls the `export-csv` / `export-pdf` Supabase Edge Functions.
///
/// The function authenticates via the caller's JWT (attached automatically by
/// the SDK), queries the user's own expenses under RLS, writes the file to the
/// `exports/{user_id}/…` bucket, and returns a 24h signed download URL.
abstract class ExportRemoteDataSource {
  Future<ExportResult> exportExpenses({
    DateTime? from,
    DateTime? to,
    ExportFormat format,
  });
}

class SupabaseExportRemoteDataSource implements ExportRemoteDataSource {
  const SupabaseExportRemoteDataSource({required FunctionsClient functions})
    : _functions = functions;

  final FunctionsClient _functions;

  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  /// Maps an [ExportFormat] to its Edge Function name.
  static String _functionName(ExportFormat format) => switch (format) {
    ExportFormat.csv => SupabaseConstants.fnExportCsv,
    ExportFormat.pdf => SupabaseConstants.fnExportPdf,
  };

  @override
  Future<ExportResult> exportExpenses({
    DateTime? from,
    DateTime? to,
    ExportFormat format = ExportFormat.csv,
  }) async {
    final String fnName = _functionName(format);
    final Map<String, dynamic> query = <String, dynamic>{
      if (from != null) 'from_date': _dateParam.format(from),
      if (to != null) 'to_date': _dateParam.format(to),
    };

    try {
      final FunctionResponse response = await _functions.invoke(
        fnName,
        method: HttpMethod.get,
        queryParameters: query.isEmpty ? null : query,
      );

      if (response.status >= 400) {
        throw ServerException(
          message: '$fnName returned HTTP ${response.status}.',
        );
      }

      final Object? data = response.data;
      if (data is! Map<String, Object?>) {
        throw ServerException(
          message: '$fnName returned an unexpected payload shape.',
        );
      }
      final Object? payload = data['data'];
      if (payload is! Map<String, Object?>) {
        throw ServerException(
          message: '$fnName response missing "data" envelope.',
        );
      }
      return _parse(payload);
    } on ServerException {
      rethrow;
    } on FunctionException catch (e) {
      throw ServerException(message: '$fnName failed: ${e.status}');
    } on Exception catch (e) {
      throw ServerException(message: '$fnName transport error: $e');
    }
  }

  ExportResult _parse(Map<String, Object?> payload) {
    final Object? url = payload['url'];
    final Object? expiresAt = payload['expires_at'];
    final Object? rowCount = payload['row_count'];
    if (url is! String || expiresAt is! String || rowCount is! int) {
      throw const ServerException(
        message: 'export-csv response fields have unexpected types.',
      );
    }
    return ExportResult(
      url: url,
      expiresAt: DateTime.parse(expiresAt),
      rowCount: rowCount,
    );
  }
}
