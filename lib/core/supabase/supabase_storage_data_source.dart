import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_error_mapper.dart';

/// Receipt image storage on Supabase Storage (private `receipts` bucket).
///
/// Object layout — the first path segment is always the owning `auth.uid()`,
/// which is how the bucket's RLS policies grant access without a join:
/// ```text
/// receipts/{user_id}/{receipt_id}/full.jpg
/// receipts/{user_id}/{receipt_id}/thumb.jpg
/// ```
/// The bucket is never public; callers render images via short-lived signed
/// URLs from [getSignedUrl].
abstract class SupabaseStorageDataSource {
  /// Uploads a downscaled `thumb.jpg` (200px wide, 70% quality) plus the
  /// `full.jpg` for [receiptId]. Returns the bucket-relative object path of
  /// the full image (what gets persisted as `receipts.storage_object_path`).
  Future<Either<Failure, String>> uploadReceiptImage({
    required String receiptId,
    required File image,
  });

  /// Mints a signed URL (default 1-hour TTL) for a bucket-relative
  /// [objectPath] so the private object can be rendered.
  Future<Either<Failure, String>> getSignedUrl(
    String objectPath, {
    Duration ttl = const Duration(hours: 1),
  });

  /// Removes both the full and thumbnail objects for [receiptId].
  Future<Either<Failure, Unit>> deleteReceiptImage(String receiptId);
}

/// [SupabaseClient]-backed implementation.
class SupabaseStorageDataSourceImpl implements SupabaseStorageDataSource {
  const SupabaseStorageDataSourceImpl(this._client);

  final SupabaseClient _client;

  static const String _bucket = 'receipts';
  static const int _thumbWidth = 200;
  static const int _thumbQuality = 70;

  @override
  Future<Either<Failure, String>> uploadReceiptImage({
    required String receiptId,
    required File image,
  }) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Left<Failure, String>(
        AuthFailure(message: 'No authenticated user for receipt upload'),
      );
    }

    try {
      final String prefix = '$userId/$receiptId';
      final String fullPath = '$prefix/full.jpg';
      final String thumbPath = '$prefix/thumb.jpg';

      final Uint8List fullBytes = await image.readAsBytes();
      final Uint8List thumbBytes = _makeThumbnail(fullBytes);

      const FileOptions options = FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      );
      await _client.storage
          .from(_bucket)
          .uploadBinary(fullPath, fullBytes, fileOptions: options);
      await _client.storage
          .from(_bucket)
          .uploadBinary(thumbPath, thumbBytes, fileOptions: options);

      return Right<Failure, String>(fullPath);
    } on Object catch (e, st) {
      return Left<Failure, String>(SupabaseErrorMapper.map(e, st));
    }
  }

  @override
  Future<Either<Failure, String>> getSignedUrl(
    String objectPath, {
    Duration ttl = const Duration(hours: 1),
  }) async {
    try {
      final String url = await _client.storage
          .from(_bucket)
          .createSignedUrl(objectPath, ttl.inSeconds);
      return Right<Failure, String>(url);
    } on Object catch (e, st) {
      return Left<Failure, String>(SupabaseErrorMapper.map(e, st));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteReceiptImage(String receiptId) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Left<Failure, Unit>(
        AuthFailure(message: 'No authenticated user for receipt delete'),
      );
    }
    try {
      final String prefix = '$userId/$receiptId';
      await _client.storage.from(_bucket).remove(<String>[
        '$prefix/full.jpg',
        '$prefix/thumb.jpg',
      ]);
      return const Right<Failure, Unit>(unit);
    } on Object catch (e, st) {
      return Left<Failure, Unit>(SupabaseErrorMapper.map(e, st));
    }
  }

  /// Decodes [source] and re-encodes a width-[_thumbWidth] JPEG at
  /// [_thumbQuality]. Falls back to the original bytes if decoding fails so a
  /// thumbnail is always written.
  Uint8List _makeThumbnail(Uint8List source) {
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null) return source;
    final img.Image resized = img.copyResize(decoded, width: _thumbWidth);
    return img.encodeJpg(resized, quality: _thumbQuality);
  }
}
