import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/receipts/data/repositories/receipt_archive_repository_impl.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';

import '../../helpers/test_database.dart';

class _MockStorage extends Mock implements SupabaseStorageDataSource {}

void main() {
  late AppDatabase db;
  late _MockStorage storage;
  late ReceiptArchiveRepositoryImpl repo;

  setUp(() {
    db = createTestDatabase();
    storage = _MockStorage();
    repo = ReceiptArchiveRepositoryImpl(
      receiptDao: db.receiptDao,
      storageDataSource: storage,
    );
  });
  tearDown(() async => db.close());

  Future<int> seedReceipt({String store = 'Migros'}) {
    return db.receiptDao.insertReceipt(
      ReceiptsCompanion.insert(
        storeName: Value<String?>(store),
        date: DateTime.utc(2026, 5, 20),
        total: 5000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  group('watchArchive', () {
    test('should stream all entries when filter is empty', () async {
      await seedReceipt(store: 'A101');
      final List<ReceiptArchiveEntry> entries =
          await repo.watchArchive(ReceiptArchiveFilter.empty).first;
      expect(entries, hasLength(1));
      expect(entries.first.storeName, 'A101');
    });

    test('should stream filtered entries when filter has a query', () async {
      await seedReceipt(store: 'Migros');
      await seedReceipt(store: 'BIM');
      final List<ReceiptArchiveEntry> entries = await repo
          .watchArchive(const ReceiptArchiveFilter(searchQuery: 'migros'))
          .first;
      expect(entries, hasLength(1));
      expect(entries.first.storeName, 'Migros');
    });
  });

  group('getDetail', () {
    test('should return CacheFailure when receipt is missing', () async {
      final Either<Failure, ReceiptDetail> result = await repo.getDetail(999);
      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f, isA<CacheFailure>()),
        (_) => fail('expected failure'),
      );
    });

    test('should return detail with items when receipt exists', () async {
      final int id = await seedReceipt();
      await db.receiptDao.insertItem(
        ReceiptItemsCompanion.insert(
          receiptId: id,
          name: 'Milk',
          unitPrice: 1000,
          totalPrice: 2000,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      final Either<Failure, ReceiptDetail> result = await repo.getDetail(id);
      final ReceiptDetail detail = result.getOrElse(
        () => fail('expected detail'),
      );
      expect(detail.id, id);
      expect(detail.items, hasLength(1));
      expect(detail.items.first.name, 'Milk');
    });
  });

  group('getReceiptImageUrl', () {
    test('should delegate to storage data source', () async {
      when(() => storage.getSignedUrl(any()))
          .thenAnswer((_) async => const Right<Failure, String>('https://x'));
      final Either<Failure, String> result =
          await repo.getReceiptImageUrl('user/1/full.jpg');
      expect(result.getOrElse(() => ''), 'https://x');
      verify(() => storage.getSignedUrl('user/1/full.jpg')).called(1);
    });
  });

  group('setWarrantyEndDate', () {
    test('should persist warranty date and return Right', () async {
      final int id = await seedReceipt();
      final DateTime end = DateTime.utc(2027, 1, 1);
      final Either<Failure, void> result =
          await repo.setWarrantyEndDate(id, end);
      expect(result.isRight(), isTrue);
      final Receipt? row = await db.receiptDao.getById(id);
      expect(row!.warrantyEndDate, end);
    });
  });
}
