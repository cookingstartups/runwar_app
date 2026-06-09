import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ── Cached tile provider ──────────────────────────────────────────────────────

/// TileProvider that resolves tiles through DefaultCacheManager.
/// Cache-first: if the tile is on disk, no network request is made.
/// If absent, CachedNetworkImageProvider downloads and writes it to cache.
class CachedNetworkTileProvider extends TileProvider {
  CachedNetworkTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: DefaultCacheManager(),
      headers: headers,
      errorListener: (e) => debugPrint('[TileCache] tile load failed: $e'),
    );
  }
}

// ── Tile cache service ────────────────────────────────────────────────────────

/// Pre-downloads CartoDB dark-matter tiles for a radius around the run start
/// point so the map is available when connectivity degrades mid-run.
///
/// The service is a singleton. Progress is emitted as a [Stream<double>]
/// in the range [0.0, 1.0]. Cancel the subscription to abort.
class TileCacheService {
  TileCacheService._();

  static final TileCacheService instance = TileCacheService._();

  // ── Public constants ──────────────────────────────────────────────────────

  /// Radius in kilometres of the area pre-downloaded around the run start.
  static const double kPrewarmRadiusKm = 7.0;

  /// Minimum zoom level included in the pre-download.
  static const int kPrewarmMinZoom = 14;

  /// Maximum zoom level included in the pre-download.
  static const int kPrewarmMaxZoom = 17;

  /// Parallel download workers used when connected via Wi-Fi.
  static const int kParallelThreadsWifi = 5;

  /// Parallel download workers used when connected via cellular.
  static const int kParallelThreadsCellular = 2;

  // ── Internal state ────────────────────────────────────────────────────────

  bool _inFlight = false;
  StreamController<double>? _activeController;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Pre-downloads CartoDB tiles for a [radiusKm] circle around [center]
  /// across [minZoom]..[maxZoom]. Emits progress in [0.0, 1.0].
  ///
  /// Re-entry is guarded -- a second call while one is active returns an empty
  /// stream that immediately closes.
  ///
  /// Cancel the returned subscription to abort all in-flight downloads.
  Stream<double> prewarmRunArea(
    LatLng center, {
    bool retina = false,
    double radiusKm = kPrewarmRadiusKm,
    int minZoom = kPrewarmMinZoom,
    int maxZoom = kPrewarmMaxZoom,
  }) {
    if (_inFlight) {
      return const Stream<double>.empty();
    }
    _inFlight = true;

    final controller = StreamController<double>();
    _activeController = controller;
    _run(controller, center, retina, radiusKm, minZoom, maxZoom);
    return controller.stream;
  }

  /// Cancels any in-flight pre-download by closing the active stream controller.
  /// The worker loop checks [StreamController.isClosed] and breaks on close.
  /// The caller should also cancel its own subscription.
  void cancelPrewarm() {
    _inFlight = false;
    _activeController?.close();
    _activeController = null;
  }

  // ── @visibleForTesting seams ──────────────────────────────────────────────

  /// Returns all tile (x, y, z) tuples covering a circle of [radiusKm] around
  /// [center] for zoom levels [minZoom]..[maxZoom].
  ///
  /// Uses bounding-box tile enumeration with standard Web Mercator XYZ formulas
  /// (OpenStreetMap wiki, Slippy_map_tilenames). The bounding box
  /// over-approximates the circle which is acceptable for pre-warming.
  @visibleForTesting
  static List<(int x, int y, int z)> tilesForCircle(
    LatLng center,
    double radiusKm,
    int minZoom,
    int maxZoom,
  ) {
    const earthRadiusKm = 6371.0;
    final latRad = center.latitude * math.pi / 180.0;
    final dLat = (radiusKm / earthRadiusKm) * (180.0 / math.pi);
    final dLng = dLat / math.cos(latRad);

    final minLat = center.latitude - dLat;
    final maxLat = center.latitude + dLat;
    final minLng = center.longitude - dLng;
    final maxLng = center.longitude + dLng;

    final result = <(int, int, int)>[];

    for (var z = minZoom; z <= maxZoom; z++) {
      final n = 1 << z; // 2^z

      int lonToTileX(double lon) {
        final wrapped = ((lon + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;
        final x = ((wrapped + 180.0) / 360.0 * n).floor();
        return x.clamp(0, n - 1);
      }

      int latToTileY(double lat) {
        final clamped = lat.clamp(-85.05112878, 85.05112878);
        final rad = clamped * math.pi / 180.0;
        final y = ((1.0 -
                    math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) /
                2.0 *
                n)
            .floor();
        return y.clamp(0, n - 1);
      }

      final x0 = lonToTileX(minLng);
      final x1 = lonToTileX(maxLng);
      // y0 corresponds to maxLat (north) because tile Y increases southward.
      final y0 = latToTileY(maxLat);
      final y1 = latToTileY(minLat);

      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          result.add((x, y, z));
        }
      }
    }

    return result;
  }

  /// Constructs the CartoDB dark_nolabels tile URL for the given coordinates.
  ///
  /// Always uses subdomain `a` so that pre-warm URLs are deterministic cache
  /// keys (the live TileLayer rotates subdomains, but the cached bytes are
  /// identical and the live layer will cache its own subdomain variant on first
  /// access).
  ///
  /// [retina] appends `@2x` before `.png` to match the HiDPI URL the TileLayer
  /// requests when [TileLayer.retinaMode] is true.
  @visibleForTesting
  static String buildTileUrl(int x, int y, int z, {bool retina = false}) {
    final retinaSuffix = retina ? '@2x' : '';
    return 'https://a.basemaps.cartocdn.com/dark_nolabels/$z/$x/$y$retinaSuffix.png';
  }

  // ── Private implementation ────────────────────────────────────────────────

  Future<void> _run(
    StreamController<double> controller,
    LatLng center,
    bool retina,
    double radiusKm,
    int minZoom,
    int maxZoom,
  ) async {
    try {
      // Determine concurrency based on connection type at run start.
      int concurrency;
      try {
        // connectivity_plus v6 returns List<ConnectivityResult>.
        final results = await Connectivity().checkConnectivity();
        concurrency = results.contains(ConnectivityResult.wifi)
            ? kParallelThreadsWifi
            : kParallelThreadsCellular;
      } catch (e) {
        debugPrint('[TileCache] connectivity check failed: $e');
        concurrency = kParallelThreadsCellular;
      }

      final tiles =
          tilesForCircle(center, radiusKm, minZoom, maxZoom);

      if (tiles.isEmpty) {
        await controller.close();
        return;
      }

      final manager = DefaultCacheManager();
      var done = 0;
      var failureCount = 0;
      final total = tiles.length;
      final iter = tiles.iterator;

      Future<void> worker() async {
        while (true) {
          if (controller.isClosed) return;
          (int, int, int)? next;
          if (iter.moveNext()) next = iter.current;
          if (next == null) return;
          final url = buildTileUrl(next.$1, next.$2, next.$3, retina: retina);
          try {
            await manager.downloadFile(url);
          } catch (e) {
            failureCount += 1;
            debugPrint('[TileCacheService] tile failed: $url ($e)');
          }
          done += 1;
          if (!controller.isClosed) {
            controller.add(done / total);
          }
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
      if (failureCount > 0 && failureCount / total > 0.2) {
        debugPrint('[TileCache] prewarm: $failureCount/$total tiles failed');
      }
    } finally {
      _inFlight = false;
      if (!controller.isClosed) await controller.close();
    }
  }
}
