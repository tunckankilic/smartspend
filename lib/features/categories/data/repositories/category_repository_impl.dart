import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/app_database.dart'
    show CategoriesCompanion;
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';

/// Drift-backed implementation of [CategoryRepository].
///
/// Wraps [CategoryDao]; never leaks Drift types past its API. Sprint 8
/// will add a Supabase remote datasource alongside the local one and
/// route writes through the sync queue — this class is the seam where
/// that wiring lands.
class CategoryRepositoryImpl implements CategoryRepository {
  const CategoryRepositoryImpl({required CategoryDao categoryDao})
      : _dao = categoryDao;

  final CategoryDao _dao;

  @override
  Future<Either<Failure, List<Category>>> listAll() async {
    try {
      final List<drift_db.Category> rows = await _dao.getAll();
      return Right<Failure, List<Category>>(rows.map(_toEntity).toList());
    } on Exception catch (e) {
      return Left<Failure, List<Category>>(
        CacheFailure(message: 'listAll failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, Category?>> findById(int id) async {
    try {
      final drift_db.Category? row = await _dao.getById(id);
      return Right<Failure, Category?>(row == null ? null : _toEntity(row));
    } on Exception catch (e) {
      return Left<Failure, Category?>(
        CacheFailure(message: 'findById failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, Category>> createCustom({
    required String name,
    required String icon,
    required int color,
  }) async {
    try {
      final List<drift_db.Category> existing = await _dao.getAll();
      final int sortOrder = existing.length + 1;
      final int id = await _dao.insertCustom(
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
        CacheFailure(message: 'createCustom failed: $e'),
      );
    }
  }

  @override
  Stream<List<Category>> watchAll() {
    return _dao
        .watchAll()
        .map(
          (List<drift_db.Category> rows) =>
              rows.map(_toEntity).toList(growable: false),
        );
  }

  Category _toEntity(drift_db.Category c) => Category(
        id: c.id,
        name: c.name,
        icon: c.icon,
        color: c.color,
        isCustom: c.isCustom,
      );
}
