// test/services/territory_service_decay_test.dart
//
// Covers TerritoryService.computeDecayStep - the pure decay-tick arithmetic
// that now also derives influence_level (previously untouched by decay,
// only the continuous `influence` value moved). `levelCrossed` is the
// signal callers use to gate the retroactive fuse-on-parity check, so it
// must fire only on a tick that actually steps the integer level down, not
// on every tick.

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/territory_service.dart';

void main() {
  group('TerritoryService.computeDecayStep', () {
    test('a tick that does not cross an integer boundary does not flag levelCrossed', () {
      // 3.5 -> 3.5 - (1/26) ~= 3.461, floor stays 3, oldLevel already 3.
      final result = TerritoryService.computeDecayStep(
        currentInfluence: 3.5,
        oldLevel: 3,
        decayPerDay: 1.0 / 26.0,
      );

      expect(result.newLevel, 3);
      expect(result.levelCrossed, isFalse);
      expect(result.newInfluence, closeTo(3.4615, 0.001));
    });

    test('a tick that crosses an integer boundary flags levelCrossed', () {
      // 3.02 decayed by ~0.0385 crosses below 3.0, so floor drops to 2.
      final result = TerritoryService.computeDecayStep(
        currentInfluence: 3.02,
        oldLevel: 3,
        decayPerDay: 1.0 / 26.0,
      );

      expect(result.newLevel, 2);
      expect(result.levelCrossed, isTrue);
    });

    test('the level floor never decays below 1', () {
      final result = TerritoryService.computeDecayStep(
        currentInfluence: 1.02,
        oldLevel: 1,
        decayPerDay: 1.0 / 26.0,
      );

      expect(result.newInfluence, 1.0);
      expect(result.newLevel, 1);
      expect(result.levelCrossed, isFalse);
    });

    test('a large per-tick decay never drops the level by more than the floor allows', () {
      final result = TerritoryService.computeDecayStep(
        currentInfluence: 2.0,
        oldLevel: 2,
        decayPerDay: 50.0,
      );

      expect(result.newInfluence, 1.0);
      expect(result.newLevel, 1);
      expect(result.levelCrossed, isTrue);
    });

    test('oldLevel already ahead of floor(currentInfluence) still only reports a crossing on an actual decrease', () {
      // A zone whose stored influence_level (e.g. from a claim/merge bonus)
      // sits above floor(influence) - decaying influence a little further
      // still only reports a crossing once newLevel actually drops below
      // the stored oldLevel, not merely below floor(currentInfluence).
      final result = TerritoryService.computeDecayStep(
        currentInfluence: 5.02,
        oldLevel: 8,
        decayPerDay: 1.0 / 26.0,
      );

      expect(result.newLevel, 4);
      expect(result.levelCrossed, isTrue);
    });
  });
}
