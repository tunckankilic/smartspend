import 'package:equatable/equatable.dart';

/// Captures a user overriding a suggested category for a given store.
///
/// Sprint 4 only defines the entity + the use case that emits it as a
/// Sentry breadcrumb; Sprint 6 will persist these in a `user_corrections`
/// Drift table and feed them into [HybridCategorizationEngine] so the
/// engine "learns" per-user store mappings.
class UserCorrection extends Equatable {
  const UserCorrection({
    required this.storeName,
    required this.oldCategoryId,
    required this.newCategoryId,
    required this.occurredAt,
  });

  final String storeName;
  final int? oldCategoryId;
  final int newCategoryId;
  final DateTime occurredAt;

  @override
  List<Object?> get props =>
      <Object?>[storeName, oldCategoryId, newCategoryId, occurredAt];
}
