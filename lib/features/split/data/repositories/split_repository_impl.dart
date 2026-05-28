import 'package:dartz/dartz.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/repositories/split_repository.dart';

/// Drift-backed [SplitRepository] implementation.
///
/// Reads the receipt + its non-deleted items via `ReceiptDao` and
/// projects them into a session-ready [SplitSession]. No writes — the
/// session lives in `SplitBloc` only.
class SplitRepositoryImpl implements SplitRepository {
  const SplitRepositoryImpl({required ReceiptDao receiptDao})
      : _dao = receiptDao;

  final ReceiptDao _dao;

  @override
  Future<Either<Failure, SplitSession>> loadSession(int receiptId) async {
    try {
      final drift_db.Receipt? receipt = await _dao.getById(receiptId);
      if (receipt == null) {
        return const Left<Failure, SplitSession>(
          CacheFailure(
            message: 'split.receipt.missing',
            code: 'SPLIT_RECEIPT_MISSING',
          ),
        );
      }
      final List<drift_db.ReceiptItem> rows = await _dao.getItems(receiptId);
      final List<SplitItem> items = rows
          .map(
            (drift_db.ReceiptItem r) => SplitItem(
              id: r.id,
              name: r.name,
              totalPriceMinor: r.totalPrice,
            ),
          )
          .toList(growable: false);
      return Right<Failure, SplitSession>(
        SplitSession.bootstrap(
          receiptId: receipt.id,
          storeName: receipt.storeName,
          receiptDate: receipt.date,
          currency: receipt.currency,
          totalMinor: receipt.total,
          items: items,
        ),
      );
    } on Object catch (e) {
      return Left<Failure, SplitSession>(
        CacheFailure(message: e.toString()),
      );
    }
  }
}
