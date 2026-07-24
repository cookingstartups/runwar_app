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

/// Slices from [startMarker] up to (not including) the next occurrence of
/// [endMarker] after it - the real boundary of the member being inspected,
/// not a guessed character count. Fails loudly, with the missing landmark
/// named, instead of silently reading whatever text happens to sit at a
/// fixed offset. [endMarker] is normally the next sibling member's own
/// signature, so the slice tracks the real method body regardless of how
/// much the method itself grows or shrinks.
String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$startMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason: 'Landmark not found after "$startMarker": "$endMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  return src.substring(start, end);
}

void main() {
  group('R4-AC1: zonesProvider(city) fallback fetch before E&U animation', () {
    test('_onAutoClaimOutcome is async (Future<void>), not fire-and-forget void', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('Future<void> _onAutoClaimOutcome('),
          reason: '_onAutoClaimOutcome must become async so it can await the fallback fetch (design.md R4-AC1)');
    });

    test('the outcome handler falls back to zonesRepositoryProvider.fetchByCity when the stream has not emitted', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, '_onAutoClaimOutcome(', 'Future<void> _completeMission1(');
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
      final body = _sliceToNextMember(src, '_showResultSnack(', 'Future<void> _onAutoClaimOutcome(');
      expect(body, contains('TerritoryResult.disputed'),
          reason: '_showResultSnack must switch on TerritoryResult.disputed with its own message');
    });
  });

  group('R4-AC4: failed outcome shows a distinct message and logs the reason', () {
    test('the failed branch of _onAutoClaimOutcome logs the reason via ErrorLogService', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final fnBody = _sliceToNextMember(src, '_onAutoClaimOutcome(', 'Future<void> _completeMission1(');
      final failedIdx = fnBody.indexOf('TerritoryResult.failed');
      expect(failedIdx, greaterThanOrEqualTo(0),
          reason: '_onAutoClaimOutcome must have a TerritoryResult.failed branch');
      // The failed branch is the first if-block in the function and ends at
      // the next top-level `if (outcome.result ==` check (the claimed/
      // conquered branch) - both exact strings within the already-anchored
      // function body, not a guessed length.
      final nextBranchIdx = fnBody.indexOf('if (outcome.result ==', failedIdx + 1);
      expect(nextBranchIdx, greaterThan(failedIdx),
          reason: 'Landmark not found: the claimed/conquered branch after the failed branch. _onAutoClaimOutcome\'s structure moved - update this anchor.');
      final failedBranch = fnBody.substring(failedIdx, nextBranchIdx);
      expect(failedBranch, contains('logClientError'),
          reason: 'The failed branch must log the underlying failure reason via ErrorLogService.logClientError');
      expect(failedBranch, contains('reason'),
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
      // The ownPos declaration is one statement; its own terminating ";" is
      // the real boundary, not a guessed character count.
      final declEnd = src.indexOf(';', idx);
      expect(declEnd, greaterThan(idx),
          reason: 'Landmark not found: the ownPos declaration never terminates with a ";" - source structure moved, update this anchor.');
      final window = src.substring(idx, declEnd);
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
      final body = _sliceToNextMember(src, 'Widget _buildFab(', 'Future<void> _onFabTap(');
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
      final body = _sliceToNextMember(src, '_onSimTrackTick(', 'void _handleMapEvent(MapEvent event) {');
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

  // ===========================================================================
  // P0 review finding: _onSimTrackTick's camera-flag reset is keyed on a
  // boolean isSimulationActive-vs-_wasSimulationActive edge, which only
  // fires when a trackVersion tick lands on the exact call that crosses the
  // edge. stopRun() ends a simulation without bumping trackVersion (pinned
  // in run_replay_simulation_test.dart), so a stop-then-restart cycle inside
  // the same mounted MapScreen can miss the reset entirely and leave
  // _simSnapDone/_simAutoFollowSuspended stuck true for the next simulation.
  // The reset must instead key off an identity/generation signal that
  // changes on every beginSimulation call, not a missable boolean edge.
  // ===========================================================================

  group('P0: the camera-flag reset does not rely solely on a missable boolean simulation edge', () {
    test('_onSimTrackTick reads a generation signal, not only isSimulationActive != _wasSimulationActive', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, '_onSimTrackTick(', 'void _handleMapEvent(MapEvent event) {');

      expect(body, contains('simulationGeneration'),
          reason: '_onSimTrackTick must read RunRecorderService.instance.simulationGeneration to '
              'detect a fresh simulation, because a boolean isSimulationActive edge can be missed '
              'when the ending call (stopRun) does not bump trackVersion');
      expect(body, isNot(contains('simActive != _wasSimulationActive')),
          reason: 'the reset must no longer be gated solely on a boolean active-state transition - '
              'that comparison silently no-ops whenever the falling edge is missed, which is exactly '
              'the stopRun-then-restart bug this test locks against');
    });

    test('a cached last-seen generation field exists alongside _wasSimulationActive', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(src, contains('_lastSimulationGeneration'),
          reason: 'the widget must cache the last generation it saw so it can diff against the '
              'current RunRecorderService.instance.simulationGeneration on every tick, independent '
              'of whether a trackVersion tick happened to land on the exact stop/start boundary');
    });
  });

  // ===========================================================================
  // SPEC-0145: the fog-of-war live-GPS reveal hole must follow the shared
  // own-position derivation (_simOrRealOwnPosition), not raw real-device GPS,
  // so it tracks a simulated/replayed position instead of the operator's
  // actual physical location. Source-inspection per flutter-test-patterns.md.
  // ===========================================================================

  group('SPEC-0145 item 1: the _FogLayer call site passes the shared derivation, not the raw field', () {
    test('the fog-overlay call site passes currentPosition: _simOrRealOwnPosition(), not _currentPosition', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final callIdx = src.indexOf('_FogLayer(');
      expect(callIdx, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: "_FogLayer(". map_screen.dart\'s structure moved - update this anchor.');
      final closeIdx = src.indexOf(');', callIdx);
      expect(closeIdx, greaterThan(callIdx),
          reason: 'Landmark not found: the closing ");" of the _FogLayer(...) call.');
      final call = src.substring(callIdx, closeIdx);
      expect(call, contains('currentPosition: _simOrRealOwnPosition()'),
          reason: 'this is the one _FogLayer call site in the file; it must pass the shared '
              'simulation-aware own-position derivation so the live-GPS reveal hole tracks a '
              'simulated/replayed position rather than the real-GPS-only _currentPosition field '
              '(this is also the regression lock: reintroducing raw _currentPosition here must fail)');
      expect(call, isNot(contains('currentPosition: _currentPosition')),
          reason: 'the raw real-GPS field must no longer be passed directly to _FogLayer');
    });
  });

  group('SPEC-0145 item 2: _FogLayer.currentPosition is typed LatLng?, not Position?', () {
    test('the _FogLayer field declaration reads final LatLng? currentPosition;', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final classIdx = src.indexOf('class _FogLayer extends ConsumerWidget');
      expect(classIdx, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: "class _FogLayer extends ConsumerWidget". Source structure moved.');
      final ctorIdx = src.indexOf('const _FogLayer({', classIdx);
      expect(ctorIdx, greaterThan(classIdx),
          reason: 'Landmark not found: the _FogLayer constructor after the class declaration.');
      final fieldsBlock = src.substring(classIdx, ctorIdx);
      expect(fieldsBlock, contains('final LatLng? currentPosition;'),
          reason: 'the field must be retyped from Geolocator\'s Position? to flutter_map\'s LatLng?, '
              'since the call site now supplies an already-resolved LatLng from _simOrRealOwnPosition()');
      expect(fieldsBlock, isNot(contains('final Position? currentPosition;')),
          reason: 'the old Position?-typed field declaration must be gone');
    });
  });

  group('SPEC-0145 item 3/4: the live-GPS reveal branch consumes the resolved LatLng directly (no re-derivation)', () {
    test('_FogLayer.build() uses currentPosition! directly instead of constructing LatLng(.latitude, .longitude)', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'Widget build(BuildContext context, WidgetRef ref) {', 'class _FogPainter');
      expect(body, contains('if (currentPosition != null)'),
          reason: 'the null-check guard for the live-GPS hole must be unchanged in shape (non-regression: '
              'a null own-position must still skip the hole with no exception, in both sim and real-GPS modes)');
      expect(body, contains('point: currentPosition!,'),
          reason: 'the live-GPS branch must consume the already-resolved LatLng directly, since the caller '
              'now supplies one via _simOrRealOwnPosition() - it must no longer re-derive a LatLng from '
              '.latitude/.longitude off a raw Position');
      expect(body, isNot(contains('LatLng(currentPosition!.latitude, currentPosition!.longitude)')),
          reason: 'the old Position-to-LatLng construction must be removed now that currentPosition is '
              'already a LatLng?');
    });
  });

  group('SPEC-0145 item 6: the 5 km historical-run reveal is unaffected by this change (non-regression)', () {
    test('the runPoints loop still adds a 5000 m hole per point, unchanged', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'Widget build(BuildContext context, WidgetRef ref) {', 'class _FogPainter');
      expect(body, contains('for (final pt in runPoints)'),
          reason: 'the historical-run reveal loop must remain fed by runPoints, untouched by this spec');
      expect(body, contains('centers.add((point: pt, radiusM: 5000));'),
          reason: 'each historical run point must still produce an unchanged 5000 m reveal hole, proving '
              'this spec\'s change is isolated to the live-GPS branch only');
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
