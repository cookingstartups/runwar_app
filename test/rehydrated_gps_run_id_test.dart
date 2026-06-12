// test/rehydrated_gps_run_id_test.dart
//
// Source-inspection tests that verify the rehydrated GPS path in
// resumeFromScratch includes run_id in every payload passed to onGpsFix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = 'lib/services/run_recorder_service.dart';

  // ---------------------------------------------------------------------------
  // Locate the rehydrated GPS callback block (second gpsCb call site)
  // ---------------------------------------------------------------------------
  //
  // The file has two gpsCb({ call sites:
  //   1. The live path around line 193 — already correct since PR #45.
  //   2. The rehydrated path inside resumeFromScratch around line 462-470 —
  //      the defective path that omits run_id.
  //
  // Strategy: split the source on the first gpsCb({ occurrence and inspect
  // only the text after it (which contains the rehydrated block).

  group('rehydrated GPS payload includes run_id', () {
    late String src;
    late String rehydratedBlock;

    setUp(() {
      src = File(path).readAsStringSync();
      // Split on the FIRST gpsCb({ to isolate the rehydrated section.
      final firstIdx = src.indexOf('gpsCb({');
      expect(
        firstIdx,
        greaterThan(-1),
        reason: 'Expected at least one gpsCb({ call in $path.',
      );
      // Everything after the first occurrence contains the rehydrated block.
      final afterFirst = src.substring(firstIdx + 'gpsCb({'.length);
      final secondIdx = afterFirst.indexOf('gpsCb({');
      expect(
        secondIdx,
        greaterThan(-1),
        reason: 'Expected a second gpsCb({ call site (rehydrated path) in $path.',
      );
      // Capture from the second gpsCb({ up to its closing });
      final secondStart = firstIdx + 'gpsCb({'.length + secondIdx;
      final closingIdx = src.indexOf('});', secondStart);
      expect(
        closingIdx,
        greaterThan(-1),
        reason: 'Expected closing }); after the rehydrated gpsCb({ call.',
      );
      rehydratedBlock = src.substring(secondStart, closingIdx + 3);
    });

    test('rehydrated gpsCb call contains run_id key', () {
      expect(
        rehydratedBlock,
        contains("'run_id':"),
        reason:
            'The rehydrated GPS payload in $path must include '
            "'run_id': so gps_samples.run_id (NOT NULL) is satisfied "
            'and the replay does not raise Postgres error 23502.',
      );
    });

    test("run_id appears before session_id in the rehydrated payload", () {
      final runIdPos = rehydratedBlock.indexOf("'run_id':");
      final sessionIdPos = rehydratedBlock.indexOf("'session_id':");
      expect(
        runIdPos,
        greaterThan(-1),
        reason: "'run_id': must be present in the rehydrated block.",
      );
      expect(
        sessionIdPos,
        greaterThan(-1),
        reason: "'session_id': must be present in the rehydrated block.",
      );
      expect(
        runIdPos,
        lessThan(sessionIdPos),
        reason:
            "Per the spec field ordering, 'run_id' must appear before "
            "'session_id' in the rehydrated GPS payload map.",
      );
    });
  });
}
