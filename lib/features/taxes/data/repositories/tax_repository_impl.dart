// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:stream_transform/stream_transform.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/daos/tax_calendar_override_dao.dart';
import 'package:smartspend/core/database/daos/tax_obligation_dao.dart';
import 'package:smartspend/core/database/daos/tax_profile_dao.dart';
import 'package:smartspend/core/database/daos/user_settings_dao.dart';
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
import 'package:smartspend/core/services/tax_override_remote_data_source.dart';
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

/// Shortest gap between two override pulls.
///
/// Six hours, not six minutes: an extension is announced days ahead of the
/// deadline it moves, so the channel has no need to be fast, and a launch is
/// the wrong moment to spend a round trip the user did not ask for. The
/// calendar's pull-to-refresh bypasses this — a user who suspects the date is
/// stale should not have to wait it out.
const Duration kTaxOverridePullInterval = Duration(hours: 6);

/// [UserSettings] key holding the last successful pull, ISO-8601 UTC.
///
/// Persisted rather than held in memory: the throttle is about not pestering
/// the server on every launch, and an in-memory one resets on exactly the
/// event it is meant to damp.
const String kTaxOverrideLastPullKey = 'tax_overrides_last_pull_at';

/// The two halves of a snapshot, carried between the two `combineLatest`
/// stages. A plain record would do; a named class keeps the stream expression
/// readable.
class _PendingSnapshot {
  const _PendingSnapshot(this.rows, this.profile);

  final List<TaxObligation> rows;
  final TaxpayerProfile profile;
}

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
    required TaxCalendarOverrideDao overrideDao,
    required UserSettingsDao settingsDao,
    required MarketRegistry markets,
    TaxOverrideRemoteDataSource? overrideRemote,
    DateTime Function()? clock,
    Random? random,
  })  : _profileDao = profileDao,
        _obligationDao = obligationDao,
        _overrideDao = overrideDao,
        _settingsDao = settingsDao,
        _markets = markets,
        _overrideRemote = overrideRemote,
        _now = clock ?? DateTime.now,
        _random = random ?? Random();

  final TaxProfileDao _profileDao;
  final TaxObligationDao _obligationDao;
  final TaxCalendarOverrideDao _overrideDao;
  final UserSettingsDao _settingsDao;
  final MarketRegistry _markets;

  /// Null in builds and tests with no Supabase client. The calendar works
  /// without it — every date simply comes from the shipped catalog — so this
  /// is an absent capability, not a broken dependency.
  final TaxOverrideRemoteDataSource? _overrideRemote;

  final DateTime Function() _now;
  final Random _random;

  /// The market whose catalog is in force, and the only one whose overrides
  /// this device applies.
  String get _market => _markets.active.countryCode.toUpperCase();

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
    // Three streams, not two. The overrides are in here so that a pull landing
    // mid-session refreshes the reason shown beside a corrected date without
    // the puller needing to know who is watching.
    return _obligationDao
        .watchAll()
        .combineLatest(
          _profileDao.watchProfile(),
          _PendingSnapshot.new,
        )
        .combineLatest(
          _overrideDao.watchAll(),
          (_PendingSnapshot pending, List<TaxCalendarOverride> overrides) =>
              _snapshot(pending.rows, pending.profile, overrides),
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
      final Map<String, TaxCalendarOverride> overrides =
          _byKey(await _overrideDao.getForMarket(_market));
      return Right<Failure, TaxCalendarItem?>(
        row == null ? null : _toItem(row, overrides),
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

  /// Runs the generator, applies the published overrides, and folds the result
  /// into the local table.
  ///
  /// 🚨 THIS IS WHERE AN OVERRIDE IS APPLIED, and it is deliberately not
  /// anywhere else (D-17). `upsertGenerated` preserves only a *user*-entered
  /// date; an override written straight into the calendar would be overwritten
  /// by the next regeneration, and regeneration happens on every app launch —
  /// the extension would appear to arrive and silently cancel itself
  /// overnight. Teaching `upsertGenerated` to protect overrides too would fix
  /// that and buy a worse bug: a correction the publisher later withdraws
  /// could never be taken back, because the date would be frozen out of reach
  /// of the only mechanism that writes it.
  ///
  /// Applying here instead keeps the precedence one readable rule —
  /// **user > override > catalog** — and keeps `due_date_source` derived, so
  /// deleting the server row reverts the date on the next run.
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
    final Map<String, TaxCalendarOverride> overrides =
        _byKey(await _overrideDao.getForMarket(_market));

    for (final GeneratedObligation item in calendar.obligations) {
      final TaxCalendarOverride? override = overrides[_overrideKey(
        kind: item.kind.wireValue,
        periodStart: item.periodStart,
        installmentIndex: item.installmentIndex,
      )];

      // A null column on an override means "this deadline is not overridden",
      // never "this deadline is removed" — so each date falls back to the
      // catalog's independently. An extension that moves only the filing date
      // must leave the payment date alone.
      await _obligationDao.upsertGenerated(
        generationKey: item.generationKey,
        kind: item.kind.wireValue,
        periodKind: item.periodKind.wireValue,
        periodStart: item.periodStart,
        periodEnd: item.periodEnd,
        declarationDueDate:
            override?.declarationDueDate ?? item.declarationDueDate,
        paymentDueDate: override?.paymentDueDate ?? item.paymentDueDate,
        dueDateSource: override == null
            ? TaxDueDateSource.catalog.wireValue
            : TaxDueDateSource.override.wireValue,
        installmentIndex: item.installmentIndex,
        now: now,
      );
    }
  }

  @override
  Future<Either<Failure, void>> refreshOverrides({bool force = false}) async {
    final TaxOverrideRemoteDataSource? remote = _overrideRemote;
    // No remote configured is not a failure: the calendar runs on the shipped
    // catalog, which is what it did before this channel existed.
    if (remote == null) {
      return const Right<Failure, void>(null);
    }
    try {
      if (!force && !await _pullIsDue()) {
        return const Right<Failure, void>(null);
      }
      final String market = _market;
      final List<Map<String, dynamic>> rows =
          await remote.fetchOverrides(market);

      // Parsed before anything is deleted. A malformed response must not be
      // able to empty the table on its way to failing.
      final List<TaxCalendarOverridesCompanion> parsed = rows
          .map((Map<String, dynamic> row) => _parseOverride(row, market))
          .whereType<TaxCalendarOverridesCompanion>()
          .toList(growable: false);

      // A response we could not read a single row of is not the same as a
      // response saying there are none. Emptying the table on it would let a
      // format change on the server silently retract every correction — the
      // one failure this channel cannot afford, because it looks like success.
      if (rows.isNotEmpty && parsed.isEmpty) {
        return Left<Failure, void>(
          ServerFailure(
            message: 'tax_calendar_overrides: '
                '${rows.length} row(s) returned, none usable',
          ),
        );
      }

      await _overrideDao.replaceMarket(market, parsed);
      await _settingsDao.setValue(
        kTaxOverrideLastPullKey,
        _now().toUtc().toIso8601String(),
      );
      // The pull only changed the corrections; the dates the user sees live on
      // the obligation rows, so they are stale until this runs.
      await _regenerate(await _profileDao.getProfile());
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(NetworkFailure(message: e.toString()));
    }
  }

  /// Whether enough time has passed since the last successful pull.
  ///
  /// A missing or unparseable stamp means "never pulled", which is the safe
  /// answer: pulling once more costs a request, and skipping forever costs the
  /// user a deadline.
  Future<bool> _pullIsDue() async {
    final String? raw = await _settingsDao.getValue(kTaxOverrideLastPullKey);
    if (raw == null) {
      return true;
    }
    final DateTime? last = DateTime.tryParse(raw)?.toUtc();
    if (last == null) {
      return true;
    }
    return _now().toUtc().difference(last) >= kTaxOverridePullInterval;
  }

  /// Turns one server row into a local companion, or null when it is not
  /// usable.
  ///
  /// Dropped rather than thrown on, and one bad row does not discard the rest:
  /// a response the client cannot read should cost at most the corrections it
  /// could not parse. A row with no reason is dropped even though the server
  /// requires one — the column is what makes a moved date checkable, and a
  /// date that moved for no stated reason is exactly what this feature must
  /// not produce.
  TaxCalendarOverridesCompanion? _parseOverride(
    Map<String, dynamic> row,
    String market,
  ) {
    final String? id = row['id'] as String?;
    final String? kind = row['kind'] as String?;
    final DateTime? periodStart = _parseDate(row['period_start']);
    final String? reason = row['reason'] as String?;
    if (id == null ||
        kind == null ||
        periodStart == null ||
        reason == null ||
        reason.isEmpty) {
      return null;
    }

    final DateTime? declaration = _parseDate(row['declaration_due_date']);
    final DateTime? payment = _parseDate(row['payment_due_date']);
    // An override that moves neither date has nothing to say, and storing it
    // would stamp the row `override` for no visible change.
    if (declaration == null && payment == null) {
      return null;
    }

    return TaxCalendarOverridesCompanion.insert(
      remoteId: id,
      market: market,
      kind: kind,
      periodStart: periodStart,
      installmentIndex: Value<int>((row['installment_index'] as int?) ?? 0),
      declarationDueDate: Value<DateTime?>(declaration),
      paymentDueDate: Value<DateTime?>(payment),
      reason: reason,
      sourceUrl: Value<String?>(row['source_url'] as String?),
      fetchedAt: _now().toUtc(),
    );
  }

  /// Reads a PostgREST `date` as UTC midnight.
  ///
  /// Rebuilt through [DateTime.utc] rather than used as parsed: a bare
  /// `2026-09-30` parses as local midnight, which in a negative-offset zone is
  /// the previous day once converted — a deadline shown one day early.
  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return null;
    }
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  Map<String, TaxCalendarOverride> _byKey(List<TaxCalendarOverride> rows) {
    return <String, TaxCalendarOverride>{
      for (final TaxCalendarOverride row in rows)
        _overrideKey(
          kind: row.kind,
          periodStart: row.periodStart,
          installmentIndex: row.installmentIndex,
        ): row,
    };
  }

  /// Addresses one generated item. Mirrors the server's
  /// `(kind, period_start, installment_index)` unique key.
  String _overrideKey({
    required String kind,
    required DateTime periodStart,
    required int installmentIndex,
  }) {
    final DateTime day = periodStart.toUtc();
    final String month = day.month.toString().padLeft(2, '0');
    final String dayOfMonth = day.day.toString().padLeft(2, '0');
    return '$kind|${day.year}-$month-$dayOfMonth|$installmentIndex';
  }

  TaxCalendarSnapshot _snapshot(
    List<TaxObligation> rows,
    TaxpayerProfile profile,
    List<TaxCalendarOverride> overrideRows,
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

    final Map<String, TaxCalendarOverride> overrides = _byKey(
      overrideRows
          .where((TaxCalendarOverride o) => o.market == _market)
          .toList(growable: false),
    );

    return TaxCalendarSnapshot(
      items: rows
          .map((TaxObligation row) => _toItem(row, overrides))
          .toList(growable: false),
      gaps: calendar.gaps,
      profile: profile,
    );
  }

  /// Joins a stored row with what only the catalog and the overrides know.
  TaxCalendarItem _toItem(
    TaxObligation row,
    Map<String, TaxCalendarOverride> overrides,
  ) {
    final TaxObligationKind kind = TaxObligationKind.fromWireValue(row.kind);
    final TaxObligationSpec? spec =
        _catalog.where((TaxObligationSpec s) => s.kind == kind).firstOrNull;

    // Only attach a reason when the row actually says its dates came from an
    // override. A row still carrying a withdrawn correction — pulled, but not
    // yet regenerated — would otherwise be captioned with a reason that no
    // longer applies.
    final String? reason =
        TaxDueDateSource.fromWireValue(row.dueDateSource) ==
                TaxDueDateSource.override
            ? overrides[_overrideKey(
                kind: row.kind,
                periodStart: row.periodStart,
                installmentIndex: row.installmentIndex,
              )]
                ?.reason
            : null;

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
        overrideReason: reason,
      );
    }

    return _item(
      row: row,
      kind: kind,
      hasDeclarationStep: spec.declaration is! NoDueDate,
      hasPaymentStep: spec.payment is! NoDueDate,
      isConditional: spec.occursOnlyWhenTransactionsExist,
      needsDateWarning: _needsDateWarning(row, spec),
      overrideReason: reason,
    );
  }

  /// Whether the dates on [row] have to be hedged rather than stated.
  ///
  /// Two independent reasons, and either is enough: the catalog rule is not
  /// verified against a primary source, or no holiday list exists for that
  /// year so the deadline could not be moved off a weekend. A date the user
  /// corrected themselves is exempt — it is their claim, not ours.
  ///
  /// 🚨 An OVERRIDE IS NOT EXEMPT. It is still a date we published, not one
  /// the user's accountant confirmed to them, and the hedge is about who is
  /// answerable for it rather than about how confident we feel. The reason
  /// string travels with it so the user can check the circular themselves;
  /// that is the honest version of certainty here.
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
    String? overrideReason,
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
        dueDateOverrideReason: overrideReason,
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
