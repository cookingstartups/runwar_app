// test/services/territory_service_dispute_reconciliation_test.dart
//
// Covers TerritoryService.computeDisputeReconciliationTargets - the pure
// comparison that decides which of the player's zones need a merge-fold
// retry (_resolveDecayMerge) because their dispute state changed server-side
// since the last sync. Mirrors the existing computeDecayStep precedent:
// _applyDecay only fires _resolveDecayMerge on a levelCrossed tick; the
// dispute-reconciliation tick fires it only on zones whose dispute just
// resolved (status flipped disputed -> owned, or ownership transferred to
// the current player).
//
// This targets a not-yet-existing static method, so it fails today with a
// missing-member compile error - the right RED reason.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/territory_service.dart';

void main() {
  group('TerritoryService.computeDisputeReconciliationTargets', () {
    test('a zone whose dispute resolved to owned since last sync is a reconciliation target', () {
      final targets = TerritoryService.computeDisputeReconciliationTargets(
        currentPlayerId: 'player-1',
        priorZones: [
          {'id': 'zone-a', 'status': 'disputed', 'owner_id': 'player-1', 'influence_level': 5},
        ],
        currentZones: [
          {'id': 'zone-a', 'status': 'owned', 'owner_id': 'player-1', 'influence_level': 4},
        ],
      );

      expect(targets, contains('zone-a'));
    });

    test('a zone freshly transferred to the current player via an attacker win is a reconciliation target', () {
      final targets = TerritoryService.computeDisputeReconciliationTargets(
        currentPlayerId: 'player-1',
        priorZones: [
          {'id': 'zone-b', 'status': 'disputed', 'owner_id': 'defender-x', 'influence_level': 3},
        ],
        currentZones: [
          {'id': 'zone-b', 'status': 'owned', 'owner_id': 'player-1', 'influence_level': 1},
        ],
      );

      expect(targets, contains('zone-b'));
    });

    test('a zone that was never disputed is not a reconciliation target', () {
      final targets = TerritoryService.computeDisputeReconciliationTargets(
        currentPlayerId: 'player-1',
        priorZones: [
          {'id': 'zone-c', 'status': 'owned', 'owner_id': 'player-1', 'influence_level': 5},
        ],
        currentZones: [
          {'id': 'zone-c', 'status': 'owned', 'owner_id': 'player-1', 'influence_level': 5},
        ],
      );

      expect(targets, isEmpty);
    });

    test('a zone still disputed (not yet resolved) is not a reconciliation target', () {
      final targets = TerritoryService.computeDisputeReconciliationTargets(
        currentPlayerId: 'player-1',
        priorZones: [
          {'id': 'zone-d', 'status': 'disputed', 'owner_id': 'player-1', 'influence_level': 2},
        ],
        currentZones: [
          {'id': 'zone-d', 'status': 'disputed', 'owner_id': 'player-1', 'influence_level': 2},
        ],
      );

      expect(targets, isEmpty);
    });

    test('a resolved dispute belonging to neither side of the current player is not a target', () {
      final targets = TerritoryService.computeDisputeReconciliationTargets(
        currentPlayerId: 'player-1',
        priorZones: [
          {'id': 'zone-e', 'status': 'disputed', 'owner_id': 'other-owner', 'influence_level': 2},
        ],
        currentZones: [
          {'id': 'zone-e', 'status': 'owned', 'owner_id': 'attacker-other', 'influence_level': 1},
        ],
      );

      expect(targets, isEmpty);
    });
  });
}
