// test/territory_service_speed_payload_test.dart
//
// R1: TerritoryService.claimViaEdgeFunction emits a [lng, lat, alt, ts_ms]
// 4-tuple per vertex when per-vertex metadata is available, and falls back
// to the legacy [lng, lat] 2-tuple when it is not (design.md section 6.5,
// the client-side half of the "accept both shapes" compatibility decision
// in design.md section 3).
//
// coordOf/lineStringOf are private closures inside claimViaEdgeFunction
// today (2-argument-free, [lng, lat]-only) - there is no existing public
// seam to call them directly, and no existing territory_service test file
// mocks the Supabase functions client (grepped: no such test exists in
// test/services/ today). This file therefore follows the same
// landmark-anchored source-inspection convention used elsewhere in this
// spec's Deno/Dart sibling files, anchored to the coordOf snippet given
// verbatim in design.md section 6.5.
//
// Flutter SDK availability: NOT confirmed runnable in this environment at
// authoring time. Written to the same rigor as if runnable; NOT executed
// here. Run with: flutter test test/territory_service_speed_payload_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'lib/services/territory_service.dart';

void main() {
  group('R1: claimViaEdgeFunction emits [lng, lat, alt, ts_ms] when tracksMeta is supplied', () {
    test('tracksMeta is a new optional named parameter on claimViaEdgeFunction', () {
      final src = File(_path).readAsStringSync();
      expect(src, contains('tracksMeta'),
          reason: 'claimViaEdgeFunction must gain a new optional named parameter tracksMeta (design.md section 6.4/6.5) - today this parameter does not exist at all.');
    });

    test('coordOf emits a 4-element [lng, lat, alt, ts_ms] tuple when meta is supplied, and the legacy 2-element tuple otherwise', () {
      final src = File(_path).readAsStringSync();
      // The exact per-vertex tuple order given verbatim in design.md section
      // 6.5: [p.longitude, p.latitude, meta[1], meta[0]] (alt before ts_ms,
      // matching the point-shape order [lng, lat, alt, ts_ms]).
      expect(src, contains('meta[1], meta[0]'),
          reason: 'coordOf must build the 4-tuple as [p.longitude, p.latitude, meta[1], meta[0]] per design.md section 6.5\'s exact snippet ([lng, lat, alt, ts_ms] order) - today coordOf only ever emits the 2-element [lng, lat] shape, with no meta-aware branch at all.');
      expect(src, contains('[p.longitude, p.latitude]'),
          reason: 'the legacy 2-element fallback shape must still be emitted when meta is null or absent, for backward compatibility with the offline/no-metadata caller.');
    });
  });
}
