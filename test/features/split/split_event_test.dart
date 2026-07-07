import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';

/// Equality contracts for [SplitEvent] subtypes.
void main() {
  group('SplitEvent equality', () {
    test('should compare SplitStarted by receipt id', () {
      expect(
        const SplitStarted(receiptId: 3),
        const SplitStarted(receiptId: 3),
      );
      expect(
        const SplitStarted(receiptId: 3),
        isNot(const SplitStarted(receiptId: 4)),
      );
    });

    test('should compare participant events by identity fields', () {
      expect(
        const SplitParticipantAdded(name: 'Ayşe'),
        const SplitParticipantAdded(name: 'Ayşe'),
      );
      expect(
        const SplitParticipantAdded(name: 'Ayşe'),
        isNot(const SplitParticipantAdded(name: 'Ali')),
      );
      expect(
        const SplitParticipantRemoved(participantId: 'p1'),
        const SplitParticipantRemoved(participantId: 'p1'),
      );
    });

    test('should compare SplitItemAssigned by item and participant set', () {
      expect(
        const SplitItemAssigned(
          itemId: 1,
          participantIds: <String>['p1', 'p2'],
        ),
        const SplitItemAssigned(
          itemId: 1,
          participantIds: <String>['p1', 'p2'],
        ),
      );
      expect(
        const SplitItemAssigned(itemId: 1, participantIds: <String>['p1']),
        isNot(
          const SplitItemAssigned(itemId: 1, participantIds: <String>[]),
        ),
      );
    });

    test('should compare SplitTypeChanged by type', () {
      expect(
        const SplitTypeChanged(type: SplitType.equal),
        const SplitTypeChanged(type: SplitType.equal),
      );
      expect(
        const SplitTypeChanged(type: SplitType.equal),
        isNot(const SplitTypeChanged(type: SplitType.custom)),
      );
    });

    test('should compare SplitShareRequested by payload', () {
      expect(
        const SplitShareRequested(payload: 'BİM — 40,00 TL'),
        const SplitShareRequested(payload: 'BİM — 40,00 TL'),
      );
    });
  });
}
