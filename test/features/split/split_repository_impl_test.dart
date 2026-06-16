import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/data/repositories/split_repository_impl.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SplitRepositoryImpl repo;

  setUp(() {
    db = createTestDatabase();
    repo = SplitRepositoryImpl(receiptDao: db.receiptDao);
  });
  tearDown(() async => db.close());

  Future<int> seedReceipt() {
    return db.receiptDao.insertReceipt(
      ReceiptsCompanion.insert(
        storeName: const Value<String?>('Migros'),
        date: DateTime.utc(2026, 5, 20),
        total: 3000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  group('loadSession', () {
    test('should return CacheFailure when receipt is missing', () async {
      final Either<Failure, SplitSession> result = await repo.loadSession(42);
      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) =>
            expect((f as CacheFailure).code, 'SPLIT_RECEIPT_MISSING'),
        (_) => fail('expected failure'),
      );
    });

    test('should bootstrap a session from receipt items', () async {
      final int id = await seedReceipt();
      await db.receiptDao.insertItem(
        ReceiptItemsCompanion.insert(
          receiptId: id,
          name: 'Bread',
          unitPrice: 1000,
          totalPrice: 1000,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.receiptDao.insertItem(
        ReceiptItemsCompanion.insert(
          receiptId: id,
          name: 'Cheese',
          unitPrice: 2000,
          totalPrice: 2000,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final Either<Failure, SplitSession> result = await repo.loadSession(id);
      final SplitSession session = result.getOrElse(
        () => fail('expected session'),
      );
      expect(session.receiptId, id);
      expect(session.storeName, 'Migros');
      expect(session.totalMinor, 3000);
      expect(session.items, hasLength(2));
      expect(
        session.items.map((SplitItem i) => i.name),
        containsAll(<String>['Bread', 'Cheese']),
      );
    });
  });
}
