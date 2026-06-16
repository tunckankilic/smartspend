import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/data/repositories/category_repository_impl.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = CategoryRepositoryImpl(categoryDao: db.categoryDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('listAll', () {
    test('should return the 15 seeded defaults sorted by sortOrder', () async {
      final Either<Failure, List<Category>> result = await repo.listAll();

      expect(result.isRight(), isTrue);
      final List<Category> cats = result.getOrElse(() => <Category>[]);
      expect(cats.length, 15);
      expect(cats.first.name, 'Market');
      expect(cats.any((Category c) => c.icon == 'shopping_cart'), isTrue);
    });

    test('should map Drift rows into domain Category entities', () async {
      final Either<Failure, List<Category>> result = await repo.listAll();
      final List<Category> cats = result.getOrElse(() => <Category>[]);
      final Category market =
          cats.firstWhere((Category c) => c.name == 'Market');

      expect(market.icon, 'shopping_cart');
      expect(market.isCustom, isFalse);
      expect(market.color, isNonZero);
    });
  });

  group('findById', () {
    test('should return the matching category', () async {
      final List<Category> all = (await repo.listAll())
          .getOrElse(() => const <Category>[]);
      final Category market =
          all.firstWhere((Category c) => c.name == 'Market');

      final Either<Failure, Category?> result = await repo.findById(market.id);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => null)?.name, 'Market');
    });

    test('should return null when no row matches', () async {
      final Either<Failure, Category?> result = await repo.findById(99999);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => const Category(
            id: -1,
            name: '',
            icon: '',
            color: 0,
            isCustom: false,
          )), isNull);
    });
  });

  group('createCustom', () {
    test('should insert a row and return the persisted Category', () async {
      final Either<Failure, Category> result = await repo.createCustom(
        name: 'Hobi',
        icon: 'more_horiz',
        color: 0xFF123456,
      );

      expect(result.isRight(), isTrue);
      final Category created = result.getOrElse(() => const Category(
            id: -1,
            name: '',
            icon: '',
            color: 0,
            isCustom: false,
          ));
      expect(created.name, 'Hobi');
      expect(created.icon, 'more_horiz');
      expect(created.color, 0xFF123456);
      expect(created.isCustom, isTrue);
      expect(created.id, isPositive);
    });

    test('should append the new row after the defaults in listAll',
        () async {
      await repo.createCustom(
        name: 'Yatırım',
        icon: 'more_horiz',
        color: 0xFF999999,
      );

      final List<Category> all = (await repo.listAll())
          .getOrElse(() => const <Category>[]);
      expect(all.length, 16);
      expect(all.last.name, 'Yatırım');
      expect(all.last.isCustom, isTrue);
    });

    test('should allow multiple inserts with increasing sortOrder',
        () async {
      await repo.createCustom(
        name: 'Kurslar',
        icon: 'more_horiz',
        color: 0xFF111111,
      );
      await repo.createCustom(
        name: 'Bağış',
        icon: 'card_giftcard',
        color: 0xFF222222,
      );

      final List<Category> all = (await repo.listAll())
          .getOrElse(() => const <Category>[]);
      expect(all.length, 17);
      expect(all[15].name, 'Kurslar');
      expect(all[16].name, 'Bağış');
    });
  });

  group('watchAll', () {
    test('should emit the current snapshot immediately', () async {
      final List<Category> first = await repo.watchAll().first;

      expect(first.length, 15);
      expect(first.first.name, 'Market');
    });

    test('should emit a new snapshot after a custom insert', () async {
      final Stream<List<Category>> stream = repo.watchAll();
      final List<List<Category>> emissions = <List<Category>>[];
      final subscription = stream.listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.createCustom(
        name: 'Çocuk',
        icon: 'pets',
        color: 0xFF333333,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.last.name, 'Çocuk');
    });
  });
}
