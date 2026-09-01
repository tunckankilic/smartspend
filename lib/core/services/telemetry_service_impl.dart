import 'dart:async';
import 'dart:math';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/services/telemetry_remote_data_source.dart';
import 'package:smartspend/core/services/telemetry_service.dart';

/// Drift-backed [TelemetryService].
///
/// Counters accumulate locally and go out on the back of the sync engine's
/// existing triggers — see [start] for why it listens rather than being called.
class TelemetryServiceImpl implements TelemetryService {
  TelemetryServiceImpl({
    required this.database,
    required this.remote,
    required this.syncService,
    DateTime Function()? clock,
    Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final AppDatabase database;
  final TelemetryRemoteDataSource remote;
  final SyncService syncService;

  final DateTime Function() _clock;
  final Random _random;

  /// Opt-out flag. Absent means on (D-15).
  static const String kEnabledKey = 'telemetry.enabled';

  /// Random per-install id. Generated on first use, never derived from
  /// hardware — IDFV, Android ID and advertising ids are all out of bounds.
  static const String kDeviceIdKey = 'telemetry.deviceId';

  /// Rows per upload. Counters are few (a handful of events per day), so this
  /// only ever bites after a long offline stretch; the remainder goes out on
  /// the next flush rather than in one oversized request.
  static const int kMaxRowsPerFlush = 500;

  /// Uploaded counters older than this are deleted locally. Their day can no
  /// longer be incremented, so keeping them is pure data-at-rest with no use.
  /// The margin absorbs clock skew and the UTC-midnight boundary.
  static const Duration kLocalRetention = Duration(days: 7);

  StreamSubscription<SyncPhase>? _phaseSub;
  SyncPhase? _lastPhase;
  bool _started = false;
  bool _flushing = false;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Flushes whenever the sync engine finishes a run.
  ///
  /// Telemetry listens to the sync engine rather than the engine calling
  /// telemetry: the dependency points one way only, so `SyncService` — the
  /// riskiest file in the project — does not grow a reason to know that
  /// telemetry exists. Riding its phase stream also inherits its connectivity
  /// and interval triggers for free, with no second timer.
  ///
  /// Only the transition *into* [SyncPhaseSynced] fires a flush. A settled
  /// `Synced` phase is also what the stream replays to every new subscriber,
  /// so keying on the transition avoids flushing merely because someone
  /// started listening. And requiring `Synced` specifically — not `Pending`,
  /// not `Offline` — means a flush is only attempted right after the app has
  /// demonstrably reached the server.
  @override
  void start() {
    if (_started) return;
    _started = true;
    _phaseSub = syncService.watchStatus().listen((SyncPhase phase) {
      final SyncPhase? previous = _lastPhase;
      _lastPhase = phase;
      if (phase is SyncPhaseSynced && previous is SyncPhaseSyncing) {
        unawaited(flush());
      }
    });
  }

  @override
  Future<void> dispose() async {
    await _phaseSub?.cancel();
    _phaseSub = null;
    _started = false;
  }

  // -----------------------------------------------------------------------
  // Recording
  // -----------------------------------------------------------------------

  @override
  Future<void> record(
    ProductEvent event, {
    TelemetryDimension? dimension,
  }) async {
    try {
      if (!await isEnabled()) return;
      await database.productEventDao.increment(
        eventKey: event.key,
        dimension: dimension?.value ?? '',
        day: _today(),
        now: _clock().toUtc(),
      );
    } on Object catch (_) {
      // Swallowed on purpose. This is called from UI callbacks — a scan, a
      // save — and an analytics failure must never surface to someone
      // photographing a receipt, let alone abort the flow. There is nothing
      // the user could do about it, and nothing worth losing their work over.
    }
  }

  // -----------------------------------------------------------------------
  // Upload
  // -----------------------------------------------------------------------

  @override
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      if (!await isEnabled()) return 0;

      final String? userId = remote.currentUserId;
      // No session means no row can satisfy RLS. Counters stay pending and go
      // out after sign-in rather than being logged as failures.
      if (userId == null) return 0;

      final List<ProductEventCounter> pending =
          await database.productEventDao.getPendingSync();
      if (pending.isEmpty) return 0;

      final List<ProductEventCounter> batch = pending.length > kMaxRowsPerFlush
          ? pending.sublist(0, kMaxRowsPerFlush)
          : pending;

      final String deviceId = await _deviceId();

      await remote.upsertCounters(<Map<String, dynamic>>[
        for (final ProductEventCounter c in batch)
          <String, dynamic>{
            'user_id': userId,
            // NULL for all of 1.3.0; the companies table lands in 1.4.0.
            'company_id': c.companyId,
            'device_id': deviceId,
            'event_key': c.eventKey,
            'dimension': c.dimension,
            'day': c.day,
            'count': c.count,
          },
      ]);

      int uploaded = 0;
      for (final ProductEventCounter c in batch) {
        // Compare-and-set: if the counter moved while the request was in
        // flight, it stays pending and goes out with the next flush.
        if (await database.productEventDao.markUploaded(
          id: c.id,
          uploadedCount: c.count,
        )) {
          uploaded++;
        }
      }

      await _pruneUploaded();
      return uploaded;
    } on Object catch (_) {
      // The batch stays pending. Because each row carries an absolute count,
      // a retry after a request that actually succeeded but whose response was
      // lost writes the same value again — a no-op, not a double count.
      return 0;
    } finally {
      _flushing = false;
    }
  }

  Future<void> _pruneUploaded() async {
    final DateTime cutoff = _clock().toUtc().subtract(kLocalRetention);
    await database.productEventDao.deleteUploadedBefore(_dayOf(cutoff));
  }

  // -----------------------------------------------------------------------
  // Consent + identity
  // -----------------------------------------------------------------------

  @override
  Future<bool> isEnabled() async {
    final String? raw =
        await database.userSettingsDao.getValue(kEnabledKey);
    // Absent means on: this is opt-out (D-15).
    return raw != 'false';
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {
    await database.userSettingsDao.setValue(kEnabledKey, '$enabled');
    if (!enabled) {
      // Opting out has to clear the backlog too. Leaving it would mean "off"
      // still sends everything collected up to that moment on the next flush,
      // which is not what anyone reading the switch would expect.
      await clearLocalData();
    }
  }

  @override
  Future<void> clearLocalData() async {
    await database.productEventDao.deleteAll();
  }

  /// Reads the per-install id, generating one on first use.
  ///
  /// 32 hex characters from [Random.secure], matching the server's
  /// `^[0-9a-f-]{16,64}$` shape check. Not a hardware identifier: reinstalling
  /// produces a new value, which costs a little cross-install continuity and
  /// buys a much smaller privacy surface. It exists only so two devices on one
  /// account can each own their counter row instead of overwriting each
  /// other's (D-14).
  Future<String> _deviceId() async {
    final String? existing =
        await database.userSettingsDao.getValue(kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 32; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    final String generated = buffer.toString();
    await database.userSettingsDao.setValue(kDeviceIdKey, generated);
    return generated;
  }

  // -----------------------------------------------------------------------
  // Day bucketing
  // -----------------------------------------------------------------------

  String _today() => _dayOf(_clock().toUtc());

  /// `YYYY-MM-DD` in UTC. A bucket label, not a timestamp — per-occurrence
  /// times would turn a counter into a timeline of what the user did and when.
  String _dayOf(DateTime utc) => utc.toIso8601String().split('T').first;
}
