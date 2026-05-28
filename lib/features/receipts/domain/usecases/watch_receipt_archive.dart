import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';

/// Reactive read of the receipt archive (Sprint 7).
///
/// Doesn't match the `UseCase<T, Params>` shape because the underlying
/// repo returns a `Stream<List<T>>`, not a `Future<Either<...>>` —
/// follows the same convention as `WatchBudgetsUseCase` (Sprint 6).
class WatchReceiptArchiveUseCase {
  const WatchReceiptArchiveUseCase(this._repository);

  final ReceiptArchiveRepository _repository;

  Stream<List<ReceiptArchiveEntry>> call(ReceiptArchiveFilter filter) {
    return _repository.watchArchive(filter);
  }
}
