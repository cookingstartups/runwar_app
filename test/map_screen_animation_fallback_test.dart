// test/map_screen_animation_fallback_test.dart
//
// RED phase - R4-AC1 (zonesProvider fallback fetch), R4-AC3 (disputed
// distinct message, regression-lock), R4-AC4 (failed message + reason log).
// Uses static source inspection (flutter-test-patterns.md) since
// _onAutoClaimOutcome lives inside MapScreen (FlutterMap-bearing) and the
// behaviour under test ("does the handler await a fallback fetch / log a
// reason") maps directly to source structure rather than runtime widget
// state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R4-AC1: zonesProvider(city) fallback fetch before E&U animation', () {
    test('_onAutoClaimOutcome is async (Future<void>), not fire-and-forget void', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('Future<void> _onAutoClaimOutcome('),
          reason: '_onAutoClaimOutcome must become async so it can await the fallback fetch (design.md R4-AC1)');
    });

    test('the outcome handler falls back to zonesRepositoryProvider.fetchByCity when the stream has not emitted', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onAutoClaimOutcome(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 2500).clamp(0, src.length));
      expect(body, contains('hasValue'),
          reason: 'The handler must check whether zonesProvider(city) has already emitted a snapshot');
      expect(body, contains('zonesRepositoryProvider'),
          reason: 'On no prior snapshot, the handler must fetch via zonesRepositoryProvider (not substitute an empty list)');
      expect(body, contains('fetchByCity'),
          reason: 'The fallback fetch must call fetchByCity(city)');
    });
  });

  group('R4-AC3: disputed outcome gets a distinct, non-silent message (regression-lock)', () {
    test('_showResultSnack has a disputed branch distinct from claimed/conquered/failed', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_showResultSnack(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 600).clamp(0, src.length));
      expect(body, contains('TerritoryResult.disputed'),
          reason: '_showResultSnack must switch on TerritoryResult.disputed with its own message');
    });
  });

  group('R4-AC4: failed outcome shows a distinct message and logs the reason', () {
    test('the failed branch of _onAutoClaimOutcome logs the reason via ErrorLogService', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onAutoClaimOutcome(');
      expect(idx, greaterThanOrEqualTo(0));
      final failedIdx = src.indexOf('TerritoryResult.failed', idx);
      expect(failedIdx, greaterThanOrEqualTo(0));
      final body = src.substring(failedIdx, (failedIdx + 700).clamp(0, src.length));
      expect(body, contains('logClientError'),
          reason: 'The failed branch must log the underlying failure reason via ErrorLogService.logClientError');
      expect(body, contains('reason'),
          reason: 'The logged error must reference the reason string returned by the server/local evaluator');
    });
  });

  // ===========================================================================
  // SPEC-0144 Part A: camera and own-player markers follow the simulated
  // position, not real GPS, while a simulation is active. Source-inspection
  // per flutter-test-patterns.md (MapScreen carries a FlutterMap).
  // ===========================================================================

  group('SPEC-0144 AC-1: simulation-aware own-position derivation exists', () {
    test('an ownPos derivation reads isSimulationActive before choosing a position source', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('ownPos');
      expect(idx, greaterThanOrEqualTo(0),
          reason: 'a simulation-aware own-position value (design.md names it ownPos) must exist '
              'alongside the existing _currentPosition-only real-GPS logic');
      final window = src.substring(idx, (idx + 400).clamp(0, src.length));
      expect(window, contains('isSimulationActive'),
          reason: 'the ownPos derivation must branch on RunRecorderService.instance.isSimulationActive');
    });
  });

  group('SPEC-0144 AC-2: simulated position comes from trackSnapshot, not _currentPosition', () {
    test('the simulation-active branch of the ownPos derivation reads trackSnapshot and never _currentPosition', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('ownPos');
      expect(idx, greaterThanOrEqualTo(0));
      final qIdx = src.indexOf('?', idx);
      expect(qIdx, greaterThanOrEqualTo(0));
      final openIdx = src.indexOf('(', qIdx);
      expect(openIdx, greaterThanOrEqualTo(0));
      final branch = _extractBalanced(src, openIdx);
      expect(branch, anyOf(contains('trackSnapshot'), contains('simSnap')),
          reason: 'the true branch (simulation active) must derive from RunRecorderService.trackSnapshot');
      expect(branch, isNot(contains('_currentPosition')),
          reason: 'the simulation-active branch must never read the real-GPS _currentPosition field');
    });
  });

  group('SPEC-0144 AC-3: the Locate button is simulation-aware', () {
    test('_buildFab branches the Locate onPressed handler on isSimulationActive', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('Widget _buildFab(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = src.substring(idx, (idx + 1400).clamp(0, src.length));
      expect(body, contains('isSimulationActive'),
          reason: '_buildFab must locally branch on RunRecorderService.instance.isSimulationActive '
              'to pick the simulated vs. real-GPS position for the Locate button');
      expect(body, contains('ownPos'),
          reason: '_buildFab must derive and use the shared ownPos value, not read _currentPosition directly '
              'for the disabled/onPressed condition');
    });
  });

  group('SPEC-0144 AC-4: manual-pan-suspend flag exists and gates continuous follow', () {
    test('_simAutoFollowSuspended is set on a non-mapController map event and checked before a follow move', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('_simAutoFollowSuspended'),
          reason: 'a local manual-pan-suspend flag must exist (design.md names it _simAutoFollowSuspended)');
      expect(src, contains('MapEventSource.mapController'),
          reason: 'the pan-detection handler must filter out our own programmatic move() calls, which the '
              'flutter_map package always tags with MapEventSource.mapController - this is the primary '
              'false-positive failure mode the design explicitly guards against');
      final handlerIdx = src.indexOf('MapEventSource.mapController');
      final followIdx = src.indexOf('_simAutoFollowSuspended', handlerIdx);
      expect(followIdx, greaterThanOrEqualTo(0),
          reason: '_simAutoFollowSuspended must be referenced after the mapController-source guard, not before it');
    });
  });

  group('SPEC-0144 AC-5: real-run camera/marker behavior is unchanged, and the new listener wiring is correctly ordered', () {
    test('the real-GPS _initLocation block stays intact and ref.listen on trackVersion is the first statement of build()', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('Geolocator.getPositionStream('),
          reason: 'the real-GPS stream subscription must remain untouched (requirements.md Part B non-goal)');
      expect(src, contains('_centeredOnGps = true;'),
          reason: 'the real-GPS one-shot auto-center gate must remain untouched');
      final listenIdx = src.indexOf('ref.listen<int>(runRecorderTrackVersionProvider');
      expect(listenIdx, greaterThanOrEqualTo(0),
          reason: 'build() must register a ref.listen on runRecorderTrackVersionProvider to drive camera-follow ticks');
      final buildIdx = src.indexOf('Widget build(BuildContext context) {');
      final loadingIdx = src.indexOf('slugsAsync.isLoading', buildIdx);
      expect(listenIdx, greaterThan(buildIdx));
      expect(listenIdx, lessThan(loadingIdx),
          reason: 'ref.listen must be the first statement in build(), before the loading early return, so it '
              'fires on every build call (design.md section 3.1 risk register entry 1)');
    });
  });

  group('SPEC-0144 AC-6: simulation end triggers no direct camera-move call site', () {
    test('_onSimTrackTick exists and makes no _mapController.move call directly gated on the active-to-inactive transition', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final idx = src.indexOf('_onSimTrackTick(');
      expect(idx, greaterThanOrEqualTo(0),
          reason: 'the tick handler driving camera-follow (design.md section 3.2) must exist');
      final body = src.substring(idx, (idx + 900).clamp(0, src.length));
      final falseGuardIdx = body.indexOf('!simActive');
      expect(falseGuardIdx, greaterThanOrEqualTo(0),
          reason: '_onSimTrackTick must guard on the inactive case before doing anything else');
      final nextMoveIdx = body.indexOf('_mapController.move(', falseGuardIdx);
      final nextReturnIdx = body.indexOf('return', falseGuardIdx);
      expect(nextReturnIdx, greaterThanOrEqualTo(0));
      expect(nextMoveIdx == -1 || nextMoveIdx > nextReturnIdx + 40, isTrue,
          reason: 'ending a simulation must not itself trigger a camera move - hand-back is implicit '
              'via the untouched real-GPS listener (design.md section 3.6)');
    });
  });
}

/// Extracts the balanced-parenthesis substring starting at [openIdx], which
/// must index a '(' character. Used to isolate one ternary branch of the
/// ownPos ?: expression without over-fitting to exact formatting.
String _extractBalanced(String src, int openIdx) {
  var depth = 0;
  for (var i = openIdx; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') {
      depth--;
      if (depth == 0) return src.substring(openIdx, i + 1);
    }
  }
  throw StateError('unbalanced parens starting at $openIdx');
}
