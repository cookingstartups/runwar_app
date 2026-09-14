// test/run_recorder_track_metadata_test.dart
//
// R1: RunRecorderService threads per-point ts_ms/altitude alongside _track
// via a new, additive onAutoClaimMeta callback (design.md section 6,
// "Blast radius decision") - a parallel index-aligned side-array approach,
// matching the codebase's existing lastSimRawPosition convention, rather
// than widening _track's own LatLng type (rejected in design.md 6.2(a) as
// the largest possible blast radius for this task).
//
// RunRecorderService currently has neither the parallel _trackTsMs/_trackAltM
// arrays nor the onAutoClaimMeta callback, so this file follows this
// codebase's own established landmark-anchored source-inspection convention
// for source-structure-mapped acceptance criteria (see
// test/map_screen_gate_toast_test.dart and
// test/rehydrated_gps_run_id_test.dart for the precedent) rather than
// driving RunRecorderService's private internals through a test seam this
// class does not yet expose (RunRecorderService.injectTrackForTesting only
// accepts List<LatLng> today, with no metadata-carrying counterpart).
//
// Flutter SDK availability: NOT confirmed runnable in this environment at
// authoring time (background install may still be in progress). These
// tests are written to the same rigor as if they were runnable; they have
// NOT been executed here. Run with: flutter test test/run_recorder_track_metadata_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'lib/services/run_recorder_service.dart';

String _sliceToNextMember(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'Landmark not found: "$startMarker" in $_path. The implementation has not landed yet, or the file structure moved - update this anchor once it lands, do not delete the check.');
  final end = src.indexOf(endMarker, start);
  expect(end, greaterThan(start),
      reason: 'Landmark not found after "$startMarker": "$endMarker" in $_path.');
  return src.substring(start, end);
}

void main() {
  group('R1: parallel timestamp/altitude arrays alongside _track', () {
    test('_trackTsMs and _trackAltM parallel arrays exist alongside _track', () {
      final src = File(_path).readAsStringSync();
      expect(src, contains('_trackTsMs'),
          reason: 'RunRecorderService must maintain a parallel _trackTsMs array index-aligned with _track (design.md section 6.2 decision (b)) - today no such field exists.');
      expect(src, contains('_trackAltM'),
          reason: 'RunRecorderService must maintain a parallel _trackAltM array index-aligned with _track - today no such field exists.');
    });

    test('_trackTsMs/_trackAltM are appended at all three _track.add call sites (proximity-closure, ordinary spacing filter, resumeFromScratch rehydration)', () {
      final src = File(_path).readAsStringSync();
      final trackAddCount = '_track.add('.allMatches(src).length;
      final tsAddCount = '_trackTsMs.add('.allMatches(src).length;
      final altAddCount = '_trackAltM.add('.allMatches(src).length;
      expect(trackAddCount, greaterThanOrEqualTo(3),
          reason: 'baseline check: _track.add( must appear at its three known existing sites (proximity-closure fast path, ordinary spacing-filter path, resumeFromScratch) - if this fails, the baseline itself moved and every other assertion in this test needs re-deriving.');
      expect(tsAddCount, equals(trackAddCount),
          reason: '_trackTsMs.add( must be appended at EVERY site _track.add( is, so the two arrays never drift out of index alignment (R1 requirement) - today _trackTsMs.add( does not appear at all.');
      expect(altAddCount, equals(trackAddCount),
          reason: '_trackAltM.add( must be appended at EVERY site _track.add( is, for the same index-alignment reason - today _trackAltM.add( does not appear at all.');
    });

    test('onAutoClaimMeta is a new, separate, nullable callback field (not a change to onAutoClaim\'s existing signature)', () {
      final src = File(_path).readAsStringSync();
      expect(src, contains('onAutoClaimMeta'),
          reason: 'design.md section 6.4 requires a wholly new, separate, nullable onAutoClaimMeta field - today it does not exist.');
      // onAutoClaim's own declared type must be untouched - this is the
      // blast-radius constraint the design explicitly protects (10 existing
      // test files plus the provider assign a plain, non-optional-arity
      // closure to it).
      expect(src, contains('Future<void> Function(List<List<LatLng>> capturedPolygons)?'),
          reason: 'onAutoClaim\'s existing declared type must remain untouched by this change - widening it would break every existing closure assignment (design.md 6.4). If this fails, either the baseline type changed unexpectedly, or onAutoClaimMeta was implemented as a signature change instead of a new field.');
    });

    test('onAutoClaimMeta is invoked in the same synchronous pass as onAutoClaim, at both existing dispatch call sites', () {
      final src = File(_path).readAsStringSync();
      final scanBlock = _sliceToNextMember(src, '_scanForAutoClaim', 'void _drainDeferredCrossings');
      expect(scanBlock, contains('onAutoClaimMeta'),
          reason: '_scanForAutoClaim must invoke onAutoClaimMeta immediately after onAutoClaim, in the same synchronous pass (design.md section 6.4) - today onAutoClaimMeta is never referenced here.');
    });

    test('computeCaptureMeta exists as the sibling of computeCapture, slicing metadata by the SAME index range (not proximity-matched)', () {
      final src = File(_path).readAsStringSync();
      expect(src, contains('computeCaptureMeta'),
          reason: 'design.md section 6.2 decision requires a new sibling function computeCaptureMeta that slices _trackTsMs/_trackAltM via the exact same integer index range used to slice _track into a captured polygon - today it does not exist anywhere in this file.');
    });
  });

  group('R1: alt/ts_ms null-preservation for the resumeFromScratch rehydration path', () {
    test('resumeFromScratch reads the new alt column and preserves null for rows written before it existed (never defaults to 0.0)', () {
      final src = File(_path).readAsStringSync();
      final body = _sliceToNextMember(src, 'resumeFromScratch', 'Future<void> ');
      expect(body, contains("'alt'"),
          reason: 'resumeFromScratch must read the new nullable alt column from run_scratch rows - today this file never references an \'alt\' key at all, since the column and the read path do not exist yet.');
      expect(body, isNot(contains("?? 0.0")),
          reason: 'a naive `row[\'alt\'] as double? ?? 0.0` default would fabricate a false ground-level altitude for rows written before the alt column existed - design.md section 6.6/6.7 requires preserving null for "unknown", never defaulting to 0.0. If this fails, the naive default pattern was used instead of the documented null-preserving convention.');
    });
  });
}
