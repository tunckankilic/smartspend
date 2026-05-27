// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/domain/entities/scan_category.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';

class ScanRepositoryImpl implements ScanRepository {
  const ScanRepositoryImpl({
    required CameraDataSource cameraDataSource,
    required OCRDataSource ocrDataSource,
    required ReceiptParser parser,
    required ReceiptDao receiptDao,
    required ExpenseDao expenseDao,
    required CategoryDao categoryDao,
  }) : _camera = cameraDataSource,
       _ocr = ocrDataSource,
       _parser = parser,
       _receipts = receiptDao,
       _expenses = expenseDao,
       _categories = categoryDao;

  final CameraDataSource _camera;
  final OCRDataSource _ocr;
  final ReceiptParser _parser;
  final ReceiptDao _receipts;
  final ExpenseDao _expenses;
  final CategoryDao _categories;

  // ---------------------------------------------------------------------
  // Image acquisition
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, File>> captureImage() async {
    return _pick(_camera.captureImage);
  }

  @override
  Future<Either<Failure, File>> pickFromGallery() async {
    return _pick(_camera.pickFromGallery);
  }

  Future<Either<Failure, File>> _pick(Future<File> Function() source) async {
    try {
      final File raw = await source();
      final File processed = await _camera.preprocessImage(raw);
      return Right<Failure, File>(processed);
    } on PermissionException catch (e) {
      return Left<Failure, File>(
        PermissionFailure(message: e.message, code: e.code),
      );
    } on CacheException catch (e) {
      return Left<Failure, File>(
        CacheFailure(message: e.message, code: e.code),
      );
    } on Exception catch (e) {
      return Left<Failure, File>(UnexpectedFailure(message: e.toString()));
    }
  }

  // ---------------------------------------------------------------------
  // OCR + parse
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, ScannedReceipt>> scanReceipt(File image) async {
    try {
      final OCRResult ocr = await _ocr.recognizeText(image);
      final ScannedReceipt receipt = _parser.parse(ocr, imagePath: image.path);
      return Right<Failure, ScannedReceipt>(receipt);
    } on RateLimitException catch (e) {
      return Left<Failure, ScannedReceipt>(
        RateLimitFailure(
          message: e.message,
          code: e.code,
          retryAfter: e.retryAfter,
        ),
      );
    } on OCRException catch (e) {
      return Left<Failure, ScannedReceipt>(
        OCRFailure(message: e.message, code: e.code),
      );
    } on Exception catch (e) {
      return Left<Failure, ScannedReceipt>(
        OCRFailure(message: 'Scan failed: $e'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Category surface (Sprint 2.3)
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, List<ScanCategory>>> listCategories() async {
    try {
      final List<Category> rows = await _categories.getAll();
      final List<ScanCategory> mapped = rows
          .map(
            (Category c) => ScanCategory(
              id: c.id,
              name: c.name,
              icon: c.icon,
              color: c.color,
              isCustom: c.isCustom,
            ),
          )
          .toList(growable: false);
      return Right<Failure, List<ScanCategory>>(mapped);
    } on Exception catch (e) {
      return Left<Failure, List<ScanCategory>>(
        CacheFailure(message: 'listCategories failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, ScanCategory>> createCategory({
    required String name,
    required String icon,
    required int color,
  }) async {
    try {
      final int sortOrder =
          (await _categories.getAll()).length + 1;
      final int id = await _categories.insertCustom(
        CategoriesCompanion.insert(
          name: name,
          icon: icon,
          color: color,
          sortOrder: Value<int>(sortOrder),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return Right<Failure, ScanCategory>(
        ScanCategory(
          id: id,
          name: name,
          icon: icon,
          color: color,
          isCustom: true,
        ),
      );
    } on Exception catch (e) {
      return Left<Failure, ScanCategory>(
        CacheFailure(message: 'createCategory failed: $e'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Save (Receipt + ReceiptItems + Expenses)
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, int>> saveReceipt({
    required ScannedReceipt receipt,
    required int defaultCategoryId,
  }) async {
    try {
      final DateTime date = receipt.date ?? DateTime.now().toUtc();
      final int receiptId = await _receipts.insertReceipt(
        ReceiptsCompanion.insert(
          date: date,
          total: receipt.total,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          storeName: Value<String?>(receipt.storeName),
          currency: Value<String>(receipt.currency),
          imagePath: Value<String?>(receipt.imagePath),
          rawOcrText: Value<String?>(receipt.rawText),
          confidenceScore: Value<double?>(receipt.confidenceScore),
        ),
      );

      for (final ScannedItem item in receipt.items) {
        final int categoryId = item.categoryId ?? defaultCategoryId;
        await _receipts.insertItem(
          ReceiptItemsCompanion.insert(
            receiptId: receiptId,
            name: item.name,
            unitPrice: item.unitPrice,
            totalPrice: item.totalPrice,
            updatedAt: DateTime.now().toUtc(),
            quantity: Value<double>(item.quantity.toDouble()),
            categoryId: Value<int?>(categoryId),
          ),
        );
        await _expenses.insertExpense(
          ExpensesCompanion.insert(
            amount: item.totalPrice,
            categoryId: categoryId,
            date: date,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
            receiptId: Value<int?>(receiptId),
            note: Value<String?>(item.name),
            isManual: const Value<bool>(false),
          ),
        );
      }

      return Right<Failure, int>(receiptId);
    } on Exception catch (e) {
      return Left<Failure, int>(
        CacheFailure(message: 'saveReceipt failed: $e'),
      );
    }
  }
}
