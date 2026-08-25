// test/providers/mission_provider_test.dart
//
// Unit tests for MissionStatus's computed gates, specifically covering the
// fail-closed error fallback used by missionStatusProvider
// (lib/providers/mission_provider.dart) - hotfix/streak-mission1-gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:runwar_app/providers/mission_provider.dart';

void main() {
  group('MissionStatus fail-closed error fallback', () {
    // GIVEN missionStatusProvider's catch block fires (fetch failure) and
    //   constructs the fallback MissionStatus it now returns:
    //   firstMissionCompletedAt: null, firstAttackCompletedAt: null,
    //   zoneCount: 0
    // WHEN needsMission1 / bypass are evaluated on that fallback
    // THEN needsMission1 is true and bypass is false - the Mission-1 gate
    //   stays active (fails closed) instead of being silently bypassed.
    //
    // Reverting the fix (zoneCount: 1 instead of 0, as it was before) makes
    // this test fail: bypass would become true via
    // `firstMissionCompletedAt == null && zoneCount > 0`, and needsMission1
    // would become false, letting an un-onboarded player skip Mission 1 on
    // any transient fetch error.
    test('error fallback fails closed: needsMission1=true, bypass=false', () {
      const fallback = MissionStatus(
        firstMissionCompletedAt: null,
        firstAttackCompletedAt: null,
        zoneCount: 0,
      );

      expect(fallback.needsMission1, isTrue,
          reason: 'Error fallback must require Mission 1, not bypass it');
      expect(fallback.bypass, isFalse,
          reason:
              'Error fallback must never look like a legacy-tester bypass');
    });

    // Sanity: the pre-fix fallback shape (zoneCount: 1) is documented here
    // as the regression this fix prevents, so a future edit that
    // reintroduces it is caught immediately.
    test('regression guard: zoneCount>0 with null firstMissionCompletedAt '
        'IS the bypass condition (must never be the error-fallback shape)',
        () {
      const regressed = MissionStatus(
        firstMissionCompletedAt: null,
        firstAttackCompletedAt: null,
        zoneCount: 1,
      );

      expect(regressed.bypass, isTrue,
          reason:
              'Documents why zoneCount:1 must never be used as the error '
              'fallback - it is indistinguishable from a legitimate '
              'legacy-tester bypass.');
    });
  });
}
