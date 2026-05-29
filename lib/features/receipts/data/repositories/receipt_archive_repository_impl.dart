import 'package:dartz/dartz.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';

/// Drift-backed [ReceiptArchiveRepository] (Sprint 7).
///
/// All reads target the local Drift mirror — Sprint 8 will layer
/// Supabase pull-on-tick on top via `SyncService`. The `drift_db` alias
/// keeps the generated `Receipt`/`ReceiptItem` row classes from
/// shadowing domain entities.
class ReceiptArchiveRepositoryImpl implements ReceiptArchiveRepository {
  const ReceiptArchiveRepositoryImpl({
    required ReceiptDao receiptDao,
    required SupabaseStorageDataSource storageDataSource,
  })  : _dao = receiptDao,
        _storage = storageDataSource;

  final ReceiptDao _dao;
  final SupabaseStorageDataSource _storage;

  @override
  Stream<List<ReceiptArchiveEntry>> watchArchive(
    ReceiptArchiveFilter filter,
  ) {
    final Stream<List<drift_db.Receipt>> stream = filter.isEmpty
        ? _dao.watchAll()
        : _dao.watchFiltered(
            searchQuery: filter.searchQuery,
            from: filter.from,
            to: filter.to,
          );
    return stream.map(
      (List<drift_db.Receipt> rows) =>
          rows.map(_toEntry).toList(growable: false),
    );
  }

  @override
  Future<Either<Failure, ReceiptDetail>> getDetail(int receiptId) async {
    try {
      final drift_db.Receipt? receipt = await _dao.getById(receiptId);
      if (receipt == null) {
        return const Left<Failure, ReceiptDetail>(
          CacheFailure(
            message: 'archive.receipt.missing',
            code: 'ARCHIVE_RECEIPT_MISSING',
          ),
        );
      }
      final List<drift_db.ReceiptItem> rows = await _dao.getItems(receiptId);
      return Right<Failure, ReceiptDetail>(
        ReceiptDetail(
          id: receipt.id,
          storeName: receipt.storeName,
          date: receipt.date,
          totalMinor: receipt.total,
          currency: receipt.currency,
          imagePath: receipt.imagePath,
          storageObjectPath: receipt.storageObjectPath,
          warrantyEndDate: receipt.warrantyEndDate,
          items: rows
              .map(
                (drift_db.ReceiptItem r) => ReceiptDetailItem(
                  id: r.id,
                  name: r.name,
                  quantity: r.quantity,
                  unitPriceMinor: r.unitPrice,
                  totalPriceMinor: r.totalPrice,
                ),
              )
              .toList(growable: false),
        ),
      );
    } on Object catch (e) {
      return Left<Failure, ReceiptDetail>(
        CacheFailure(message: e.toString()),
      );
    }
  }

  @override
  Future<Either<Failure, String>> getReceiptImageUrl(String objectPath) {
    return _storage.getSignedUrl(objectPath);
  }

  @override
  Future<Either<Failure, void>> setWarrantyEndDate(
    int receiptId,
    DateTime? endDate,
  ) async {
    try {
      await _dao.setWarrantyEndDate(receiptId, endDate);
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  ReceiptArchiveEntry _toEntry(drift_db.Receipt row) {
    return ReceiptArchiveEntry(
      id: row.id,
      storeName: row.storeName,
      date: row.date,
      totalMinor: row.total,
      currency: row.currency,
      imagePath: row.imagePath,
      warrantyEndDate: row.warrantyEndDate,
    );
  }
}
