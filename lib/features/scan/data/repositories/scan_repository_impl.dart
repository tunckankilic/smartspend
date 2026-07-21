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
import 'package:smartspend/core/error/failure_codes.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/ocr_debug_recorder.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// ML Kit confidence below this escalates to the Gemini Edge Function when
/// online. The value (and the full gate) lives in the receipt_ocr package's
/// [EscalationPolicy] so the eval harness measures the exact production
/// rule; these aliases keep the app-side names stable.
const double kOcrConfidenceThreshold = EscalationPolicy.confidenceThreshold;

/// When the on-device parse finds items AND a printed total but they disagree
/// by more than this fraction of the total, the parse is incomplete (a
/// column-split receipt dropped line items, or a discount the regex missed) —
/// escalate so the cloud engine can itemize from the image directly.
const double kOcrItemsTotalTolerance = EscalationPolicy.itemsTotalTolerance;

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
    required SettingsRepository settingsRepository,
    Logger? logger,
    OcrDebugRecorder? debugRecorder,
  }) : _camera = cameraDataSource,
       _mlKit = mlKitDataSource,
       _gemini = geminiDataSource,
       _connectivity = connectivity,
       _parser = parser,
       _receipts = receiptDao,
       _expenses = expenseDao,
       _categories = categoryDao,
       _storage = storage,
       _settings = settingsRepository,
       _logger = logger,
       _debugRecorder = debugRecorder;

  final CameraDataSource _camera;
  final OCRDataSource _mlKit;
  final OCRDataSource _gemini;
  final Connectivity _connectivity;
  final ReceiptParser _parser;
  final ReceiptDao _receipts;
  final ExpenseDao _expenses;
  final CategoryDao _categories;
  final SupabaseStorageDataSource _storage;
  final SettingsRepository _settings;
  final Logger? _logger;

  /// OCR corpus recorder (roadmap ADIM 1) — no-op unless the build defines
  /// OCR_DEBUG. Optional so tests and store builds are untouched.
  final OcrDebugRecorder? _debugRecorder;

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
      // Corpus collection wants the *raw on-device* output — record it
      // before any parsing/escalation touches the flow.
      _debugRecorder?.record(mlKitResult);
      fromMlKit = _toReceipt(mlKitResult, image.path);
    } on Exception catch (e) {
      // ML Kit is on-device; any failure just means "try the cloud engine".
      mlKitError = e;
      _logger?.w('ML Kit OCR failed: $e — considering Gemini fallback.');
    }

    if (!_shouldEscalate(mlKitResult, fromMlKit)) return fromMlKit!;

    // Privacy gate (App Store 5.1.2(i)): the receipt photo may only leave
    // the device when the user has explicitly allowed the Gemini fallback.
    // Anything else — never asked, denied, or the preference unreadable —
    // degrades to the on-device result, exactly like being offline.
    if (!await _aiConsentGranted()) {
      _logger?.i('AI consent not granted — keeping on-device OCR result.');
      if (fromMlKit != null) return fromMlKit;
      throw OCRException(
        message: 'OCR failed and cloud fallback is not permitted: $mlKitError',
        code: kOcrNoAiConsentCode,
      );
    }

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

  /// Thin adapter over the shared [EscalationPolicy] (receipt_ocr package):
  /// the rule itself lives there so the eval harness's `would_escalate`
  /// metric can never drift from production. The escalation degrades
  /// gracefully (offline / rate-limited / failed → keep the ML Kit result),
  /// so it never costs the user a usable scan.
  bool _shouldEscalate(OCRResult? mlKit, ScannedReceipt? parsed) {
    if (mlKit == null || parsed == null) return true;
    final int itemsSum = parsed.items.fold<int>(
      0,
      (int sum, ScannedItem item) => sum + item.totalPrice,
    );
    return EscalationPolicy.shouldEscalate(
      confidence: mlKit.confidence,
      itemCount: parsed.items.length,
      itemsSum: itemsSum,
      total: parsed.total,
    );
  }

  /// Whether a result is worth preferring over the ML Kit fallback — i.e. the
  /// engine produced *something* (items or a positive total).
  bool _isUsable(ScannedReceipt r) => r.items.isNotEmpty || r.total > 0;

  /// Maps an [OCRResult] to a [ScannedReceipt]. Prefers the engine's
  /// pre-itemized [OCRStructured] (Gemini) and falls back to the regex
  /// parser over raw text (ML Kit).
  ScannedReceipt _toReceipt(OCRResult ocr, String imagePath) {
    final OCRStructured? s = ocr.structured;
    if (s == null) {
      // The parser (receipt_ocr package) is app-agnostic: it returns a
      // ParsedReceipt without image path / raw text / confidence — those
      // belong to this scan pipeline, so they're composed here.
      final ParsedReceipt parsed = _parser.parse(ocr);
      return ScannedReceipt(
        imagePath: imagePath,
        storeName: parsed.storeName,
        date: parsed.date,
        items: parsed.items
            .map(
              (ParsedItem i) => ScannedItem(
                name: i.name,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                totalPrice: i.totalPrice,
              ),
            )
            .toList(growable: false),
        total: parsed.total,
        currency: parsed.currency,
        rawText: ocr.rawText,
        confidenceScore: ocr.confidence,
      );
    }

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
    final List<ConnectivityResult> result = await _connectivity
        .checkConnectivity();
    return result.any((ConnectivityResult r) => r != ConnectivityResult.none);
  }

  /// Fails closed: only an explicit [AiConsentStatus.granted] opens the
  /// cloud path; a read failure counts as "no consent".
  Future<bool> _aiConsentGranted() async {
    final Either<Failure, UserPreferences> prefs = await _settings
        .getPreferences();
    return prefs.fold(
      (Failure _) => false,
      (UserPreferences p) => p.aiConsent == AiConsentStatus.granted,
    );
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
      final int sortOrder = (await _categories.getAll()).length + 1;
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
