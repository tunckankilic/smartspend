import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/services/sync_service.dart';

/// Equality + arithmetic contracts for the sync engine's value objects.
/// The sync indicator rebuilds on [SyncPhase] changes, so props must
/// cover every field; [SyncReport.+] merges the push and pull legs.
void main() {
  group('SyncReport', () {
    test('should sum both legs field by field', () {
      const SyncReport push = SyncReport(
        pushed: 2,
        pulled: 0,
        conflicts: 1,
        failed: 1,
      );
      const SyncReport pull = SyncReport(
        pushed: 0,
        pulled: 5,
        conflicts: 0,
        failed: 2,
      );
      expect(
        push + pull,
        const SyncReport(pushed: 2, pulled: 5, conflicts: 1, failed: 3),
      );
    });
  });

  group('SyncPhase equality', () {
    test('should compare SyncPhaseSynced by last sync time', () {
      final DateTime at = DateTime.utc(2026, 7, 7, 12);
      expect(SyncPhaseSynced(lastSyncAt: at), SyncPhaseSynced(lastSyncAt: at));
      expect(
        SyncPhaseSynced(lastSyncAt: at),
        isNot(const SyncPhaseSynced()),
      );
    });

    test('should treat field-less phases as equal', () {
      expect(const SyncPhaseSyncing(), const SyncPhaseSyncing());
    });

    test('should compare SyncPhasePending by queued row count', () {
      expect(
        const SyncPhasePending(count: 3),
        const SyncPhasePending(count: 3),
      );
      expect(
        const SyncPhasePending(count: 3),
        isNot(const SyncPhasePending(count: 4)),
      );
    });
  });
}
