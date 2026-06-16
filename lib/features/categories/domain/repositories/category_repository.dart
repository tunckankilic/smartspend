import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';

/// Abstract surface for the `categories` table.
///
/// Hoisted in Sprint 4 so presentation-layer code (e.g. `AddExpenseBloc`,
/// `ExpenseListPage`) stops reaching into [CategoryDao] directly. The
/// implementation wraps the dao and maps Drift rows into the domain
/// [Category] entity so callers never see Drift types.
abstract class CategoryRepository {
  /// All categories (seeded defaults + user-created), ordered by
  /// `sortOrder`.
  Future<Either<Failure, List<Category>>> listAll();

  /// One row by primary key, or `null` if not found.
  Future<Either<Failure, Category?>> findById(int id);

  /// Persist a new user-defined category and return the resulting row.
  /// The icon must be a key in `kCategoryIcons`; colours are packed ARGB.
  Future<Either<Failure, Category>> createCustom({
    required String name,
    required String icon,
    required int color,
  });

  /// Reactive stream of the full category list. Emits on every insert
  /// or update.
  Stream<List<Category>> watchAll();
}
