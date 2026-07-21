// test/unified_owned_polygons_render_test.dart
//
// RED phase - unequal-level adjacent zones must render as one shared
// outline with each sub-area keeping its own fill alpha, instead of one
// group-wide alpha computed from the group's maximum level.
//
// map_screen.dart contains a FlutterMap, and _buildUnifiedOwnedPolygons is a
// private State method with no exposed test seam (unlike the adjacency
// grouping helper, which is already exposed via groupAdjacentZonesForTesting
// in territory_merge_test.dart). Per flutter-test-patterns.md ("source
// inspection instead of testWidgets for routing assertions") and this
// repo's own claim_territory_merge_wiring_test.ts precedent, these tests
// read the source directly and assert on the structural change the design
// calls for, rather than rendering pixels.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readMapScreenSrc() => File('lib/screens/map_screen.dart').readAsStringSync();

// Scopes assertions to _buildUnifiedOwnedPolygons's own body, not the whole
// file - map_screen.dart already uses isFilled: false elsewhere (the
// pre-existing owned-zone glow layer), so an unscoped `contains` check would
// pass vacuously without the AC-6 rewrite ever touching this function.
String _buildUnifiedOwnedPolygonsBody(String src) {
  final start = src.indexOf('List<Polygon> _buildUnifiedOwnedPolygons(');
  expect(start, greaterThanOrEqualTo(0),
      reason: '_buildUnifiedOwnedPolygons must still exist in map_screen.dart');
  final end = src.indexOf('/// Handles a map tap', start);
  expect(end, greaterThan(start),
      reason: 'Could not locate the end of _buildUnifiedOwnedPolygons for scoped inspection');
  return src.substring(start, end);
}

void main() {
  group('per-sub-area fill alpha for unequal-level adjacent zones', () {
    // GIVEN the render function currently computes one group-wide level via
    //   group.map((z) => z.influenceLevel).reduce(math.max) and applies that
    //   single fillAlpha to every sub-area in the group
    // WHEN the AC-6 rewrite lands
    // THEN a per-zone fill alpha, computed from each zone's OWN
    //   influenceLevel, must exist in the source
    test('fill alpha is computed per zone from its own influenceLevel, not the group max', () {
      final body = _buildUnifiedOwnedPolygonsBody(_readMapScreenSrc());

      expect(body.contains('z.influenceLevel.clamp(1, 15)'), isTrue,
          reason: 'Each source zone must compute its own clamped level rather than reducing '
              'the whole group to one shared level for fill purposes');
    });

    // GIVEN the shared outline must be drawn with no interior seam between
    //   sub-areas
    // WHEN the AC-6 rewrite lands
    // THEN the outline pass must emit stroke-only polygons (isFilled: false)
    //   separately from the new per-zone fill-only polygons
    test('the shared outline is emitted as a stroke-only polygon, separate from per-zone fills', () {
      final body = _buildUnifiedOwnedPolygonsBody(_readMapScreenSrc());

      expect(body.contains('isFilled: false'), isTrue,
          reason: 'The shared-outline pass must emit stroke-only polygons once fills are '
              'split into their own per-zone pass');
    });

    // GIVEN a per-zone fill polygon must not draw its own border (the
    //   shared outline pass owns the border)
    // WHEN the AC-6 rewrite lands
    // THEN the per-zone fill pass must set borderStrokeWidth to 0
    test('per-zone fill polygons carry no border of their own', () {
      final body = _buildUnifiedOwnedPolygonsBody(_readMapScreenSrc());

      expect(body.contains('borderStrokeWidth: 0'), isTrue,
          reason: 'Per-zone fills must not draw a competing border under the shared outline');
    });
  });

  group('non-regression - single-zone fast path is untouched by the AC-6 rewrite', () {
    // GIVEN a group of exactly one zone with a single outline (today's fast
    //   path at group.length == 1)
    // WHEN the AC-6 rewrite lands
    // THEN the existing fast-path condition must still be present verbatim -
    //   this is a lock against the rewrite accidentally touching the
    //   single-zone case
    //
    // Already true of today's source; expected to remain true after the
    // AC-6 rewrite - a regression lock, not a new-behaviour probe.
    test('the group.length == 1 fast-path condition is still present', () {
      final src = _readMapScreenSrc();

      expect(
        src.contains('if (group.length == 1 && group.first.outlines.length <= 1)'),
        isTrue,
        reason: 'The single-zone fast path must remain byte-for-byte unaffected by the '
            'per-sub-area rewrite',
      );
    });
  });

  group('non-regression - MultiPolygon-shaped zones within a group render every outline', () {
    // GIVEN a zone whose own geometry is a MultiPolygon (e.g. a legacy
    //   Tier-2 merge), sitting inside a rendered group
    // WHEN _buildUnifiedOwnedPolygons builds fills for that group
    // THEN it must still iterate every outline of every zone (z.outlines),
    //   so a MultiPolygon-shaped zone contributes one fill per member
    //   outline with no special-casing or bridging between them
    //
    // This assertion already holds against today's source (the existing
    // outline-union loop already iterates z.outlines) and is expected to
    // keep passing after the AC-6 rewrite - it is a regression lock, not a
    // new-behaviour probe, matching the accepted already-passing-invariant
    // pattern used elsewhere in this suite (auto_claim_test.dart's
    // non-regression group).
    test('the per-zone render loop iterates every outline of every zone', () {
      final src = _readMapScreenSrc();

      expect(src.contains('for (final outline in z.outlines)'), isTrue,
          reason: 'Every outline of every zone (including a MultiPolygon-shaped one) must be '
              'iterated individually so disjoint contours are never bridged');
    });
  });
}
