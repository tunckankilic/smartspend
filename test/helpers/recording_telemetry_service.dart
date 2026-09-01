import 'package:smartspend/core/services/telemetry_service.dart';

/// In-memory [TelemetryService] double.
///
/// Records what was asked of it instead of touching Drift or the network, so
/// bloc tests can assert on the event stream without standing up a database.
/// Deliberately a hand-written fake rather than a mocktail mock: the
/// assertions these tests want are "which events, in what order", and a plain
/// list reads better than a sequence of `verify` calls.
class RecordingTelemetryService implements TelemetryService {
  final List<({ProductEvent event, TelemetryDimension? dimension})> recorded =
      <({ProductEvent event, TelemetryDimension? dimension})>[];

  int flushCount = 0;
  bool enabled = true;
  bool cleared = false;
  bool started = false;

  /// Just the event keys, in order — the usual assertion target.
  List<String> get keys => recorded
      .map((({ProductEvent event, TelemetryDimension? dimension}) e) =>
          e.event.key)
      .toList(growable: false);

  @override
  Future<void> record(
    ProductEvent event, {
    TelemetryDimension? dimension,
  }) async {
    if (!enabled) return;
    recorded.add((event: event, dimension: dimension));
  }

  @override
  Future<int> flush() async {
    flushCount++;
    return 0;
  }

  @override
  bool get defaultEnabled => true;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled({required bool enabled}) async {
    this.enabled = enabled;
    if (!enabled) await clearLocalData();
  }

  @override
  Future<void> clearLocalData() async {
    cleared = true;
    recorded.clear();
  }

  @override
  void start() => started = true;

  @override
  Future<void> dispose() async {}
}
