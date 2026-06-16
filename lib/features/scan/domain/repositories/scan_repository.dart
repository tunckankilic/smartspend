import 'dart:io';

import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';

/// Contract for the scan feature's data access.
///
/// Implementations live in `data/`. The interface stays free of Flutter,
/// Drift, Supabase, and `image_picker` types so the domain layer remains
/// portable.
abstract class ScanRepository {
  /// Open the system camera and return the captured image file.
  ///
  /// Returns [PermissionFailure] if the user denied camera access,
  /// [CacheFailure] if writing the temporary file failed, and a generic
  /// [UnexpectedFailure] for everything else.
  Future<Either<Failure, File>> captureImage();

  /// Open the photo library picker and return the selected image file.
  Future<Either<Failure, File>> pickFromGallery();

  /// Run the OCR pipeline against [image] and return a structured receipt.
  Future<Either<Failure, ScannedReceipt>> scanReceipt(File image);

  /// All categories (seeded defaults + user custom ones).
  Future<Either<Failure, List<Category>>> listCategories();

  /// Persist a custom category and return the inserted row. The
  /// [color] argument is a packed ARGB int.
  Future<Either<Failure, Category>> createCategory({
    required String name,
    required String icon,
    required int color,
  });

  /// Save a confirmed receipt to the local cache (Drift). Persists three
  /// tables in a single transaction:
  ///
  /// * `receipts` — one row, stamped `pending_create`
  /// * `receipt_items` — one row per [ScannedReceipt.items] element
  /// * `expenses` — one row per item, so dashboard charts and budget
  ///   tracking can attribute amounts by category
  ///
  /// Items without a `categoryId` fall back to [defaultCategoryId]. The
  /// receipt id (local Drift PK) is returned on success.
  Future<Either<Failure, int>> saveReceipt({
    required ScannedReceipt receipt,
    required int defaultCategoryId,
  });
}
