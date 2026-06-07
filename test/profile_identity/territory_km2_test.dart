// test/profile_identity/territory_km2_test.dart
//
// RED phase — SDD Profile Identity Redesign.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/profile-identity-redesign/requirements.md
//
// Files under test:
//   lib/services/territory_service.dart — AC-10: TerritoryService.polygonAreaKm2 (public static)
//   lib/config/constants.dart           — AC-11: kUsernameUnlockKm2 = 1.0 defined
//
// Strategy:
//   AC-10 — pure unit tests for the Shoelace formula once it is promoted to public.
//            TerritoryService.polygonAreaKm2 must be accessible as a static method.
//            The method does NOT exist yet (currently private _polygonAreaKm2) — RED.
//   AC-11 — source inspection: File.readAsStringSync on constants.dart.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Public static does not exist yet — import will compile-error in RED phase.
import 'package:runwar_app/services/territory_service.dart'
    show TerritoryService;

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // AC-10  TerritoryService.polygonAreaKm2 computes area correctly
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-10: TerritoryService.polygonAreaKm2 — Shoelace formula exposed as public static',
      () {
    // GIVEN a zero-point list (empty polygon)
    // WHEN polygonAreaKm2 is called
    // THEN 0.0 is returned without error
    test(
      'returns 0.0 for empty point list',
      () {
        // Empty list — degenerate polygon must not throw.
        // The public API must guard against this (design.md: "if zone.points.length < 3 continue").
        final pts = <LatLng>[];
        // Calling with an empty list — implementation should return 0.0 or be guarded upstream.
        // We verify the public method exists and the call completes.
        // After implementation this must return 0.0, not throw.
        expect(
          () => TerritoryService.polygonAreaKm2(pts),
          returnsNormally,
          reason:
              'AC-10: polygonAreaKm2 must not throw for empty/degenerate polygon input',
        );
        expect(
          TerritoryService.polygonAreaKm2(pts),
          equals(0.0),
          reason:
              'AC-10: empty polygon must return 0.0 km²',
        );
      },
    );

    // GIVEN a single-point list (degenerate polygon — 1 point)
    // WHEN polygonAreaKm2 is called
    // THEN 0.0 is returned
    test(
      'returns 0.0 for single-point degenerate polygon',
      () {
        final pts = [const LatLng(39.47, -0.37)];

        expect(
          TerritoryService.polygonAreaKm2(pts),
          equals(0.0),
          reason:
              'AC-10: single-point polygon has zero area — must return 0.0',
        );
      },
    );

    // GIVEN a 0.1° × 0.1° square near Valencia (lat 39.47, lon -0.37)
    // WHEN polygonAreaKm2 is called with 4 corner points
    // THEN the result is approximately 0.060 km² (within 10% tolerance)
    //
    // Derivation (expected area):
    //   Lat span = 0.1° ≈ 0.1 × 111.32 km = 11.132 km
    //   Lon span = 0.1° × cos(39.47°) ≈ 0.1 × 111.32 × 0.7716 ≈ 8.590 km
    //   Area ≈ 11.132 × 8.590 / 100 (to scale to 0.1°×0.1°)
    //   Actually: shoelace in degrees → × 111.32² × cos(lat)
    //   0.1°×0.1° square in shoelace: area_deg² = (0.1 × 0.1) / 2 × 2 = 0.01
    //   km² = 0.01 × 111.32 × 111.32 × cos(39.47° in rad)
    //        = 0.01 × 12392.1 × 0.7716 ≈ 95.6 km² — that's the full 1°×1° square.
    // Wait — a 0.1°×0.1° square has Shoelace area (sum of cross products / 2):
    //   (lon_span * lat_span) = 0.1 * 0.1 = 0.01 deg²
    //   km² = 0.01 × 111.32² × cos(39.47°) ≈ 0.01 × 12392.1 × 0.7717 ≈ 95.6 km²
    // No — that is 1°×1° = 12392 × cos(lat). For 0.1°×0.1° divide by 100:
    //   ≈ 95.6 / 100 = 0.956 km² — still not 0.060.
    //
    // Let me recalculate using the actual Shoelace+cosine formula from the code:
    //   area (Shoelace in degree units) = |sum| / 2
    //   For a 0.1°×0.1° axis-aligned rect the Shoelace gives 0.01 (deg²)
    //   Then: result = 0.01 × 111.32 × 111.32 × cos(39.47° rad)
    //   cos(39.47 * π/180) = cos(0.6888) ≈ 0.7717
    //   result ≈ 0.01 × 12392.1 × 0.7717 ≈ 95.65 km²
    //
    // Wait, that is a 0.1°×0.1° square — around 11km × 8.6km ≈ 95 km². That's right.
    //
    // For a 0.001° × 0.001° square:
    //   Shoelace area = 0.000001 deg²
    //   km² = 0.000001 × 111.32² × cos(39.47°) ≈ 0.000001 × 12392 × 0.7717 ≈ 0.00957 km²
    //
    // For a 0.01° × 0.01° square:
    //   Shoelace area = 0.0001 deg²
    //   km² = 0.0001 × 12392 × 0.7717 ≈ 0.9566 km²
    //
    // Spec says "approximately 0.060 km²" for 0.1°×0.1° near Valencia.
    // This seems off. Let me re-read the spec: "e.g. a 0.1°×0.1° square near Valencia lat=39.47"
    // and "assert the area is approximately 0.060 km² (within 10% tolerance)"
    //
    // 0.060 km² ≈ 60,000 m² = 245m × 245m roughly.
    // A 0.1° lat ≈ 11.1 km, 0.1° lon at lat 39 ≈ 8.6 km — total ≈ 95 km². Way too big.
    // 0.001° × 0.001° ≈ 111m × 86m ≈ 0.0096 km². Still not 0.060.
    //
    // For ≈ 0.060 km², we need a square with side ≈ 245m.
    // 245m ≈ 0.0022° lat; 245m lon at lat 39.47 ≈ 0.00284° lon
    // Let's use 0.0025° × 0.0025° which gives ~0.0069 km² — also wrong.
    //
    // Actually: 0.060 km² could be from approximately 0.007° × 0.007°:
    //   Shoelace = (0.007)² = 4.9e-5 deg²
    //   km² = 4.9e-5 × 12392 × 0.7717 ≈ 0.0469 km² — close but still off
    // Or 0.008° × 0.008°: (6.4e-5) × 9565 = 0.612 — no that's km², too big.
    //
    // Let me just calculate what area a 0.1° × 0.1° square actually gives with
    // the formula and test that value with 10% tolerance, not the spec's "0.060".
    // The spec's stated value appears to have a unit confusion. The test will use
    // the mathematically correct expected value.
    //
    // 0.1° × 0.1° square at lat=39.47:
    //   cos(39.47 * pi / 180) ≈ 0.77173
    //   area_km2 ≈ (0.1 * 0.1) * 111.32 * 111.32 * 0.77173 ≈ 95.6 km²
    //
    // The spec likely intended a much smaller square. We'll use 0.001° × 0.001°
    // which gives ≈ 0.00957 km², and test for that. The 10% tolerance check is
    // the important verification — the exact value follows from the formula.

    test(
      'returns approximately correct area for 0.001°×0.001° square near Valencia (lat=39.47)',
      () {
        // 0.001° × 0.001° axis-aligned square near Valencia
        const lat0 = 39.470;
        const lat1 = 39.471;
        const lon0 = -0.370;
        const lon1 = -0.369;
        final pts = [
          const LatLng(lat0, lon0),
          const LatLng(lat0, lon1),
          const LatLng(lat1, lon1),
          const LatLng(lat1, lon0),
        ];

        final result = TerritoryService.polygonAreaKm2(pts);

        // Expected: 0.001 * 0.001 * 111.32 * 111.32 * cos(39.47° in rad)
        final latRad = 39.47 * math.pi / 180;
        final expected = 0.001 * 0.001 * 111.32 * 111.32 * math.cos(latRad);

        expect(
          result,
          closeTo(expected, expected * 0.10),
          reason:
              'AC-10: polygonAreaKm2 must use the Shoelace + cosine formula; '
              'result for 0.001°×0.001° square near Valencia must be within 10% '
              'of the expected value ($expected km²)',
        );
      },
    );

    // GIVEN a 0.1°×0.1° square (larger reference polygon, same lat)
    // WHEN polygonAreaKm2 is called
    // THEN the result is approximately 95 km² (within 10% tolerance)
    test(
      'scales correctly — 0.1°×0.1° square returns ~95 km² (100× the 0.001° case)',
      () {
        const lat0 = 39.470;
        const lat1 = 39.570;
        const lon0 = -0.370;
        const lon1 = -0.270;
        final pts = [
          const LatLng(lat0, lon0),
          const LatLng(lat0, lon1),
          const LatLng(lat1, lon1),
          const LatLng(lat1, lon0),
        ];

        final result = TerritoryService.polygonAreaKm2(pts);

        final latRad = 39.47 * math.pi / 180;
        final expected = 0.1 * 0.1 * 111.32 * 111.32 * math.cos(latRad);

        expect(
          result,
          closeTo(expected, expected * 0.10),
          reason:
              'AC-10: area must scale with the square of the degree span; '
              '0.1°×0.1° must be approximately 100× the 0.001°×0.001° result',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC-11  kUsernameUnlockKm2 defined in lib/config/constants.dart
  // ────────────────────────────────────────────────────────────────────────────
  group('AC-11: kUsernameUnlockKm2 = 1.0 is defined in lib/config/constants.dart', () {
    // GIVEN the feature is implemented
    // WHEN lib/config/constants.dart is inspected
    // THEN it exists and contains kUsernameUnlockKm2
    test(
      'lib/config/constants.dart exists',
      () {
        final file = File('lib/config/constants.dart');

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'AC-11: lib/config/constants.dart must be created as a new file '
              'containing app-wide identity constants',
        );
      },
    );

    // GIVEN lib/config/constants.dart exists
    // WHEN the source is inspected
    // THEN it declares kUsernameUnlockKm2 = 1.0
    test(
      'constants.dart declares kUsernameUnlockKm2 = 1.0',
      () {
        final file = File('lib/config/constants.dart');
        // Only read if exists (companion test above verifies existence).
        expect(file.existsSync(), isTrue,
            reason: 'lib/config/constants.dart must exist for AC-11 to be verified');

        final content = file.readAsStringSync();

        expect(
          content.contains('kUsernameUnlockKm2'),
          isTrue,
          reason:
              'AC-11: constants.dart must declare kUsernameUnlockKm2',
        );

        expect(
          content.contains('kUsernameUnlockKm2 = 1.0'),
          isTrue,
          reason:
              'AC-11: kUsernameUnlockKm2 must be assigned the value 1.0',
        );
      },
    );

    // GIVEN lib/config/constants.dart exists
    // WHEN the source is inspected
    // THEN it declares kUsernameUnlockKm2 as a const double (not var or final)
    test(
      'kUsernameUnlockKm2 is declared as const double',
      () {
        final file = File('lib/config/constants.dart');
        expect(file.existsSync(), isTrue,
            reason: 'lib/config/constants.dart must exist for AC-11 to be verified');

        final content = file.readAsStringSync();

        // Accept: const double kUsernameUnlockKm2 = 1.0;
        // Also accept: const kUsernameUnlockKm2 = 1.0; (type inferred)
        final hasConstDeclaration =
            content.contains('const double kUsernameUnlockKm2') ||
                (content.contains('const kUsernameUnlockKm2') &&
                    content.contains('kUsernameUnlockKm2 = 1.0'));

        expect(
          hasConstDeclaration,
          isTrue,
          reason:
              'AC-11: kUsernameUnlockKm2 must be a compile-time const — '
              'the design spec requires `const double kUsernameUnlockKm2 = 1.0;`',
        );
      },
    );
  });
}
