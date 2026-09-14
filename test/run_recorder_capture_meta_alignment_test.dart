// test/run_recorder_capture_meta_alignment_test.dart
//
// Runtime regression test for the client-side metadata/polygon index-
// alignment finding: the polygon RunRecorderService actually dispatches to
// onAutoClaim is Douglas-Peucker simplified AFTER capture, so metadata
// sliced against the RAW (pre-simplification) index range silently drifts
// out of alignment with it the moment simplification drops a vertex - which
// happens on any real GPS track with a straight-ish stretch.
//
// This test drives the real, exported production functions
// (computeCapture, computeCaptureMeta, simplifyDouglasPeucker,
// simplifyDouglasPeuckerKeptIndices) against a fixture deliberately shaped
// so Douglas-Peucker drops a real vertex, and asserts on the actual
// resulting arrays - not on source text.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/geo/douglas_peucker.dart';
import 'package:runwar_app/geo/lasso.dart' show computeCapture;
import 'package:runwar_app/services/run_recorder_service.dart'
    show computeCaptureMeta;

const double _centerLat = 34.700;
const double _centerLng = 33.000;

LatLng _offsetMetres(LatLng base, double dxM, double dyM) {
  final dLat = dyM / 110540.0;
  final dLng = dxM / (111320.0 * math.cos(base.latitude * math.pi / 180.0));
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}

void main() {
  group('capture-polygon and capture-metadata stay index-aligned through simplification', () {
    test(
      'metadata sliced by the same kept-index set as the simplified polygon '
      'matches it 1:1 - metadata sliced against the raw index range does not',
      () {
        const anchor = LatLng(_centerLat, _centerLng);
        // A near-straight 100 m trail with mid-points jittered a few metres
        // off the true path (well under the 10 m Douglas-Peucker epsilon),
        // followed by a real closing hop. simplifyDouglasPeucker collapses
        // the jittered interior points to just the two endpoints (matching
        // the identical fixture shape in test/geo/douglas_peucker_test.dart
        // that already proves this collapse happens under this epsilon).
        final trail = <LatLng>[
          anchor, // 0: loopStartTrailIndex placeholder, unused by computeCapture
          _offsetMetres(anchor, 0, 0), // 1: intersectingSegmentIdx
          _offsetMetres(anchor, 25, 3), // 2: dropped by DP
          _offsetMetres(anchor, 50, -4), // 3: dropped by DP
          _offsetMetres(anchor, 75, 2), // 4: dropped by DP
          _offsetMetres(anchor, 100, 0), // 5: k (closing vertex)
        ];
        const intersectingSegmentIdx = 1;
        const k = 5;
        final intersectionPoint = trail[intersectingSegmentIdx];

        // One timestamp/altitude pair per _track index, matching the
        // production _trackTsMs/_trackAltM convention.
        final tsMs = List<int>.generate(trail.length, (i) => 1000 * i);
        final altM = List<double?>.generate(
          trail.length,
          (i) => i.isEven ? 10.0 + i : null, // mix of real and unknown alt
        );

        // Proximity closure (isProximityClosure: true) so computeCapture
        // does not prepend a synthetic vertex - keeps this fixture focused
        // purely on the Douglas-Peucker alignment question, not the
        // separate synthetic-vertex approximation.
        final rawPolygon = computeCapture(
          trail,
          1,
          intersectingSegmentIdx,
          intersectionPoint,
          k,
          isProximityClosure: true,
        );
        final rawMeta = computeCaptureMeta(
          tsMs,
          altM,
          intersectingSegmentIdx,
          k,
          isProximityClosure: true,
        );

        // Baseline: computeCapture/computeCaptureMeta slice the exact same
        // raw index range, so they start out aligned.
        expect(rawMeta.length, rawPolygon.length);

        final simplifiedPolygon = simplifyDouglasPeucker(rawPolygon);
        // The fixture must actually exercise a real simplification - if DP
        // stops dropping the jittered interior points, this fixture no
        // longer tests anything and must be reshaped.
        expect(simplifiedPolygon.length, lessThan(rawPolygon.length),
            reason: 'fixture must exercise Douglas-Peucker actually '
                'dropping a vertex, or this test proves nothing about the '
                'alignment bug it targets.');

        // THE BUG this test guards against: metadata sliced against the RAW
        // index range no longer matches the DISPATCHED (simplified) polygon
        // once simplification has dropped anything. This is exactly the
        // mismatch that made TerritoryService.metaForTrack's own
        // `m.length == simplifiedTracks[i].length` guard silently fall back
        // to the legacy 2-tuple shape for every real, non-straight-line GPS
        // track.
        expect(rawMeta.length, isNot(simplifiedPolygon.length),
            reason: 'this assertion documents the pre-fix failure mode: '
                'raw (pre-simplification) metadata length does not match '
                'the simplified polygon length whenever DP drops a vertex.');

        // THE FIX: slicing metadata by the SAME kept-index set the
        // simplification step used keeps it aligned by construction.
        final keptIdx = simplifyDouglasPeuckerKeptIndices(rawPolygon);
        final alignedMeta = [for (final i in keptIdx) rawMeta[i]];

        expect(alignedMeta.length, simplifiedPolygon.length,
            reason: 'metadata sliced by the simplification kept-index set '
                'must be index-aligned 1:1 with the simplified polygon - if '
                'this fails, the alignment fix regressed.');
        // Endpoints must carry their own original timestamp/altitude, not a
        // neighbour's.
        expect(alignedMeta.first[0], rawMeta.first[0]);
        expect(alignedMeta.last[0], rawMeta.last[0]);
      },
    );
  });
}
