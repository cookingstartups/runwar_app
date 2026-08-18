// test/providers/runs_provider_test.dart
//
// RED phase: asserts the reworked userRunPointsProvider pipeline sources
// historical fog-reveal points from gps_samples (not the dead track_json
// writer), normalizes city casing, ignores is_simulated, unions legacy
// track_json points for pre-cutover runs, and applies decimation/cap exactly
// once via a single shared function.
//
// Pure-function tests only, no Supabase, no widget pump - matching the
// house precedent that Supabase-backed layers have no live-client test seam
// (test/services/database/zones_repository_test.dart's own stated rationale).
//
// RED status expected: every function under test here does not exist yet on
// unfixed code (runs_provider.dart only defines _parseLineString and the old
// track_json-only userRunPointsProvider body), so these fail to compile -
// "Target of URI doesn't exist" / undefined-name errors are the expected RED
// shape, matching zones_repository_test.dart's own documented precedent.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/providers/runs_provider.dart';

void main() {
  group('normalizeCityForRunsQuery', () {
    // GIVEN a capitalized city string (the zones.city query convention)
    // WHEN normalizeCityForRunsQuery is called
    // THEN it returns the lowercase-slug form runs.city is written with
    test('lowercases a capitalized city input', () {
      expect(normalizeCityForRunsQuery('Valencia'), equals('valencia'));
    });

    test('leaves an already-lowercase city input unchanged', () {
      expect(normalizeCityForRunsQuery('valencia'), equals('valencia'));
    });
  });

  group('pointsFromGpsSampleRows', () {
    // GIVEN synthetic gps_samples rows with lat/lng
    // WHEN pointsFromGpsSampleRows parses them
    // THEN it yields one LatLng per row with lat/lng populated
    test('yields points from rows with populated lat/lng', () {
      final rows = [
        {'lat': 39.4699, 'lng': -0.3763},
        {'lat': 39.4712, 'lng': -0.3701},
      ];

      final points = pointsFromGpsSampleRows(rows);

      expect(points.length, equals(2));
      expect(points[0], equals(const LatLng(39.4699, -0.3763)));
      expect(points[1], equals(const LatLng(39.4712, -0.3701)));
    });

    test('skips rows with a null lat or lng', () {
      final rows = [
        {'lat': 39.4699, 'lng': -0.3763},
        {'lat': null, 'lng': -0.3701},
        {'lat': 39.4712, 'lng': null},
      ];

      final points = pointsFromGpsSampleRows(rows);

      expect(points.length, equals(1));
    });

    test('returns an empty list for empty input', () {
      expect(pointsFromGpsSampleRows(const []), isEmpty);
    });
  });

  group('legacyPointsFromRunRows (AC-E6)', () {
    String geojsonLine(List<List<double>> coords) {
      final coordStr =
          coords.map((c) => '[${c[0]}, ${c[1]}]').join(', ');
      return '{"type":"LineString","coordinates":[$coordStr]}';
    }

    // GIVEN a run row with populated (pre-cutover) track_json
    // WHEN legacyPointsFromRunRows parses it
    // THEN it returns the parsed LineString points
    test('parses points from a row with populated track_json', () {
      final rows = [
        {
          'track_json': geojsonLine([
            [-0.3763, 39.4699],
            [-0.3701, 39.4712],
          ]),
        },
      ];

      final points = legacyPointsFromRunRows(rows);

      expect(points, isNotEmpty);
    });

    // GIVEN a run row whose track_json is "{}" (post-cutover, dead writer)
    // WHEN legacyPointsFromRunRows parses it
    // THEN it contributes no points
    test('contributes no points for a row with track_json == "{}"', () {
      final rows = [
        {'track_json': '{}'},
      ];

      expect(legacyPointsFromRunRows(rows), isEmpty);
    });

    // GIVEN one pre-cutover row (populated track_json) and one post-cutover
    // row (track_json == "{}")
    // WHEN legacyPointsFromRunRows parses the mixed fixture
    // THEN only the pre-cutover row's points are returned
    test('mixed pre/post-cutover fixture returns points from the pre-cutover row only', () {
      final rows = [
        {
          'track_json': geojsonLine([
            [-0.3763, 39.4699],
            [-0.3701, 39.4712],
          ]),
        },
        {'track_json': '{}'},
      ];

      final points = legacyPointsFromRunRows(rows);

      expect(points, isNotEmpty);
      // Only one row contributed - the pre-cutover coords above, not a
      // second copy from the "{}" row (which would double the count if the
      // post-cutover guard were missing).
      final singleRowPoints =
          legacyPointsFromRunRows([rows.first]);
      expect(points.length, equals(singleRowPoints.length));
    });
  });

  group('AC-E3: is_simulated does not gate fog-reveal inclusion', () {
    // Source-inspection: getUserRunSessions' query body must not filter on
    // is_simulated in an .eq(/.neq( call, even though it selects the column
    // as a passthrough.
    test('getUserRunSessions query body contains no is_simulated filter predicate', () {
      final src = _readSource('lib/services/database_service.dart');
      final body = _sliceMethodBody(src, 'getUserRunSessions');
      expect(body, isNot(contains(RegExp(r"\.(eq|neq)\('is_simulated'"))),
          reason: 'is_simulated must remain a passthrough-selected column only - '
              'filtering on it would silently exclude simulated runs\' gps_samples '
              'from historical fog reveal (AC-E3)');
    });
  });

  group('decimateAndCapFogPoints (AC-E4)', () {
    // GIVEN 900 raw points
    // WHEN decimateAndCapFogPoints is applied
    // THEN the output is bounded to <= 200 and reflects stride decimation
    test('bounds a 900-point input to the shared cap', () {
      final input = List<LatLng>.generate(
          900, (i) => LatLng(39.0 + i * 0.0001, -0.3 + i * 0.0001));

      final out = decimateAndCapFogPoints(input);

      expect(out.length, lessThanOrEqualTo(200));
      expect(out.length, greaterThan(0));
    });

    test('a small input under the cap is only strided, not truncated below its strided length', () {
      final input = List<LatLng>.generate(
          8, (i) => LatLng(39.0 + i * 0.0001, -0.3 + i * 0.0001));

      final out = decimateAndCapFogPoints(input);

      expect(out.length, lessThanOrEqualTo(input.length));
      expect(out.length, greaterThan(0));
    });
  });
}

String _readSource(String relativePath) {
  return File(relativePath).readAsStringSync();
}

String _sliceMethodBody(String src, String methodName) {
  final start = src.indexOf(methodName);
  if (start < 0) {
    fail('Landmark not found: "$methodName" in database_service.dart - '
        'method does not exist yet (expected RED today)');
  }
  final closeBraceSearchStart = src.indexOf('{', start);
  // Find the matching closing brace by simple depth counting from the first
  // '{' after the method signature.
  var depth = 0;
  var i = closeBraceSearchStart;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(start, i + 1);
}
