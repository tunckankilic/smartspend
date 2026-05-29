import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';

/// Read-side + warranty-edit contract for the receipt archive (Sprint 7).
///
/// Reads return reactive streams so the archive page stays in lock-step
/// with new scans, deletions and warranty edits. Writes are limited to
/// the warranty expiry — full edit of a receipt is owned by the scan
/// edit feature (Sprint 2.3).
abstract class ReceiptArchiveRepository {
  /// Streams every non-deleted receipt matching [filter].
  ///
  /// Empty / default [ReceiptArchiveFilter] returns the full archive.
  /// The Sprint 8 implementation will additionally hydrate `imagePath`
  /// from Supabase Storage signed URLs; today it's the local file.
  Stream<List<ReceiptArchiveEntry>> watchArchive(ReceiptArchiveFilter filter);

  /// One-shot detail read.
  Future<Either<Failure, ReceiptDetail>> getDetail(int receiptId);

  /// Mints a short-lived signed URL for a receipt image stored in the
  /// private `receipts` bucket. [objectPath] is the bucket-relative path
  /// persisted on the receipt row (`storage_object_path`).
  Future<Either<Failure, String>> getReceiptImageUrl(String objectPath);

  /// Patch the warranty end date. Pass `null` to clear the warranty.
  ///
  /// Notification scheduling is **not** done here — the use case layer
  /// composes the repo write + `NotificationService` call so the
  /// repository stays plugin-free.
  Future<Either<Failure, void>> setWarrantyEndDate(
    int receiptId,
    DateTime? endDate,
  );
}
