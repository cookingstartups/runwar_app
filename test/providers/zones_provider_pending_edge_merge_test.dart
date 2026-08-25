// test/providers/zones_provider_pending_edge_merge_test.dart
//
// rw_app-territory-vanish: the map's rendered zone list has exactly one
// source, zonesProvider(city)'s stream. A claim confirmed while a run was
// finishing (e.g. the final loop's claim still in flight when Finish is
// tapped) invalidates that stream but the invalidated re-fetch is async -
// nothing rendered the outline in the meantime, so the just-captured zone
// could go missing from the map immediately after Finish until the stream
// happened to re-emit (or forever, if nothing ever nudged it to).
//
// mergePendingOwnedZoneEdges is the pure fix: it folds RunRecorderNotifier's
// pendingOwnedZoneEdges cache (already written on every successful claim,
// previously consumed only by the scan-time closure - never by MapScreen)
// into whatever zonesAsync last delivered, so the claimed outline renders
// immediately and is dropped the moment the real row shows up.
//
// Reverting map_screen.dart's merge wiring (or deleting this function) means
// a pending outline for a zone id absent from `zones` never appears in the
// merged list - the first two tests below fail for that exact reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runwar_app/providers/zones_provider.dart';
import 'package:runwar_app/services/database/models/zone.dart';

Zone _zone(String id, {String ownerId = 'owner-1'}) => Zone(
      id: id,
      ownerId: ownerId,
      city: 'Nicosia',
      influenceLevel: 1,
      status: ZoneStatus.owned,
      points: const [LatLng(35.0, 33.0), LatLng(35.01, 33.0), LatLng(35.01, 33.01)],
    );

void main() {
  group('mergePendingOwnedZoneEdges', () {
    test('a pending outline for a zone id absent from zones is rendered', () {
      final zones = <Zone>[];
      final pending = {
        'zone-final-claim': [
          const [LatLng(35.0, 33.0), LatLng(35.01, 33.0), LatLng(35.01, 33.01)],
        ],
      };

      final merged = mergePendingOwnedZoneEdges(zones, pending, 'runner-1');

      expect(merged, hasLength(1),
          reason: 'a claim the zonesAsync stream has not caught up with '
              'must still render - this is the exact symptom this fix '
              'covers (revert this function and the zone never appears)');
      expect(merged.single.id, 'zone-final-claim');
      expect(merged.single.ownerId, 'runner-1');
      expect(merged.single.status, ZoneStatus.owned);
    });

    test('a pending outline is dropped once the real zone lands in zones', () {
      final zones = [_zone('zone-final-claim', ownerId: 'runner-1')];
      final pending = {
        'zone-final-claim': [
          const [LatLng(35.0, 33.0), LatLng(35.01, 33.0), LatLng(35.01, 33.01)],
        ],
      };

      final merged = mergePendingOwnedZoneEdges(zones, pending, 'runner-1');

      expect(merged, hasLength(1),
          reason: 'the fresh snapshot must win - no duplicate synthetic '
              'entry once the real row is present');
      expect(merged.single, same(zones.single));
    });

    test('an empty pending map returns the original zones list unchanged',
        () {
      final zones = [_zone('zone-a')];
      final merged = mergePendingOwnedZoneEdges(zones, const {}, 'runner-1');
      expect(merged, same(zones));
    });

    test('multiple pending outlines for different unclaimed-server-side ids '
        'all render alongside each other', () {
      final pending = {
        'zone-a': [const [LatLng(1, 1), LatLng(1, 2), LatLng(2, 2)]],
        'zone-b': [const [LatLng(3, 3), LatLng(3, 4), LatLng(4, 4)]],
      };

      final merged = mergePendingOwnedZoneEdges(const [], pending, 'runner-1');

      expect(merged.map((z) => z.id).toSet(), {'zone-a', 'zone-b'});
      expect(merged.every((z) => z.ownerId == 'runner-1'), isTrue);
    });
  });
}
