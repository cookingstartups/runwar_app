// test/claim_capture_flash_and_level_label_test.dart
//
// RED phase - map_screen.dart does not yet expose the pure, testable seams
// this feature needs (isCaptureFlashTriggerForTesting,
// groupInfluenceLevelForTesting, zoneLevelLabelsForTesting), so every test
// below fails to compile until they land.
//
// Covers the two decidable parts of "capture flash + level label":
//   1. The trigger predicate - does a claim outcome play the flash?
//   2. The per-holding label value - one label per contiguity group,
//      showing the group's max influence level.
//   3. A regression lock on the steady fill formula (0.0633 * level),
//      unchanged by this feature.
//
// Animation playback itself (the flash/ring easing over time) is not
// asserted here - flutter-test-patterns.md's source-inspection convention
// covers the non-widget-testable painter/controller wiring instead, in the
// regression-lock group below.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/screens/map_screen.dart'
    show
        isCaptureFlashTriggerForTesting,
        groupInfluenceLevelForTesting,
        zoneLevelLabelsForTesting,
        groupLabelAnchorForTesting;
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/services/territory_service.dart' show TerritoryResult;
import 'package:runwar_app/geo/lasso.dart' show pointInPolygon;

// A ~40m-side square, in the Valencia area (lat ~39.47), starting at the
// given (lat, lng) origin. Mirrors territory_merge_test.dart's own fixture.
List<LatLng> _squareAt(double lat0, double lng0) {
  const dLat = 0.0003618; // ~40 m north-south
  const dLng = 0.0004657; // ~40 m east-west at lat 39.47
  return [
    LatLng(lat0, lng0),
    LatLng(lat0, lng0 + dLng),
    LatLng(lat0 + dLat, lng0 + dLng),
    LatLng(lat0 + dLat, lng0),
  ];
}

Zone _zone(
  String id,
  String ownerId,
  List<LatLng> pts, {
  ZoneStatus status = ZoneStatus.owned,
  int influenceLevel = 1,
}) =>
    Zone(
      id: id,
      ownerId: ownerId,
      city: 'valencia',
      influenceLevel: influenceLevel,
      status: status,
      points: pts,
    );

void main() {
  group('capture flash trigger predicate', () {
    // GIVEN a claim outcome that is a genuine territorial gain
    // WHEN isCaptureFlashTriggerForTesting evaluates it
    // THEN it fires for claimed and conquered
    test('fires for claimed and conquered', () {
      expect(isCaptureFlashTriggerForTesting(TerritoryResult.claimed), isTrue,
          reason: 'A first claim is a real gain and must play the flash');
      expect(isCaptureFlashTriggerForTesting(TerritoryResult.conquered), isTrue,
          reason: 'A successful conquest is a real gain and must play the flash');
    });

    // GIVEN a claim outcome that is not a gain (still contested, or the
    //   claim never landed)
    // WHEN isCaptureFlashTriggerForTesting evaluates it
    // THEN it never fires for disputed or failed
    test('never fires for disputed or failed', () {
      expect(isCaptureFlashTriggerForTesting(TerritoryResult.disputed), isFalse,
          reason: 'A dispute has not resolved into a gain yet - no flash');
      expect(isCaptureFlashTriggerForTesting(TerritoryResult.failed), isFalse,
          reason: 'A failed claim landed nothing - no flash');
    });
  });

  group('per-holding influence-level label value', () {
    // GIVEN a contiguity group of same-owner zones at mixed levels
    // WHEN groupInfluenceLevelForTesting computes the displayed level
    // THEN it is the group's max, clamped 1..15 - the same reduction the
    //   fill formula already performs
    test('shows the group max, not the min or an average', () {
      final group = [
        _zone('z1', 'p1', _squareAt(39.470000, 33.000000), influenceLevel: 2),
        _zone('z2', 'p1', _squareAt(39.470000, 33.000466), influenceLevel: 7),
        _zone('z3', 'p1', _squareAt(39.470000, 33.000932), influenceLevel: 4),
      ];

      expect(groupInfluenceLevelForTesting(group), 7,
          reason: 'The displayed level must be the max across the group (7), '
              'not the min (2) or an average (~4.3)');
    });

    // GIVEN a group whose max level exceeds the 1..15 display range
    // WHEN groupInfluenceLevelForTesting computes the displayed level
    // THEN it clamps to 15
    test('clamps the displayed level to 15', () {
      final group = [
        _zone('z1', 'p1', _squareAt(39.470000, 33.000000), influenceLevel: 20),
      ];

      expect(groupInfluenceLevelForTesting(group), 15);
    });

    // GIVEN two same-owner zones that touch (one contiguity group) plus a
    //   third zone belonging to a different owner far away (its own group)
    // WHEN zoneLevelLabelsForTesting computes labels for all rendered
    //   holdings
    // THEN exactly one label is produced per contiguity group - never one
    //   per zone and never one per outline within a group
    test('one label per contiguity group, not per zone or outline', () {
      final touching = [
        _zone('z1', 'p1', _squareAt(39.470000, 33.000000), influenceLevel: 3),
        _zone('z2', 'p1', _squareAt(39.470000, 33.000466), influenceLevel: 9),
      ];
      final farAway = _zone(
        'z3',
        'p2',
        _squareAt(39.480000, 33.100000),
        influenceLevel: 5,
      );

      final labels = zoneLevelLabelsForTesting([...touching, farAway]);

      expect(labels, hasLength(2),
          reason: 'Two contiguity groups (the touching pair, and the lone '
              'far-away zone) must produce exactly two labels, not three '
              '(one per zone) and not one (collapsed across owners)');
      expect(labels.map((l) => l.level), containsAll(<int>[9, 5]),
          reason: 'The touching pair shows its group max (9); the lone zone '
              'shows its own level (5)');
    });

    // GIVEN a disputed zone (not an owned holding)
    // WHEN zoneLevelLabelsForTesting computes labels
    // THEN no label is produced for it - labels are for owned holdings only
    test('disputed zones are never labeled', () {
      final disputed = _zone(
        'z1',
        'p1',
        _squareAt(39.470000, 33.000000),
        status: ZoneStatus.disputed,
        influenceLevel: 4,
      );

      expect(zoneLevelLabelsForTesting([disputed]), isEmpty,
          reason: 'A disputed zone is not a rendered holding and must not '
              'get a level label');
    });

    // GIVEN a group whose combined outline is concave enough that the
    //   naive average-of-all-vertices centroid falls outside every member
    //   outline (an L-shaped pair of touching squares)
    // WHEN groupLabelAnchorForTesting picks a label anchor
    // THEN it still returns a point that lies inside at least one member
    //   outline of the group - never an unanchored/outside point
    test('label anchor for a concave group still lands inside the shape', () {
      // Two squares touching only at a shared edge offset diagonally,
      // forming an L - the straight average of all 8 vertices sits in the
      // concave notch, outside both squares.
      final a = _squareAt(39.470000, 33.000000);
      final b = _squareAt(39.470362, 33.000466); // offset north + east
      final group = [
        _zone('a', 'p1', a, influenceLevel: 1),
        _zone('b', 'p1', b, influenceLevel: 1),
      ];

      final anchor = groupLabelAnchorForTesting(group);

      expect(
        pointInPolygon(anchor, a) || pointInPolygon(anchor, b),
        isTrue,
        reason: 'The label anchor must fall inside at least one member '
            'outline of the group, even when the naive group-wide centroid '
            'lands outside every outline',
      );
    });
  });

  group('regression lock - steady fill formula is unchanged', () {
    // GIVEN the pre-existing steady-state fill formula in
    //   _buildUnifiedOwnedPolygons (0.0633 * level for the group-wide base
    //   alpha, and 0.0633 * zLevel for the per-zone sub-area alpha)
    // WHEN this feature's flash/label work lands
    // THEN both formulas must remain byte-for-byte present - this feature
    //   only adds a transient overlay and a label, it must never touch the
    //   steady render math
    test('0.0633 * level and 0.0633 * zLevel are still present verbatim', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();

      expect(src.contains('0.0633 * level'), isTrue,
          reason: 'The group-wide steady base alpha formula must be unchanged');
      expect(src.contains('0.0633 * zLevel'), isTrue,
          reason: 'The per-zone steady sub-area alpha formula must be unchanged');

      // Sanity: level 1 must still render at ~6.3% alpha (the "faint
      // low-level fill is intentional" decision this feature's label makes
      // legible), not some rescaled value.
      const level = 1;
      const baseAlpha = 0.0633 * level;
      expect(baseAlpha, closeTo(0.063, 0.001));
    });
  });
}
