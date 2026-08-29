// test/unified_owned_polygons_render_test.dart
//
// Owned-territory rendering is fill-only and static: unequal-level adjacent
// zones render as one seamless shape with each sub-area keeping its own
// fill alpha, and there is no border or glow stroke anywhere for owned
// zones (the border/glow was removed in favor of pure fill depth).
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
// file - map_screen.dart's disputed-zone rendering elsewhere in the file
// still uses borderStrokeWidth/isDotted, so an unscoped `contains` check
// would pass vacuously without these assertions ever touching this
// function.
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

    // GIVEN owned-territory rendering is fill-only and static (no pulse, no
    //   border, no glow) - influence is conveyed by fill depth alone
    // WHEN the rendering function builds a multi-zone group
    // THEN it must never emit an unfilled/stroke-only polygon (isFilled:
    //   false is reserved for the disputed-zone amber dotted border
    //   elsewhere in the file, never for owned zones)
    test('owned-zone rendering never emits an unfilled/stroke-only polygon', () {
      final body = _buildUnifiedOwnedPolygonsBody(_readMapScreenSrc());

      expect(body.contains('isFilled: false'), isFalse,
          reason: 'Owned zones are fill-only - no border/glow/outline pass may render an '
              'unfilled polygon in _buildUnifiedOwnedPolygons');
    });

    // GIVEN the fill alpha must be static (no pulse modulation)
    // WHEN the rendering function computes fill alpha for owned zones
    // THEN the source must never multiply by a pulse-derived factor
    test('owned-zone fill alpha carries no pulse modulation', () {
      final body = _buildUnifiedOwnedPolygonsBody(_readMapScreenSrc());

      expect(body.contains('0.75 + 0.25 * pulse'), isFalse,
          reason: 'Owned-zone fill must be static - the pulse-derived scaling factor must be '
              'gone entirely');
      expect(body.contains('pulse'), isFalse,
          reason: '_buildUnifiedOwnedPolygons must not reference pulse at all once owned '
              'rendering is static');
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

  group('ZoneLevelBadge removed entirely, no replacement indicator', () {
    // GIVEN the operator decision to remove ZoneLevelBadge with no
    //   replacement indicator - influence level is conveyed by fill depth
    //   alone
    // WHEN map_screen.dart is inspected
    // THEN it must not import or reference ZoneLevelBadge anywhere, and the
    //   widget file itself must no longer exist
    //
    // If this test is reverted along with the badge removal, both
    // assertions fail immediately: the import line reappears and
    // zone_level_badge.dart is restored to disk.
    test('map_screen.dart does not reference ZoneLevelBadge', () {
      final src = _readMapScreenSrc();

      expect(src.contains('ZoneLevelBadge'), isFalse,
          reason: 'ZoneLevelBadge was removed with no replacement indicator - map_screen.dart '
              'must not import or construct it');
    });

    test('zone_level_badge.dart no longer exists', () {
      expect(File('lib/widgets/zone_level_badge.dart').existsSync(), isFalse,
          reason: 'The widget file itself must be deleted, not just unreferenced');
    });
  });

  group('owned-zone rendering has no border/glow layer anywhere in the file', () {
    // GIVEN owned zones render fill-only with no border stroke and no glow
    //   layer
    // WHEN _buildPolygonsGlow (the glow/background polygon layer) is
    //   inspected
    // THEN it must no longer branch on ZoneStatus.owned at all - only
    //   disputed zones may still glow
    //
    // If the owned branch is reintroduced, this fails because the glow
    // function's body would contain an owned-status check again.
    test('_buildPolygonsGlow never branches on ZoneStatus.owned', () {
      final src = _readMapScreenSrc();
      final start = src.indexOf('List<Polygon> _buildPolygonsGlow(');
      expect(start, greaterThanOrEqualTo(0),
          reason: '_buildPolygonsGlow must still exist (disputed zones still glow)');
      final end = src.indexOf('/// Builds the main polygon layer', start);
      expect(end, greaterThan(start),
          reason: 'Could not locate the end of _buildPolygonsGlow for scoped inspection');
      final body = src.substring(start, end);

      expect(body.contains('ZoneStatus.owned'), isFalse,
          reason: 'The glow layer must never render anything for owned zones - fill only, no '
              'glow border');
    });
  });
}
