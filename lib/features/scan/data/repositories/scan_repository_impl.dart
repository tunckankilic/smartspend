// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:logger/logger.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/app_database.dart'
    show
        CategoriesCompanion,
        ExpensesCompanion,
        ReceiptItemsCompanion,
        ReceiptsCompanion;
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';

/// ML Kit confidence below this escalates to the Gemini Edge Function when
/// online. Receipt OCR is bursty and a single bad block can wreck total
/// parsing, so the bar is deliberately conservative.
const double kOcrConfidenceThreshold = 0.70;

/// When the on-device parse finds items AND a printed total but they disagree
/// by more than this fraction of the total, the parse is incomplete (a
/// column-split receipt dropped line items, or a discount the regex missed) —
/// escalate so the cloud engine can itemize from the image directly.
const double kOcrItemsTotalTolerance = 0.10;

class ScanRepositoryImpl implements ScanRepository {
  const ScanRepositoryImpl({
    required CameraDataSource cameraDataSource,
    required OCRDataSource mlKitDataSource,
    required OCRDataSource geminiDataSource,
    required Connectivity connectivity,
    required ReceiptParser parser,
    required ReceiptDao receiptDao,
    required ExpenseDao expenseDao,
    required CategoryDao categoryDao,
    required SupabaseStorageDataSource storage,
    Logger? logger,
  }) : _camera = cameraDataSource,
       _mlKit = mlKitDataSource,
       _gemini = geminiDataSource,
       _connectivity = connectivity,
       _parser = parser,
       _receipts = receiptDao,
       _expenses = expenseDao,
       _categories = categoryDao,
       _storage = storage,
       _logger = logger;

  final CameraDataSource _camera;
  final OCRDataSource _mlKit;
  final OCRDataSource _gemini;
  final Connectivity _connectivity;
  final ReceiptParser _parser;
  final ReceiptDao _receipts;
  final ExpenseDao _expenses;
  final CategoryDao _categories;
  final SupabaseStorageDataSource _storage;
  final Logger? _logger;

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
      return Right<Failure, ScannedReceipt>(await _runOcrPipeline(image));
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

  /// Picks the cheapest OCR engine that yields a usable receipt — the same
  /// source-selection discipline the rest of the app applies to cache vs
  /// remote, here applied to on-device vs cloud OCR:
  ///
  /// 1. ML Kit first (on-device, free, sub-second), then parse it.
  /// 2. If ML Kit was confident *and* the parse is usable → done.
  /// 3. Otherwise, when online, escalate to the Gemini Edge Function, which
  ///    returns pre-itemized structured output mapped straight to a receipt.
  ///    Prefer Gemini's result when it's usable; keep ML Kit's otherwise.
  /// 4. Offline, or Gemini rate-limited/failed → degrade to the ML Kit
  ///    result so the user always gets something to edit.
  ///
  /// The escalation decision lives here (not in a datasource) because only
  /// this layer can see the *parsed* result: ML Kit can report high
  /// confidence yet parse to zero items, which is exactly when the cloud
  /// engine earns its cost.
  Future<ScannedReceipt> _runOcrPipeline(File image) async {
    OCRResult? mlKitResult;
    ScannedReceipt? fromMlKit;
    Object? mlKitError;

    try {
      mlKitResult = await _mlKit.recognizeText(image);
      fromMlKit = _toReceipt(mlKitResult, image.path);
    } on Exception catch (e) {
      // ML Kit is on-device; any failure just means "try the cloud engine".
      mlKitError = e;
      _logger?.w('ML Kit OCR failed: $e — considering Gemini fallback.');
    }

    if (!_shouldEscalate(mlKitResult, fromMlKit)) return fromMlKit!;

    if (!await _isOnline()) {
      _logger?.i('Offline — keeping on-device OCR result.');
      if (fromMlKit != null) return fromMlKit;
      throw OCRException(
        message: 'OCR failed offline: $mlKitError',
        code: 'mlkit_offline_failure',
      );
    }

    try {
      final OCRResult gemini = await _gemini.recognizeText(image);
      final ScannedReceipt fromGemini = _toReceipt(gemini, image.path);
      if (_isUsable(fromGemini) || fromMlKit == null) return fromGemini;
      _logger?.i('Gemini result not usable — keeping ML Kit result.');
      return fromMlKit;
    } on RateLimitException {
      if (fromMlKit != null) {
        _logger?.w('Gemini rate-limited — keeping ML Kit result.');
        return fromMlKit;
      }
      rethrow;
    } on Exception catch (e) {
      if (fromMlKit != null) {
        _logger?.w('Gemini failed ($e) — keeping ML Kit result.');
        return fromMlKit;
      }
      throw OCRException(
        message: 'Both OCR engines failed. ML Kit: $mlKitError; Gemini: $e',
      );
    }
  }

  /// Escalate when ML Kit threw, reported low confidence, or its parse left
  /// out what the cloud engine is good at: line items or a positive total.
  /// Escalating on *empty items even when a total was found* is deliberate —
  /// block-layout ML Kit routinely reads the total but no items, and Gemini's
  /// itemization is the whole point of the fallback. The escalation degrades
  /// gracefully (offline / rate-limited / failed → keep the ML Kit result),
  /// so it never costs the user a usable scan.
  bool _shouldEscalate(OCRResult? mlKit, ScannedReceipt? parsed) {
    if (mlKit == null || parsed == null) return true;
    if (mlKit.confidence < kOcrConfidenceThreshold) return true;
    if (parsed.items.isEmpty || parsed.total <= 0) return true;
    // Items found, but they don't reconcile with the printed total → the
    // on-device parse missed lines (column split) or a discount. The cloud
    // engine reads the layout directly, so escalate rather than trust a
    // plausible-but-wrong itemization.
    final int itemsSum = parsed.items.fold<int>(
      0,
      (int sum, ScannedItem item) => sum + item.totalPrice,
    );
    final int tolerance = (parsed.total * kOcrItemsTotalTolerance).round();
    return (itemsSum - parsed.total).abs() > tolerance;
  }

  /// Whether a result is worth preferring over the ML Kit fallback — i.e. the
  /// engine produced *something* (items or a positive total).
  bool _isUsable(ScannedReceipt r) => r.items.isNotEmpty || r.total > 0;

  /// Maps an [OCRResult] to a [ScannedReceipt]. Prefers the engine's
  /// pre-itemized [OCRStructured] (Gemini) and falls back to the regex
  /// parser over raw text (ML Kit).
  ScannedReceipt _toReceipt(OCRResult ocr, String imagePath) {
    final OCRStructured? s = ocr.structured;
    if (s == null) return _parser.parse(ocr, imagePath: imagePath);

    final List<ScannedItem> items = s.items
        .map(
          (OCRStructuredItem i) => ScannedItem(
            name: i.name,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            totalPrice: i.totalPrice,
          ),
        )
        .toList(growable: false);
    return ScannedReceipt(
      imagePath: imagePath,
      storeName: s.storeName,
      date: _parser.parseDateFromText(ocr.rawText),
      items: items,
      total: s.total ?? _sumItems(items),
      currency: s.currency ?? 'TRY',
      rawText: ocr.rawText,
      confidenceScore: ocr.confidence,
    );
  }

  int _sumItems(List<ScannedItem> items) {
    int sum = 0;
    for (final ScannedItem i in items) {
      if (i.totalPrice > 0) sum += i.totalPrice;
    }
    return sum;
  }

  Future<bool> _isOnline() async {
    final List<ConnectivityResult> result =
        await _connectivity.checkConnectivity();
    return result.any((ConnectivityResult r) => r != ConnectivityResult.none);
  }

  // ---------------------------------------------------------------------
  // Category surface (Sprint 2.3)
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, List<Category>>> listCategories() async {
    try {
      final List<drift_db.Category> rows = await _categories.getAll();
      final List<Category> mapped = rows
          .map(
            (drift_db.Category c) => Category(
              id: c.id,
              name: c.name,
              icon: c.icon,
              color: c.color,
              isCustom: c.isCustom,
            ),
          )
          .toList(growable: false);
      return Right<Failure, List<Category>>(mapped);
    } on Exception catch (e) {
      return Left<Failure, List<Category>>(
        CacheFailure(message: 'listCategories failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, Category>> createCategory({
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
      return Right<Failure, Category>(
        Category(
          id: id,
          name: name,
          icon: icon,
          color: color,
          isCustom: true,
        ),
      );
    } on Exception catch (e) {
      return Left<Failure, Category>(
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

      // OCR detected a total but couldn't itemize it (block-layout ML Kit,
      // low-confidence scans). Record a single expense from the receipt
      // total so the scan still produces a tracked expense instead of an
      // orphan receipt that never reaches the dashboard or budgets.
      if (receipt.items.isEmpty && receipt.total > 0) {
        await _expenses.insertExpense(
          ExpensesCompanion.insert(
            amount: receipt.total,
            categoryId: defaultCategoryId,
            date: date,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
            receiptId: Value<int?>(receiptId),
            note: Value<String?>(receipt.storeName),
            isManual: const Value<bool>(false),
          ),
        );
      }

      // Fire-and-forget: push the receipt image to Storage without blocking
      // the save. On success the returned object path is persisted (which
      // re-stamps the row `pending_update` so the sync engine propagates it);
      // on failure the row stays pending and is retried by a later sync.
      unawaited(_uploadReceiptImage(receiptId, receipt.imagePath));

      return Right<Failure, int>(receiptId);
    } on Exception catch (e) {
      return Left<Failure, int>(
        CacheFailure(message: 'saveReceipt failed: $e'),
      );
    }
  }

  Future<void> _uploadReceiptImage(int receiptId, String? imagePath) async {
    if (imagePath == null) return;
    final File file = File(imagePath);
    if (!file.existsSync()) return;
    final Either<Failure, String> result = await _storage.uploadReceiptImage(
      receiptId: '$receiptId',
      image: file,
    );
    await result.fold(
      (Failure _) async {},
      (String objectPath) async {
        await _receipts.updateReceipt(
          receiptId,
          ReceiptsCompanion(storageObjectPath: Value<String?>(objectPath)),
        );
      },
    );
  }
}
