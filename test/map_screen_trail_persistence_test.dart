// test/map_screen_trail_persistence_test.dart
//
// Verifies map_screen.dart paints the current-segment trail (persists until
// the next claim, then resets) rather than the whole session's raw track.
// Per flutter-test-patterns.md ("When NOT to use testWidgets for map tests"),
// this uses static source inspection rather than pumping MapScreen (which
// contains FlutterMap and would require mocking 5+ Riverpod providers just to
// reach initState).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('painted trail persistence wiring in map_screen.dart', () {
    late String src;

    setUpAll(() {
      src = File('lib/screens/map_screen.dart').readAsStringSync();
    });

    test('the live trail polyline reads currentSegmentTrack, not the raw trackSnapshot', () {
      final polylineBlockIdx = src.indexOf('Live track polyline while recording');
      expect(polylineBlockIdx, greaterThanOrEqualTo(0),
          reason: 'Landmark comment moved - update this anchor, do not delete the check.');
      final nextBlockIdx = src.indexOf('Own player comet', polylineBlockIdx);
      expect(nextBlockIdx, greaterThan(polylineBlockIdx));
      final block = src.substring(polylineBlockIdx, nextBlockIdx);

      expect(block, contains('RunRecorderService.instance.currentSegmentTrack'),
          reason: 'The persistent live trail must be scoped to the current (post-claim) '
              'segment, so it stays visible until the NEXT claim and then resets, rather '
              'than drawing the whole session track unbounded across every claim');
      expect(block, isNot(contains('RunRecorderService.instance.trackSnapshot')),
          reason: 'The live polyline must no longer read the raw session-wide trackSnapshot');
    });

    test('the runner comet tail also reads the current-segment trail', () {
      final cometBlockIdx = src.indexOf('Own player comet');
      expect(cometBlockIdx, greaterThanOrEqualTo(0));
      final nextBlockIdx = src.indexOf('GPS dot', cometBlockIdx);
      expect(nextBlockIdx, greaterThan(cometBlockIdx));
      final block = src.substring(cometBlockIdx, nextBlockIdx);

      expect(block, contains('RunRecorderService.instance.currentSegmentTrack'),
          reason: 'The comet tail must be derived from the same reset-on-claim segment as '
              'the persistent trail, so it never shows points from a loop that already claimed');
    });
  });
}
