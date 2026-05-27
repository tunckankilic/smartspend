import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';

class CreateCategoryParams extends Equatable {
  const CreateCategoryParams({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final int color;

  @override
  List<Object?> get props => <Object?>[name, icon, color];
}

/// Insert a user-defined category and return the persisted row.
class CreateCategoryUseCase {
  const CreateCategoryUseCase(this._repository);

  final CategoryRepository _repository;

  Future<Either<Failure, Category>> call(CreateCategoryParams params) {
    return _repository.createCustom(
      name: params.name,
      icon: params.icon,
      color: params.color,
    );
  }
}
