// test/offline_owned_edge_claim_parity_test.dart
//
// RED phase, informational - AC-14 confirms the offline claim fallback
// (TerritoryService.evaluateClaim) never attempts a local merge, for both
// an ordinary self-closed claim and a new owned-edge-assisted one; Q3D's
// merge-vs-separate-row reconciliation only ever happens server-side, on
// the next online claim's full rescan.
//
// design.md states plainly that no functional change to territory_service.dart
// is required for this feature - _mergeAdjacentZones is already the shipped,
// intentional no-op this feature relies on. These are regression locks
// against that already-shipped invariant, not new-behaviour probes; they
// are expected to already pass today and must keep passing once the
// owned-edge closure feature ships, matching the accepted
// already-passing-invariant pattern used elsewhere in this suite
// (auto_claim_test.dart's non-regression group).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readTerritoryServiceSrc() =>
    File('lib/services/territory_service.dart').readAsStringSync();

void main() {
  group('offline claim path - no local merge, with or without an owned-edge-assisted sliver', () {
    // GIVEN the offline fallback's zone-reconciliation hook
    // WHEN a claim (ordinary or owned-edge-assisted) is processed locally
    // THEN _mergeAdjacentZones must remain an intentional no-op - Q3D's
    //   level-equality reconciliation is exclusively a server-side concern
    test('_mergeAdjacentZones stays an intentional no-op, unaffected by this feature', () {
      final src = _readTerritoryServiceSrc();

      final methodStart = src.indexOf('Future<void> _mergeAdjacentZones(');
      expect(methodStart, greaterThanOrEqualTo(0),
          reason: '_mergeAdjacentZones must still exist as the offline merge hook');

      // Bounded to the next sibling declaration's own signature, not the
      // first "}" after the method opens - a naive first-brace search finds
      // the true closing brace only by coincidence of this method's current
      // one-line body; it would silently truncate mid-body (and could miss
      // a later `await`) the moment any real logic with its own nested
      // braces were added - exactly the case this test exists to guard
      // against staying a no-op.
      final bodyEnd = src.indexOf('static List<LatLng> _sutherlandHodgman(', methodStart);
      expect(bodyEnd, greaterThan(methodStart),
          reason: 'Landmark not found: _sutherlandHodgman after _mergeAdjacentZones. '
              'territory_service.dart\'s structure moved - update this anchor, do not delete the check.');
      final body = src.substring(methodStart, bodyEnd);
      expect(body.contains('Intentionally a no-op'), isTrue,
          reason: 'The offline merge hook must remain a documented no-op - this feature adds '
              'no local merge/reconciliation logic of any kind');
      expect(body.contains('await'), isFalse,
          reason: 'A true no-op issues no async work of any kind, including for an '
              'owned-edge-assisted claim');
    });

    // GIVEN the doctrine's render-time-union-independent-of-row-count
    //   principle, restated by this spec for the unequal-level case
    // WHEN the offline no-op leaves an owned-edge sliver as its own row
    // THEN the doc comment must still cite the render-time union as what
    //   keeps the territory visually unified in the meantime
    test('the no-op doc comment still points at the render-time union as the visual fallback', () {
      final src = _readTerritoryServiceSrc();
      expect(src.contains('_buildUnifiedOwnedPolygons'), isTrue,
          reason: 'The offline no-op must still document that the render-time union, not a '
              'local merge, is what keeps territory looking unified until the next online claim');
    });
  });

  group('non-regression - full-containment overlap path is untouched by AC-7', () {
    // GIVEN a self-closed loop that fully encloses a previously-claimed
    //   sub-area from outside (the pre-existing ownedOverlapIds path)
    // WHEN evaluateClaim processes it
    // THEN this remains the existing containment path - it is explicitly
    //   NOT the AC-7 split case (which only applies when a re-run retraces
    //   PART of an existing zone's own edge, not when it strictly encloses
    //   a sub-area from outside)
    test('ownedOverlapIds containment logic is present and untouched by this feature', () {
      final src = _readTerritoryServiceSrc();
      expect(src.contains('ownedOverlapIds'), isTrue,
          reason: 'The pre-existing full-containment overlap path must still exist, '
              'confirming this feature adds no new split/merge branch to the offline fallback');
    });
  });
}
