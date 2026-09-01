// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/daos/tax_obligation_dao.dart';
import 'package:smartspend/core/database/daos/tax_profile_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tax/due_date_shift.dart';
import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// How far back the calendar is generated.
///
/// Past periods are kept because a deadline missed six months ago is still
/// something the user may need to mark, and because a calendar that silently
/// forgets is worse than one that shows an old item.
const int kTaxCalendarMonthsBack = 6;

/// How far forward. Twelve months means the annual obligations appear once
/// each and the user can see next year's coming.
const int kTaxCalendarMonthsForward = 12;

/// Drift-backed [TaxRepository].
///
/// The generator lives behind this boundary: callers ask for a calendar, not
/// for a profile plus a catalog. That keeps the pure function pure — it never
/// learns about a database — and leaves exactly one place where the two are
/// joined.
class TaxRepositoryImpl implements TaxRepository {
  TaxRepositoryImpl({
    required TaxProfileDao profileDao,
    required TaxObligationDao obligationDao,
    required MarketRegistry markets,
    DateTime Function()? clock,
    Random? random,
  })  : _profileDao = profileDao,
        _obligationDao = obligationDao,
        _markets = markets,
        _now = clock ?? DateTime.now,
        _random = random ?? Random();

  final TaxProfileDao _profileDao;
  final TaxObligationDao _obligationDao;
  final MarketRegistry _markets;
  final DateTime Function() _now;
  final Random _random;

  List<TaxObligationSpec> get _catalog => _markets.active.taxObligations;

  @override
  Future<Either<Failure, TaxpayerProfile>> getProfile() async {
    try {
      return Right<Failure, TaxpayerProfile>(await _profileDao.getProfile());
    } on Object catch (e) {
      return Left<Failure, TaxpayerProfile>(
        CacheFailure(message: e.toString()),
      );
    }
  }

  @override
  Future<Either<Failure, void>> saveProfile(TaxpayerProfile profile) async {
    try {
      await _profileDao.save(profile, now: _now().toUtc());
      // Regenerating here rather than leaving it to the caller: a profile that
      // never reaches the calendar is a form the user filled in for nothing.
      await _regenerate(profile);
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  @override
  Stream<TaxCalendarSnapshot> watchCalendar() {
    return _obligationDao.watchAll().combineLatest(
          _profileDao.watchProfile(),
          _snapshot,
        );
  }

  @override
  Future<Either<Failure, void>> regenerate() async {
    try {
      await _regenerate(await _profileDao.getProfile());
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, TaxCalendarItem?>> getItem(int id) async {
    try {
      final List<TaxObligation> rows = await _obligationDao.getAll();
      final TaxObligation? row =
          rows.where((TaxObligation r) => r.id == id).firstOrNull;
      return Right<Failure, TaxCalendarItem?>(
        row == null ? null : _toItem(row),
      );
    } on Object catch (e) {
      return Left<Failure, TaxCalendarItem?>(
        CacheFailure(message: e.toString()),
      );
    }
  }

  @override
  Future<Either<Failure, void>> setDeclared(int id, DateTime? at) =>
      _write(() => _obligationDao.setDeclaredAt(id, at, now: _now().toUtc()));

  @override
  Future<Either<Failure, void>> setPaid(int id, DateTime? at) =>
      _write(() => _obligationDao.setPaidAt(id, at, now: _now().toUtc()));

  @override
  Future<Either<Failure, void>> setDismissed(int id, DateTime? at) =>
      _write(() => _obligationDao.setDismissedAt(id, at, now: _now().toUtc()));

  @override
  Future<Either<Failure, void>> setAmount(
    int id, {
    required int? amountMinor,
    required TaxAmountSource source,
  }) =>
      _write(
        () => _obligationDao.setAmount(
          id,
          amountMinor: amountMinor,
          amountSource: source.wireValue,
          now: _now().toUtc(),
        ),
      );

  @override
  Future<Either<Failure, void>> setNote(int id, String? note) =>
      _write(() => _obligationDao.setNote(id, note, now: _now().toUtc()));

  @override
  Future<Either<Failure, void>> setUserDueDates(
    int id, {
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
  }) =>
      _write(
        () => _obligationDao.setUserDueDates(
          id,
          declarationDueDate: declarationDueDate,
          paymentDueDate: paymentDueDate,
          now: _now().toUtc(),
        ),
      );

  @override
  Future<Either<Failure, int>> addCustomItem({
    required String title,
    required DateTime dueDate,
    bool isPayment = true,
    String? note,
  }) async {
    try {
      final DateTime day =
          DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
      final int id = await _obligationDao.insertUserDefined(
        generationKey: _customGenerationKey(),
        title: title,
        // A user-defined item has no statutory period. Using the deadline's
        // own month keeps it sorting alongside everything else instead of
        // needing a special case in every query.
        periodStart: DateTime.utc(day.year, day.month),
        periodEnd: DateTime.utc(day.year, day.month + 1, 0),
        declarationDueDate: isPayment ? null : day,
        paymentDueDate: isPayment ? day : null,
        note: note,
        now: _now().toUtc(),
      );
      return Right<Failure, int>(id);
    } on Object catch (e) {
      return Left<Failure, int>(CacheFailure(message: e.toString()));
    }
  }

  Future<Either<Failure, void>> _write(Future<void> Function() action) async {
    try {
      await action();
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  /// Runs the generator and folds the result into the local table.
  Future<void> _regenerate(TaxpayerProfile profile) async {
    final DateTime now = _now().toUtc();
    final TaxCalendar calendar = generateTaxCalendar(
      profile: profile,
      catalog: _catalog,
      rangeStart: DateTime.utc(now.year, now.month - kTaxCalendarMonthsBack),
      rangeEnd:
          DateTime.utc(now.year, now.month + kTaxCalendarMonthsForward, 1),
      shift: shiftDueDate,
    );

    for (final GeneratedObligation item in calendar.obligations) {
      await _obligationDao.upsertGenerated(
        generationKey: item.generationKey,
        kind: item.kind.wireValue,
        periodKind: item.periodKind.wireValue,
        periodStart: item.periodStart,
        periodEnd: item.periodEnd,
        declarationDueDate: item.declarationDueDate,
        paymentDueDate: item.paymentDueDate,
        installmentIndex: item.installmentIndex,
        now: now,
      );
    }
  }

  TaxCalendarSnapshot _snapshot(
    List<TaxObligation> rows,
    TaxpayerProfile profile,
  ) {
    final DateTime now = _now().toUtc();
    // Re-run the generator for its gaps only. It is pure and cheap, and
    // deriving them live means a wizard answer updates the "finish your
    // profile" list without a second write path.
    final TaxCalendar calendar = generateTaxCalendar(
      profile: profile,
      catalog: _catalog,
      rangeStart: DateTime.utc(now.year, now.month - kTaxCalendarMonthsBack),
      rangeEnd:
          DateTime.utc(now.year, now.month + kTaxCalendarMonthsForward, 1),
      shift: shiftDueDate,
    );

    return TaxCalendarSnapshot(
      items: rows.map(_toItem).toList(growable: false),
      gaps: calendar.gaps,
      profile: profile,
    );
  }

  /// Joins a stored row with what only the catalog knows.
  TaxCalendarItem _toItem(TaxObligation row) {
    final TaxObligationKind kind = TaxObligationKind.fromWireValue(row.kind);
    final TaxObligationSpec? spec =
        _catalog.where((TaxObligationSpec s) => s.kind == kind).firstOrNull;

    // A user-defined item has exactly the step the user gave it a date for,
    // and its dates are their own claim rather than our rule — so no hedge.
    if (row.isUserDefined || spec == null) {
      return _item(
        row: row,
        kind: kind,
        hasDeclarationStep: row.declarationDueDate != null,
        hasPaymentStep: row.paymentDueDate != null,
        isConditional: false,
        needsDateWarning: false,
      );
    }

    return _item(
      row: row,
      kind: kind,
      hasDeclarationStep: spec.declaration is! NoDueDate,
      hasPaymentStep: spec.payment is! NoDueDate,
      isConditional: spec.occursOnlyWhenTransactionsExist,
      needsDateWarning: _needsDateWarning(row, spec),
    );
  }

  /// Whether the dates on [row] have to be hedged rather than stated.
  ///
  /// Two independent reasons, and either is enough: the catalog rule is not
  /// verified against a primary source, or no holiday list exists for that
  /// year so the deadline could not be moved off a weekend. A date the user
  /// corrected themselves is exempt — it is their claim, not ours.
  bool _needsDateWarning(TaxObligation row, TaxObligationSpec spec) {
    if (TaxDueDateSource.fromWireValue(row.dueDateSource) ==
        TaxDueDateSource.user) {
      return false;
    }
    if (!spec.isVerified) {
      return true;
    }
    return <DateTime?>[row.declarationDueDate, row.paymentDueDate]
        .whereType<DateTime>()
        .any(
          (DateTime d) =>
              shiftDueDate(d).confidence != TaxDueDateConfidence.complete,
        );
  }

  TaxCalendarItem _item({
    required TaxObligation row,
    required TaxObligationKind kind,
    required bool hasDeclarationStep,
    required bool hasPaymentStep,
    required bool isConditional,
    required bool needsDateWarning,
  }) =>
      TaxCalendarItem(
        id: row.id,
        kind: kind,
        nameL10nKey: kind.l10nKey,
        title: row.title,
        periodKind: TaxPeriodKind.fromWireValue(row.periodKind),
        periodStart: row.periodStart,
        periodEnd: row.periodEnd,
        installmentIndex: row.installmentIndex,
        declarationDueDate: row.declarationDueDate,
        paymentDueDate: row.paymentDueDate,
        dueDateSource: TaxDueDateSource.fromWireValue(row.dueDateSource),
        hasDeclarationStep: hasDeclarationStep,
        hasPaymentStep: hasPaymentStep,
        isConditional: isConditional,
        needsDateWarning: needsDateWarning,
        amountMinor: row.amountMinor,
        amountSource: TaxAmountSource.fromWireValue(row.amountSource),
        declaredAt: row.declaredAt,
        paidAt: row.paidAt,
        dismissedAt: row.dismissedAt,
        note: row.note,
        isUserDefined: row.isUserDefined,
      );

  /// A generation key for an item the catalog did not produce.
  ///
  /// Random rather than derived from the title and date: two custom items can
  /// legitimately share both, and a collision would make one silently
  /// overwrite the other.
  String _customGenerationKey() {
    final int stamp = _now().toUtc().microsecondsSinceEpoch;
    final int salt = _random.nextInt(1 << 32);
    return 'custom|$stamp|$salt';
  }
}
