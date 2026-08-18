// test/map_screen_run_autocenter_test.dart
//
// Source-inspection tests for run-session camera auto-follow with
// intentional-pan override. Camera/routing logic in map_screen.dart is
// proven by static source inspection, never by pumping a FlutterMap widget
// (flutter-test-patterns.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slices from [startMarker] up to (not including) the next occurrence of
/// [endMarker] after it - the real boundary of the member being inspected,
/// not a guessed character count. Anchored on the enclosing method/symbol,
/// never on first-occurrence-of-a-token, per flutter-test-patterns.md.
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
  group('follow is gated on the recorder recording state, not on simulation being active', () {
    test('_handleMapEvent gates on RecorderState.recording rather than isSimulationActive', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'void _handleMapEvent(MapEvent event) {', '\n  }');
      expect(body, contains('RecorderState.recording'),
          reason: 'follow suspend must be gated on the recorder reporting RecorderState.recording, '
              'covering both real-GPS and simulation sessions identically');
      expect(body, isNot(contains('isSimulationActive')),
          reason: 'the session gate must no longer be simulation-only - real sessions must suspend follow too');
    });

    test('_handleMapEvent still filters out our own programmatic moves via the mapController source', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'void _handleMapEvent(MapEvent event) {', '\n  }');
      expect(body, contains('MapEventSource.mapController'),
          reason: 'the mapController-source filter must remain the sole distinguisher between our own '
              'follow-driven moves and a real user gesture');
      final recordingIdx = body.indexOf('RecorderState.recording');
      final mapControllerIdx = body.indexOf('MapEventSource.mapController');
      expect(recordingIdx, greaterThanOrEqualTo(0));
      expect(mapControllerIdx, greaterThan(recordingIdx),
          reason: 'the recording-state gate must be checked before the mapController-source filter');
    });
  });

  group('gesture suspend captures a reference time and position for later re-engage evaluation', () {
    test('_handleMapEvent stores the wall-clock suspend time and the position at suspend', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'void _handleMapEvent(MapEvent event) {', '\n  }');
      expect(body, contains('_followSuspended'),
          reason: 'a session-wide suspend flag must be set when a real gesture is detected');
      expect(body, contains('_followSuspendedAt'),
          reason: 'the wall-clock time of the suspending gesture must be captured');
      expect(body, contains('_followSuspendedFromPosition'),
          reason: 'the player position at the moment of the suspending gesture must be captured as the '
              're-engage reference point');
    });
  });

  group('a shared follow driver is invoked from both the simulation tick path and the real position listener', () {
    test('_onSimTrackTick invokes the shared follow driver instead of its own inline continuous-follow move', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'void _onSimTrackTick() {', '\n  }');
      expect(body, contains('_driveFollow('),
          reason: 'the simulation tick path must delegate continuous follow to the shared _driveFollow method '
              'instead of the old inline "!_simAutoFollowSuspended" branch');
    });

    test('the real-GPS position listener also invokes the shared follow driver', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final listenerStart = src.indexOf('_posSub = Geolocator.getPositionStream(');
      expect(listenerStart, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: the real-GPS position stream subscription. map_screen.dart\'s structure moved.');
      final listenerEnd = src.indexOf('void _onSimTrackTick(', listenerStart);
      expect(listenerEnd, greaterThan(listenerStart),
          reason: 'Landmark not found: _onSimTrackTick after the real-GPS listener block.');
      final listenerBody = src.substring(listenerStart, listenerEnd);
      expect(listenerBody, contains('_driveFollow('),
          reason: 'real GPS position updates must drive the same shared follow method as the simulation tick path, '
              'not a second independent follow mechanism');
    });

    test('the shared follow driver evaluates the re-engage predicate and preserves current zoom on move', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final driverStart = src.indexOf('void _driveFollow(');
      expect(driverStart, greaterThanOrEqualTo(0),
          reason: 'a shared _driveFollow(LatLng position) method must exist');
      final driverEnd = src.indexOf('\n  }', driverStart);
      expect(driverEnd, greaterThan(driverStart));
      final driverBody = src.substring(driverStart, driverEnd);
      expect(driverBody, contains('shouldReengageFollow('),
          reason: 'the shared follow driver must evaluate the pure re-engage predicate while suspended, '
              'lazily on the position tick, rather than a periodic timer');
      expect(driverBody, contains('elapsed:'),
          reason: 'shouldReengageFollow must be called with the elapsed named argument');
      expect(driverBody, contains('distanceMeters:'),
          reason: 'shouldReengageFollow must be called with the distanceMeters named argument');
      expect(driverBody, contains('_mapController.move(position, _mapController.camera.zoom)'),
          reason: 'the follow move must preserve the current zoom level, not reset to the initial zoom');
    });
  });

  group('the map event handler suspends follow only for non-programmatic sources', () {
    test('an event sourced from mapController must not reach the follow-suspend statements', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final body = _sliceToNextMember(src, 'void _handleMapEvent(MapEvent event) {', '\n  }');
      final mapControllerIdx = body.indexOf('MapEventSource.mapController');
      final returnIdx = body.indexOf('return', mapControllerIdx);
      final suspendIdx = body.indexOf('_followSuspended = true', mapControllerIdx);
      expect(mapControllerIdx, greaterThanOrEqualTo(0));
      expect(returnIdx, greaterThan(mapControllerIdx),
          reason: 'the mapController-sourced check must be followed by an early return');
      expect(suspendIdx, greaterThan(returnIdx),
          reason: 'the suspend assignment must occur strictly after the mapController early return, so a '
              'programmatic move can never suspend follow');
    });
  });

  group('the Locate control re-arms follow unconditionally for both session kinds', () {
    test('the Locate FAB onPressed handler resets suspend state without an isSimulationActive condition', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final locateIdx = src.indexOf("heroTag: 'locate'");
      expect(locateIdx, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: the Locate FAB\'s heroTag. map_screen.dart\'s structure moved.');
      final onPressedIdx = src.indexOf('onPressed:', locateIdx);
      final childIdx = src.indexOf('child:', onPressedIdx);
      expect(onPressedIdx, greaterThan(locateIdx));
      expect(childIdx, greaterThan(onPressedIdx));
      final onPressedBody = src.substring(onPressedIdx, childIdx);
      expect(onPressedBody, contains('_followSuspended = false'),
          reason: 'the Locate FAB must unconditionally clear the session-wide suspend flag');
      expect(onPressedBody, isNot(contains('if (isSimulationActive)')),
          reason: 'the re-arm must no longer be gated behind an isSimulationActive check - it applies to real '
              'sessions identically');
      expect(onPressedBody, contains('_mapController.move('),
          reason: 'the Locate FAB must always perform the immediate re-center move regardless of prior suspend state');
    });

    test('the Locate FAB carries a follow-state visual', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final buildFabStart = src.indexOf('Widget _buildFab(');
      expect(buildFabStart, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: _buildFab. map_screen.dart\'s structure moved.');
      final buildFabEnd = src.indexOf('Future<void> _onFabTap(', buildFabStart);
      expect(buildFabEnd, greaterThan(buildFabStart));
      final buildFabBody = src.substring(buildFabStart, buildFabEnd);
      expect(buildFabBody, contains('_followSuspended'),
          reason: '_buildFab must read the follow-suspend state to drive the Locate FAB\'s visual');
    });
  });

  group('tile layer buffering to prevent flicker under follow-driven pans', () {
    test('the TileLayer carries keepBuffer, panBuffer and noFade tile display', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final tileLayerStart = src.indexOf('TileLayer(');
      expect(tileLayerStart, greaterThanOrEqualTo(0),
          reason: 'Landmark not found: TileLayer(. map_screen.dart\'s structure moved.');
      final openIdx = tileLayerStart + 'TileLayer'.length;
      final tileLayerBody = _extractBalanced(src, openIdx);
      expect(tileLayerBody, contains('keepBuffer: 4'),
          reason: 'per flutter-mobile-animation.md section 9, keepBuffer must be 4');
      expect(tileLayerBody, contains('panBuffer: 2'),
          reason: 'per flutter-mobile-animation.md section 9, panBuffer must be 2');
      expect(tileLayerBody, contains('tileDisplay: TileDisplay.noFade()'),
          reason: 'per flutter-mobile-animation.md section 9, tile display must skip the opacity-ramp pop-in');
    });
  });

  group('the existing track-version listener stays the first statement of build()', () {
    test('ref.listen<int> on runRecorderTrackVersionProvider remains before the loading early return', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      final buildIdx = src.indexOf('Widget build(BuildContext context) {');
      expect(buildIdx, greaterThanOrEqualTo(0));
      final listenIdx = src.indexOf('ref.listen<int>(runRecorderTrackVersionProvider', buildIdx);
      final loadingIdx = src.indexOf('slugsAsync.isLoading', buildIdx);
      expect(listenIdx, greaterThan(buildIdx));
      expect(listenIdx, lessThan(loadingIdx),
          reason: 'ref.listen on runRecorderTrackVersionProvider must remain the first statement in build(), '
              'before the loading early return, unchanged by this feature');
    });
  });
}

/// Extracts the balanced-parenthesis substring starting at [openIdx], which
/// must index a '(' character. Used to isolate the full TileLayer(...) call
/// without stopping at a nested call's own closing "),", such as
/// CachedNetworkTileProvider().
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
