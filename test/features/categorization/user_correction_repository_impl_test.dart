import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart'
    show AppDatabase, Category;
import 'package:smartspend/core/database/daos/user_correction_dao.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/data/repositories/user_correction_repository_impl.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';

import '../../helpers/test_database.dart';

class _MockDao extends Mock implements UserCorrectionDao {}

void main() {
  late AppDatabase db;
  late UserCorrectionRepositoryImpl repo;
  late int categoryId;

  setUp(() async {
    db = createTestDatabase();
    repo = UserCorrectionRepositoryImpl(dao: db.userCorrectionDao);
    final List<Category> defaults = await db.categoryDao.getDefaults();
    categoryId = defaults.first.id;
  });
  tearDown(() async => db.close());

  group('record', () {
    test('should persist a correction and return Right(unit)', () async {
      final Either<Failure, Unit> result = await repo.record(
        UserCorrection(
          storeName: 'Migros',
          oldCategoryId: null,
          newCategoryId: categoryId,
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(result.isRight(), isTrue);
      final Either<Failure, UserCorrection?> top = await repo.topForStore(
        'Migros',
      );
      expect(top.getOrElse(() => null), isNotNull);
    });
  });

  group('topForStore', () {
    test('should return null when nothing recorded for the store', () async {
      final Either<Failure, UserCorrection?> result = await repo.topForStore(
        'Unknown',
      );
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => _sentinel), isNull);
    });

    test('should return the mapped domain correction', () async {
      await repo.record(
        UserCorrection(
          storeName: 'BIM',
          oldCategoryId: null,
          newCategoryId: categoryId,
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      );
      final UserCorrection? mapped = (await repo.topForStore(
        'BIM',
      )).getOrElse(() => null);
      expect(mapped, isNotNull);
      expect(mapped!.storeName, 'BIM');
      expect(mapped.newCategoryId, categoryId);
    });
  });

  group('failure mapping', () {
    late _MockDao dao;
    late UserCorrectionRepositoryImpl failing;

    final UserCorrection correction = UserCorrection(
      storeName: 'Migros',
      oldCategoryId: null,
      newCategoryId: 1,
      occurredAt: DateTime.utc(2026, 5, 1),
    );

    setUp(() {
      dao = _MockDao();
      failing = UserCorrectionRepositoryImpl(dao: dao);
    });

    test('should map CacheException from record to CacheFailure', () async {
      when(
        () => dao.upsertCorrection(
          storeName: any(named: 'storeName'),
          oldCategoryId: any(named: 'oldCategoryId'),
          newCategoryId: any(named: 'newCategoryId'),
          occurredAt: any(named: 'occurredAt'),
        ),
      ).thenThrow(const CacheException(message: 'disk full'));

      final Either<Failure, Unit> result = await failing.record(correction);
      expect(result.isLeft(), isTrue);
    });

    test('should wrap unexpected record errors in CacheFailure', () async {
      when(
        () => dao.upsertCorrection(
          storeName: any(named: 'storeName'),
          oldCategoryId: any(named: 'oldCategoryId'),
          newCategoryId: any(named: 'newCategoryId'),
          occurredAt: any(named: 'occurredAt'),
        ),
      ).thenThrow(StateError('boom'));

      final Either<Failure, Unit> result = await failing.record(correction);
      expect(result.isLeft(), isTrue);
    });

    test(
      'should map CacheException from topForStore to CacheFailure',
      () async {
        when(
          () => dao.getTopCorrectionForStore(any()),
        ).thenThrow(const CacheException(message: 'disk full'));

        final Either<Failure, UserCorrection?> result = await failing
            .topForStore('Migros');
        expect(result.isLeft(), isTrue);
      },
    );

    test('should wrap unexpected topForStore errors in CacheFailure', () async {
      when(
        () => dao.getTopCorrectionForStore(any()),
      ).thenThrow(StateError('boom'));

      final Either<Failure, UserCorrection?> result = await failing.topForStore(
        'Migros',
      );
      expect(result.isLeft(), isTrue);
    });
  });
}

/// Non-null fallback so `getOrElse` returning `null` proves the repository
/// produced a null (the "no correction" case) rather than the fallback.
final UserCorrection _sentinel = UserCorrection(
  storeName: 'sentinel',
  oldCategoryId: null,
  newCategoryId: -1,
  occurredAt: DateTime.utc(1970),
);
