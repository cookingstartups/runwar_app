// test/screens/map_carved_hole_render_test.dart
//
// RED phase: a concave/donut zone (a shielded overlap carved out of a rival
// claim) must render as a visible gap on the map, not a solid fill, across
// every render surface map_screen.dart owns - the single-zone fast path, the
// seamless same-owner underlay union (which must subtract holes via
// PathOperation.difference before computeMetrics() walks the contours), the
// per-zone fill pass, and the tap hit-test (a tap inside the hole must not
// register as a hit on the surrounding zone).
//
// map_screen.dart contains a FlutterMap, whose tile-fetch timers make
// testWidgets pumping generate hundreds of spurious HTTP-400 exceptions
// (see flutter-mobile-animation venture protocol / flutter-test-patterns.md
// §2). The render-composition assertions below therefore use static source
// inspection, anchored on the enclosing method by name (never by first
// token occurrence), matching the house convention already established in
// test/screens/map_screen_owner_zone_always_visible_test.dart. The tap
// hit-test assertion is a real behavioral unit test against the new
// zoneContainsPointRespectingHoles() pure function instead, since that one
// does not require any widget tree at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/screens/map_screen.dart';
import 'package:runwar_app/services/database/models/zone.dart';

// Locates a landmark-delimited slice of [src]. Callable outside a test()
// body (e.g. at group-registration time) because it does not call
// flutter_test's expect() - flutter_test forbids expect() outside an active
// test zone (OutsideTestException), which a landmark lookup at group level
// would otherwise trip before any test even runs.
String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  if (start < 0) {
    throw StateError(
        'Landmark not found: "$startMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  }
  final end = src.indexOf(endMarker, start + startMarker.length);
  if (end <= start) {
    throw StateError(
        'Landmark not found after "$startMarker": "$endMarker". map_screen.dart\'s structure moved - update this anchor, do not delete the check.');
  }
  return src.substring(start, end);
}

void main() {
  final src = File('lib/screens/map_screen.dart').readAsStringSync();
  final unifiedMethod = _sliceToNextMember(
      src,
      'List<Polygon> _buildUnifiedOwnedPolygons(List<Zone> zones) {',
      'Future<void> _handleMapTap(');

  group('_buildUnifiedOwnedPolygons: carved holes must render as a visible gap', () {
    test('single-zone fast path passes holePointsList through to the flutter_map Polygon', () {
      final fastPath = _sliceToNextMember(
          unifiedMethod,
          'if (group.length == 1 && group.first.outlines.length <= 1) {',
          'continue;');

      // Tightened: a bare `contains('holePointsList')` would pass even if
      // the value wired in were `holePointsList: null` or `const []`, which
      // renders identically to no holePointsList at all - the defect would
      // survive and this test would go green regardless. Require the real
      // operand: an expression that reads group.first.holeOutlines (the
      // actual Zone field the design routes through this site).
      final holePointsListArg = RegExp(
          r'holePointsList\s*:[\s\S]{0,120}?group\.first\.holeOutlines');
      expect(holePointsListArg.hasMatch(fastPath), isTrue,
          reason: 'the single-zone fast path builds a flutter_map Polygon '
              'directly from group.first without ever passing '
              'holePointsList: group.first.holeOutlines - a shielded zone '
              'with a carved hole would render as a solid fill through this '
              'path even though flutter_map natively supports donut '
              'rendering via Polygon.holePointsList. A bare occurrence of '
              'the token "holePointsList" is not sufficient proof: '
              '`holePointsList: null` or `holePointsList: const []` would '
              'also satisfy that weaker check while still rendering solid.');
    });

    test('the seamless underlay union subtracts holes via PathOperation.difference before computeMetrics() walks the contours', () {
      final underlayBlock = _sliceToNextMember(
          unifiedMethod, 'var unified = Path();', 'computeMetrics()');

      // Tightened: a bare `contains('PathOperation.difference')` would pass
      // if that token appeared anywhere in the block, including in an
      // unrelated comment or a call with the wrong operands. Require the
      // real Path.combine call, scoped to its first two operands: the
      // difference operation applied to the `unified` accumulator (the
      // union of every exterior built just above it).
      final differenceCombine = RegExp(
          r'Path\.combine\(\s*PathOperation\.difference\s*,\s*unified\s*,');
      expect(differenceCombine.hasMatch(underlayBlock), isTrue,
          reason: 'the underlay currently only ever composes exteriors with '
              'PathOperation.union - a hole must be subtracted from the '
              'unioned shape via Path.combine(PathOperation.difference, '
              'unified, holePath) before computeMetrics() is called, or the '
              'seamless underlay fills straight over a carved hole '
              'regardless of what the per-zone fill pass draws on top. A '
              'bare occurrence of the token "PathOperation.difference" is '
              'not sufficient proof: it could appear in a comment, or in a '
              'Path.combine call with the wrong operands entirely.');
    });

    test('the per-zone fill pass also passes holePointsList for each member outline', () {
      final fillPass = _sliceToNextMember(
          unifiedMethod, '// Per-zone fill pass', 'return out;');

      // Tightened for the same reason as the fast-path check above: require
      // the real operand, an expression reading z.holeOutlines (the loop
      // variable this pass actually iterates over), not a bare token match.
      final holePointsListArg =
          RegExp(r'holePointsList\s*:[\s\S]{0,120}?z\.holeOutlines');
      expect(holePointsListArg.hasMatch(fillPass), isTrue,
          reason: 'the per-zone fill pass builds one flutter_map Polygon per '
              'outline without ever passing holePointsList: z.holeOutlines '
              '- drawn on top of the underlay, this pass alone would '
              'repaint a carved hole solid even if the underlay difference '
              'above were fixed. A bare occurrence of the token '
              '"holePointsList" is not sufficient proof: `holePointsList: '
              'null` or `holePointsList: const []` would also satisfy that '
              'weaker check while still rendering solid.');
    });
  });

  group('tap hit-test: a tap inside a carved hole must not register as a hit', () {
    // A 10x10 square zone with a 4x4 hole punched in its centre.
    final exterior = [
      const LatLng(0, 0),
      const LatLng(10, 0),
      const LatLng(10, 10),
      const LatLng(0, 10),
    ];
    final hole = [
      const LatLng(3, 3),
      const LatLng(7, 3),
      const LatLng(7, 7),
      const LatLng(3, 7),
    ];

    const holedZone = Zone(
      id: 'zone-1',
      ownerId: 'player-b',
      city: 'Valencia',
      influenceLevel: 2,
      status: ZoneStatus.owned,
      points: [],
    );
    final zoneWithHole = Zone(
      id: holedZone.id,
      ownerId: holedZone.ownerId,
      city: holedZone.city,
      influenceLevel: holedZone.influenceLevel,
      status: holedZone.status,
      points: exterior,
      outlines: [exterior],
      holeOutlines: [hole],
    );

    test('a tap in the middle of the shape but inside the carved hole reports no containment', () {
      const tapInsideHole = LatLng(5, 5);

      final hit = zoneContainsPointRespectingHoles(zoneWithHole, tapInsideHole);

      expect(hit, isFalse,
          reason: 'a tap inside a carved-out hole must not be reported as a '
              'hit on the surrounding zone - opening the attack sheet for '
              'territory the shielded defender was never dispossessed of. '
              'zoneContainsPointRespectingHoles currently tests only the '
              'exterior ring and completely ignores Zone.holeOutlines, so '
              'this reports true today');
    });

    test('a tap well inside the exterior but outside the hole still reports containment (non-regression)', () {
      const tapInSolidArea = LatLng(1, 1);

      final hit = zoneContainsPointRespectingHoles(zoneWithHole, tapInSolidArea);

      expect(hit, isTrue,
          reason: 'a tap on ordinary held territory outside the hole must still register a hit');
    });
  });
}
