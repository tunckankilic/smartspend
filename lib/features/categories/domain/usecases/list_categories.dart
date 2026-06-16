import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';

class ListCategoriesParams extends Equatable {
  const ListCategoriesParams();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Fetch all categories (seed + custom) ordered by `sortOrder`.
class ListCategoriesUseCase {
  const ListCategoriesUseCase(this._repository);

  final CategoryRepository _repository;

  Future<Either<Failure, List<Category>>> call(
    ListCategoriesParams params,
  ) {
    return _repository.listAll();
  }
}
