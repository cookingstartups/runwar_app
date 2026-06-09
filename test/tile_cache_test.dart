
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:runwar_app/services/tile_cache_service.dart';

// ---------------------------------------------------------------------------
// Tile Cache Service - pure unit tests
//
// All tests exercise @visibleForTesting seams on TileCacheService.
// These are pure-Dart tests: no Flutter binding, no network, no cache manager.
//
// Every test below will fail to compile until
// lib/services/tile_cache_service.dart is created with the expected symbols.
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Group 1: Service constants have correct values
  // =========================================================================

  group('tile cache service constants have correct values', () {
    // GIVEN the TileCacheService is compiled
    // WHEN the prewarm radius constant is read
    // THEN it equals 7.0 km
    test('prewarm radius constant is 7.0 km', () {
      expect(TileCacheService.kPrewarmRadiusKm, equals(7.0));
    });

    // GIVEN the TileCacheService is compiled
    // WHEN the minimum zoom constant is read
    // THEN it equals 14
    test('prewarm minimum zoom constant is 14', () {
      expect(TileCacheService.kPrewarmMinZoom, equals(14));
    });

    // GIVEN the TileCacheService is compiled
    // WHEN the maximum zoom constant is read
    // THEN it equals 17
    test('prewarm maximum zoom constant is 17', () {
      expect(TileCacheService.kPrewarmMaxZoom, equals(17));
    });

    // GIVEN the TileCacheService is compiled
    // WHEN the Wi-Fi concurrency constant is read
    // THEN it equals 5
    test('wifi parallel threads constant is 5', () {
      expect(TileCacheService.kParallelThreadsWifi, equals(5));
    });

    // GIVEN the TileCacheService is compiled
    // WHEN the cellular concurrency constant is read
    // THEN it equals 2
    test('cellular parallel threads constant is 2', () {
      expect(TileCacheService.kParallelThreadsCellular, equals(2));
    });
  });

  // =========================================================================
  // Group 2: tilesForCircle - basic coverage
  // =========================================================================

  group('tilesForCircle returns tiles for a known city center', () {
    // GIVEN a center point in Valencia, Spain at lat 39.47, lng -0.37
    //   AND a 7 km radius, zoom 14-17
    // WHEN tilesForCircle is called
    // THEN the result is non-empty
    test('returns non-empty list for Valencia center at default zoom range', () {
      const valencia = LatLng(39.47, -0.37);
      final tiles = TileCacheService.tilesForCircle(
        valencia,
        TileCacheService.kPrewarmRadiusKm,
        TileCacheService.kPrewarmMinZoom,
        TileCacheService.kPrewarmMaxZoom,
      );

      expect(tiles, isNotEmpty,
          reason: 'A 7 km radius around Valencia must yield at least one tile');
    });

    // GIVEN a center point in Valencia at lat 39.47, lng -0.37
    //   AND a 7 km radius, zoom 14-17
    // WHEN tilesForCircle is called
    // THEN the tile count falls in the plausible range per the design estimate
    //   (design doc: ~2800 tiles; allow 1000-5000 for the bounding-box approximation)
    test('tile count for Valencia 7 km radius is in the plausible range', () {
      const valencia = LatLng(39.47, -0.37);
      final tiles = TileCacheService.tilesForCircle(
        valencia,
        TileCacheService.kPrewarmRadiusKm,
        TileCacheService.kPrewarmMinZoom,
        TileCacheService.kPrewarmMaxZoom,
      );

      expect(tiles.length, inInclusiveRange(1000, 5000),
          reason: 'Expected roughly 2800 tiles for 7 km radius at zoom 14-17');
    });
  });

  // =========================================================================
  // Group 3: tilesForCircle - center containment at zoom 14
  // =========================================================================

  group('tilesForCircle zoom-14 result contains the center tile', () {
    // GIVEN a center point in Valencia, Spain at lat 39.47, lng -0.37
    //   AND zoom range restricted to 14-14
    // WHEN tilesForCircle is called
    // THEN every tile in the result has z == 14
    //   AND the tile computed from the slippy-map formula for the center
    //       coordinate appears in the result
    test('the tile containing Valencia center appears in the zoom-14 result', () {
      const lat = 39.47;
      const lng = -0.37;
      const z = 14;
      const n = 1 << z; // 16384

      // Standard slippy-map / Web Mercator formulas (same as production).
      final expectedX = ((lng + 180.0) / 360.0 * n).floor();
      final latRad = lat * math.pi / 180.0;
      final expectedY =
          ((1.0 -
                      math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) /
                          math.pi) /
                  2.0 *
                  n)
              .floor();

      const valencia = LatLng(lat, lng);
      final tiles = TileCacheService.tilesForCircle(valencia, 7.0, z, z);

      expect(tiles, isNotEmpty,
          reason: 'tilesForCircle with zoom 14-14 must not return empty');

      final allZoom14 = tiles.every((t) => t.$3 == z);
      expect(allZoom14, isTrue,
          reason: 'All tiles must have z == 14 when minZoom == maxZoom == 14');

      final containsCenter =
          tiles.any((t) => t.$1 == expectedX && t.$2 == expectedY);
      expect(containsCenter, isTrue,
          reason: 'The tile at ($expectedX, $expectedY, $z) must be in the result');
    });
  });

  // =========================================================================
  // Group 4: buildTileUrl - non-retina URL format
  // =========================================================================

  group('buildTileUrl constructs correct CartoDB dark_nolabels URLs', () {
    // GIVEN tile coordinates x=10, y=10, z=14 and retina=false
    // WHEN buildTileUrl is called
    // THEN the URL is the exact CartoDB non-retina URL with subdomain a
    test('non-retina URL matches expected CartoDB template', () {
      final url = TileCacheService.buildTileUrl(10, 10, 14, retina: false);
      expect(
        url,
        equals('https://a.basemaps.cartocdn.com/dark_nolabels/14/10/10.png'),
        reason: 'Non-retina URL must not contain @2x',
      );
    });

    // GIVEN tile coordinates x=10, y=10, z=14 and retina=true
    // WHEN buildTileUrl is called
    // THEN the URL contains @2x immediately before .png
    test('retina URL inserts @2x before .png suffix', () {
      final url = TileCacheService.buildTileUrl(10, 10, 14, retina: true);
      expect(
        url,
        equals('https://a.basemaps.cartocdn.com/dark_nolabels/14/10/10@2x.png'),
        reason: 'Retina URL must contain @2x to match TileLayer HiDPI requests',
      );
    });

    // GIVEN tile coordinates x=0, y=0, z=0 with retina=false
    // WHEN buildTileUrl is called
    // THEN the URL path segment is /0/0/0.png in z/x/y order
    test('URL path encodes z, x, y in correct order for zoom-0 root tile', () {
      final url = TileCacheService.buildTileUrl(0, 0, 0, retina: false);
      expect(url, contains('/0/0/0.png'),
          reason: 'Path segment must be /{z}/{x}/{y}.png');
      expect(url, startsWith('https://a.basemaps.cartocdn.com/dark_nolabels/'),
          reason: 'URL must use subdomain a and the dark_nolabels layer');
    });
  });

  // =========================================================================
  // Group 5: buildTileUrl - subdomain is always 'a'
  // =========================================================================

  group('buildTileUrl always uses subdomain a for cache-key determinism', () {
    // GIVEN arbitrary valid tile coordinates called multiple times
    // WHEN buildTileUrl is called
    // THEN every returned URL starts with https://a.basemaps.cartocdn.com/
    //   (subdomain is not cycled; pre-warm always uses a)
    test('subdomain is a for every coordinate combination', () {
      final urls = [
        TileCacheService.buildTileUrl(0, 0, 14),
        TileCacheService.buildTileUrl(100, 200, 15),
        TileCacheService.buildTileUrl(999, 1, 17),
        TileCacheService.buildTileUrl(8192, 8192, 14),
      ];

      for (final url in urls) {
        expect(url, startsWith('https://a.basemaps.cartocdn.com/'),
            reason: 'All pre-warm URLs must use subdomain a, got: $url');
      }
    });
  });
}
