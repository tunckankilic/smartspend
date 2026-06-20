import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart'
    show AppDatabase, Expense, Receipt, ReceiptItem;
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/data/repositories/scan_repository_impl.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';

import '../../helpers/test_database.dart';

class _MockCameraDataSource extends Mock implements CameraDataSource {}

class _MockOCRDataSource extends Mock implements OCRDataSource {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockReceiptDao extends Mock implements ReceiptDao {}

class _MockExpenseDao extends Mock implements ExpenseDao {}

class _MockCategoryDao extends Mock implements CategoryDao {}

class _MockStorage extends Mock implements SupabaseStorageDataSource {}

class _FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeFile());
  });

  late _MockCameraDataSource camera;
  late _MockOCRDataSource mlKit;
  late _MockOCRDataSource gemini;
  late _MockConnectivity connectivity;
  late _MockReceiptDao receiptDao;
  late _MockExpenseDao expenseDao;
  late _MockCategoryDao categoryDao;
  late _MockStorage storage;
  late ReceiptParser parser;
  late ScanRepositoryImpl repo;
  late File raw;
  late File processed;

  setUp(() {
    camera = _MockCameraDataSource();
    mlKit = _MockOCRDataSource();
    gemini = _MockOCRDataSource();
    connectivity = _MockConnectivity();
    receiptDao = _MockReceiptDao();
    expenseDao = _MockExpenseDao();
    categoryDao = _MockCategoryDao();
    storage = _MockStorage();
    parser = ReceiptParser();
    repo = ScanRepositoryImpl(
      cameraDataSource: camera,
      mlKitDataSource: mlKit,
      geminiDataSource: gemini,
      connectivity: connectivity,
      parser: parser,
      receiptDao: receiptDao,
      expenseDao: expenseDao,
      categoryDao: categoryDao,
      storage: storage,
    );
    raw = File('/tmp/raw.jpg');
    processed = File('/tmp/raw.processed.jpg');
  });

  void mockOnline({bool online = true}) {
    when(() => connectivity.checkConnectivity()).thenAnswer(
      (_) async => online
          ? <ConnectivityResult>[ConnectivityResult.wifi]
          : <ConnectivityResult>[ConnectivityResult.none],
    );
  }

  group('captureImage', () {
    test('should return the preprocessed file on success', () async {
      when(() => camera.captureImage()).thenAnswer((_) async => raw);
      when(() => camera.preprocessImage(raw))
          .thenAnswer((_) async => processed);

      final Either<Failure, File> result = await repo.captureImage();

      expect(result, Right<Failure, File>(processed));
    });

    test('should translate PermissionException → PermissionFailure', () async {
      when(() => camera.captureImage()).thenThrow(
        const PermissionException(message: 'denied'),
      );

      final Either<Failure, File> result = await repo.captureImage();

      final Failure f = result.swap().getOrElse(
        () => throw StateError('expected Left'),
      );
      expect(f, isA<PermissionFailure>());
    });

    test('should preserve user-cancel sentinel code', () async {
      when(() => camera.captureImage()).thenThrow(
        const PermissionException(
          message: 'cancelled',
          code: kCameraCancelledCode,
        ),
      );

      final Either<Failure, File> result = await repo.captureImage();
      final Failure f = result.swap().getOrElse(
        () => throw StateError('expected Left'),
      );
      expect(f.code, kCameraCancelledCode);
    });

    test('should translate CacheException → CacheFailure', () async {
      when(() => camera.captureImage()).thenAnswer((_) async => raw);
      when(() => camera.preprocessImage(raw))
          .thenThrow(const CacheException(message: 'decode failed'));

      final Either<Failure, File> result = await repo.captureImage();
      expect(
        result.swap().getOrElse(() => throw StateError('left')),
        isA<CacheFailure>(),
      );
    });
  });

  group('pickFromGallery', () {
    test('should return the preprocessed file on success', () async {
      when(() => camera.pickFromGallery()).thenAnswer((_) async => raw);
      when(() => camera.preprocessImage(raw))
          .thenAnswer((_) async => processed);

      final Either<Failure, File> result = await repo.pickFromGallery();
      expect(result, Right<Failure, File>(processed));
    });
  });

  group('scanReceipt', () {
    OCRResult mlKitResult(String text, {double confidence = 0.9}) => OCRResult(
          rawText: text,
          blocks: <OCRTextBlock>[
            OCRTextBlock(text: text, confidence: confidence),
          ],
          confidence: confidence,
          engine: OCREngine.mlKit,
        );

    OCRResult geminiResult({
      List<OCRStructuredItem> items = const <OCRStructuredItem>[],
      int? total,
      String? store,
      String? currency,
      String rawText = '',
      double confidence = 0.93,
    }) =>
        OCRResult(
          rawText: rawText,
          blocks: <OCRTextBlock>[
            OCRTextBlock(text: rawText, confidence: confidence),
          ],
          confidence: confidence,
          engine: OCREngine.gemini,
          structured: OCRStructured(
            items: items,
            total: total,
            storeName: store,
            currency: currency,
          ),
        );

    test('parses a confident, itemized ML Kit result without escalating',
        () async {
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult(
          'BİM BİRLEŞİK MAĞAZALAR A.Ş.\n'
          'TARİH: 15/04/2026\n'
          'EKMEK 4,50\n'
          'TOPLAM 4,50',
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.storeName, 'BİM BİRLEŞİK MAĞAZALAR A.Ş.');
      expect(receipt.date, DateTime.utc(2026, 4, 15));
      expect(receipt.total, 450);
      expect(receipt.currency, 'TRY');
      expect(receipt.imagePath, raw.path);
      expect(receipt.confidenceScore, 0.9);
      verifyNever(() => gemini.recognizeText(any()));
    });

    test('escalates to Gemini when a confident ML Kit result parses to no '
        'items', () async {
      // High confidence, but a block layout the regex parser can't itemize —
      // the parse-aware gate the old confidence-only wrapper missed.
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('GÜNEŞ\n???\n###', confidence: 0.95),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenAnswer(
        (_) async => geminiResult(
          store: 'GÜNEŞ',
          total: 14200,
          currency: 'TRY',
          items: const <OCRStructuredItem>[
            OCRStructuredItem(
              name: 'HİBİSKUS',
              quantity: 1,
              unitPrice: 14200,
              totalPrice: 14200,
            ),
          ],
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      verify(() => gemini.recognizeText(any())).called(1);
      expect(receipt.storeName, 'GÜNEŞ');
      expect(receipt.total, 14200);
      expect(receipt.items.single.name, 'HİBİSKUS');
    });

    test('escalates when ML Kit finds a total but cannot itemize it',
        () async {
      // ML Kit reads the printed TOPLAM but the block layout yields no line
      // items — itemization is exactly what the cloud engine is for, so we
      // escalate even though a positive total was already found.
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('GÜNEŞ MARKET\nTOPLAM 142,00'),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenAnswer(
        (_) async => geminiResult(
          store: 'GÜNEŞ',
          total: 14200,
          items: const <OCRStructuredItem>[
            OCRStructuredItem(
              name: 'HİBİSKUS ÇAYI',
              quantity: 1,
              unitPrice: 14200,
              totalPrice: 14200,
            ),
          ],
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      verify(() => gemini.recognizeText(any())).called(1);
      expect(receipt.items.single.name, 'HİBİSKUS ÇAYI');
    });

    test('maps Gemini structured output directly, skipping the regex parser',
        () async {
      // raw_text is deliberate noise: a parser run would yield nothing, so a
      // populated receipt proves the structured branch was taken.
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('unparseable', confidence: 0.2),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenAnswer(
        (_) async => geminiResult(
          rawText: 'noise noise noise',
          store: 'ŞAHUTOĞLU',
          total: 67041,
          currency: 'TRY',
          items: const <OCRStructuredItem>[
            OCRStructuredItem(
              name: 'A',
              quantity: 1,
              unitPrice: 30000,
              totalPrice: 30000,
            ),
            OCRStructuredItem(
              name: 'B',
              quantity: 1,
              unitPrice: 37041,
              totalPrice: 37041,
            ),
          ],
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.items.length, 2);
      expect(receipt.total, 67041);
      expect(receipt.storeName, 'ŞAHUTOĞLU');
    });

    test('sums Gemini items when the structured total is null', () async {
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('x', confidence: 0.1),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenAnswer(
        (_) async => geminiResult(
          items: const <OCRStructuredItem>[
            OCRStructuredItem(
              name: 'A',
              quantity: 1,
              unitPrice: 1000,
              totalPrice: 1000,
            ),
            OCRStructuredItem(
              name: 'B',
              quantity: 1,
              unitPrice: 2000,
              totalPrice: 2000,
            ),
          ],
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.total, 3000);
      expect(receipt.currency, 'TRY'); // null currency defaults to TRY
    });

    test('keeps the ML Kit result when offline even at low confidence',
        () async {
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('EKMEK 4,50\nTOPLAM 4,50', confidence: 0.4),
      );
      mockOnline(online: false);

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.total, 450);
      verifyNever(() => gemini.recognizeText(any()));
    });

    test('escalates to Gemini when ML Kit throws and we are online', () async {
      when(() => mlKit.recognizeText(any())).thenThrow(
        const OCRException(message: 'recognizer crashed'),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenAnswer(
        (_) async => geminiResult(
          total: 5000,
          items: const <OCRStructuredItem>[
            OCRStructuredItem(
              name: 'A',
              quantity: 1,
              unitPrice: 5000,
              totalPrice: 5000,
            ),
          ],
        ),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.total, 5000);
    });

    test('surfaces OCRFailure when offline and ML Kit fails', () async {
      when(() => mlKit.recognizeText(any())).thenThrow(
        const OCRException(message: 'recognizer crashed'),
      );
      mockOnline(online: false);

      final Either<Failure, ScannedReceipt> result =
          await repo.scanReceipt(raw);
      expect(
        result.swap().getOrElse(() => throw StateError('left')),
        isA<OCRFailure>(),
      );
      verifyNever(() => gemini.recognizeText(any()));
    });

    test('degrades to the ML Kit result when Gemini is rate-limited',
        () async {
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('EKMEK 4,50\nTOPLAM 4,50', confidence: 0.4),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenThrow(
        const RateLimitException(message: 'limit'),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.total, 450);
    });

    test('surfaces RateLimitFailure when ML Kit failed and Gemini is '
        'rate-limited', () async {
      when(() => mlKit.recognizeText(any())).thenThrow(
        const OCRException(message: 'crashed'),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenThrow(
        const RateLimitException(message: 'limit'),
      );

      final Either<Failure, ScannedReceipt> result =
          await repo.scanReceipt(raw);
      expect(
        result.swap().getOrElse(() => throw StateError('left')),
        isA<RateLimitFailure>(),
      );
    });

    test('degrades to the ML Kit result when Gemini throws a generic error',
        () async {
      when(() => mlKit.recognizeText(any())).thenAnswer(
        (_) async => mlKitResult('EKMEK 4,50\nTOPLAM 4,50', confidence: 0.4),
      );
      mockOnline();
      when(() => gemini.recognizeText(any())).thenThrow(
        const OCRException(message: 'gemini down'),
      );

      final ScannedReceipt receipt = (await repo.scanReceipt(raw)).getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receipt.total, 450);
    });
  });

  group('categories + save (integration with in-memory Drift)', () {
    late AppDatabase db;
    late ScanRepositoryImpl liveRepo;

    setUp(() async {
      db = createTestDatabase();
      // Wait for onCreate migration to seed the 15 default categories.
      await db.categoryDao.getAll();
      liveRepo = ScanRepositoryImpl(
        cameraDataSource: camera,
        mlKitDataSource: mlKit,
        geminiDataSource: gemini,
        connectivity: connectivity,
        parser: parser,
        receiptDao: db.receiptDao,
        expenseDao: db.expenseDao,
        categoryDao: db.categoryDao,
        storage: storage,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('listCategories should return the 15 seeded defaults', () async {
      final Either<Failure, List<Category>> result =
          await liveRepo.listCategories();
      final List<Category> cats = result.getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(cats.length, greaterThanOrEqualTo(15));
      expect(
        cats.map((Category c) => c.name),
        contains('Market'),
      );
    });

    test('createCategory should persist a custom category', () async {
      final Either<Failure, Category> result =
          await liveRepo.createCategory(
        name: 'Hediye Kartı',
        icon: 'card_giftcard',
        color: 0xFFCE93D8,
      );

      final Category created = result.getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(created.name, 'Hediye Kartı');
      expect(created.isCustom, isTrue);

      final List<Category> all = (await liveRepo.listCategories())
          .getOrElse(() => throw StateError('left'));
      expect(
        all.any((Category c) => c.name == 'Hediye Kartı'),
        isTrue,
      );
    });

    test('saveReceipt should write 1 receipt + N items + N expenses',
        () async {
      final List<Category> cats = (await liveRepo.listCategories())
          .getOrElse(() => throw StateError('left'));
      final int marketId = cats
          .firstWhere((Category c) => c.name == 'Market')
          .id;

      const ScannedReceipt receipt = ScannedReceipt(
        imagePath: '/tmp/x.jpg',
        items: <ScannedItem>[
          ScannedItem(
            name: 'EKMEK',
            quantity: 1,
            unitPrice: 450,
            totalPrice: 450,
          ),
          ScannedItem(
            name: 'SÜT 1L',
            quantity: 2,
            unitPrice: 350,
            totalPrice: 700,
          ),
        ],
        total: 1150,
        currency: 'TRY',
        rawText: 'EKMEK 4,50\nSÜT 1L 7,00\nTOPLAM 11,50',
        confidenceScore: 0.92,
        storeName: 'BİM',
      );

      final Either<Failure, int> result = await liveRepo.saveReceipt(
        receipt: receipt,
        defaultCategoryId: marketId,
      );

      final int receiptId = result.getOrElse(
        () => throw StateError('expected Right'),
      );
      expect(receiptId, isPositive);

      final List<ReceiptItem> items = await db.receiptDao.getItems(receiptId);
      expect(items.length, 2);

      final List<Expense> expenses =
          await db.expenseDao.getByCategory(marketId);
      expect(expenses.length, greaterThanOrEqualTo(2));
      final int sum = expenses
          .map((Expense e) => e.amount)
          .reduce((int a, int b) => a + b);
      expect(sum, 1150);
    });

    test(
        'saveReceipt with no items but a positive total writes one expense '
        'from the receipt total', () async {
      final List<Category> cats = (await liveRepo.listCategories())
          .getOrElse(() => throw StateError('left'));
      final int marketId =
          cats.firstWhere((Category c) => c.name == 'Market').id;

      const ScannedReceipt receipt = ScannedReceipt(
        imagePath: '/tmp/x.jpg',
        items: <ScannedItem>[],
        total: 14200,
        currency: 'TRY',
        rawText: 'GÜNEŞ\nTOPLAM 142,00',
        confidenceScore: 0.4,
        storeName: 'GÜNEŞ',
      );

      final int receiptId = (await liveRepo.saveReceipt(
        receipt: receipt,
        defaultCategoryId: marketId,
      ))
          .getOrElse(() => throw StateError('expected Right'));

      final List<ReceiptItem> items = await db.receiptDao.getItems(receiptId);
      expect(items, isEmpty);

      final List<Expense> expenses =
          await db.expenseDao.getByCategory(marketId);
      expect(expenses.length, 1);
      expect(expenses.first.amount, 14200);
      expect(expenses.first.note, 'GÜNEŞ');
      expect(expenses.first.isManual, isFalse);
    });

    test('saveReceipt should skip the upload when the image is missing',
        () async {
      final List<Category> cats = (await liveRepo.listCategories())
          .getOrElse(() => throw StateError('left'));
      final int marketId =
          cats.firstWhere((Category c) => c.name == 'Market').id;

      const ScannedReceipt receipt = ScannedReceipt(
        imagePath: '/tmp/does-not-exist.jpg',
        items: <ScannedItem>[
          ScannedItem(
            name: 'EKMEK',
            quantity: 1,
            unitPrice: 450,
            totalPrice: 450,
          ),
        ],
        total: 450,
        currency: 'TRY',
        rawText: 'EKMEK 4,50',
        confidenceScore: 0.9,
        storeName: 'BİM',
      );

      await liveRepo.saveReceipt(receipt: receipt, defaultCategoryId: marketId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(
        () => storage.uploadReceiptImage(
          receiptId: any(named: 'receiptId'),
          image: any(named: 'image'),
        ),
      );
    });

    test('saveReceipt should upload and persist storageObjectPath', () async {
      final List<Category> cats = (await liveRepo.listCategories())
          .getOrElse(() => throw StateError('left'));
      final int marketId =
          cats.firstWhere((Category c) => c.name == 'Market').id;

      final File temp = File(
        '${Directory.systemTemp.path}/receipt_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await temp.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete();
      });

      when(
        () => storage.uploadReceiptImage(
          receiptId: any(named: 'receiptId'),
          image: any(named: 'image'),
        ),
      ).thenAnswer(
        (_) async => const Right<Failure, String>('user-1/1/full.jpg'),
      );

      final ScannedReceipt receipt = ScannedReceipt(
        imagePath: temp.path,
        items: const <ScannedItem>[
          ScannedItem(
            name: 'EKMEK',
            quantity: 1,
            unitPrice: 450,
            totalPrice: 450,
          ),
        ],
        total: 450,
        currency: 'TRY',
        rawText: 'EKMEK 4,50',
        confidenceScore: 0.9,
        storeName: 'BİM',
      );

      final Either<Failure, int> result = await liveRepo.saveReceipt(
        receipt: receipt,
        defaultCategoryId: marketId,
      );
      final int receiptId =
          result.getOrElse(() => throw StateError('expected Right'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(
        () => storage.uploadReceiptImage(
          receiptId: '$receiptId',
          image: any(named: 'image'),
        ),
      ).called(1);
      final Receipt? saved = await db.receiptDao.getById(receiptId);
      expect(saved?.storageObjectPath, 'user-1/1/full.jpg');
    });
  });
}
