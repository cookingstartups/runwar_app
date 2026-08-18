import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/database_service.dart';

/// Normalizes a city argument to the lowercase-slug form runs.city is
/// written with at run-start (run_recorder_provider.dart, sourced from
/// joinedCitySlugsProvider), independent of whatever casing the caller
/// passes (map_screen.dart passes the capitalized zones.city convention).
/// zones.city's own casing/query path is untouched.
String normalizeCityForRunsQuery(String city) => city.toLowerCase();

/// Applies stride decimation then a hard cap, exactly once, so every
/// consumer of userRunPointsProvider's output observes an identically-sized,
/// identically-composed list. gps_samples rows are already spacing-filtered
/// at write time to >=50m apart (run_recorder_service.dart), a materially
/// denser input than the old track_json's raw per-fix stream the original
/// stride-20 constant was calibrated against. Stride 4 over ~50m-spaced
/// input targets the canonical ~200m adjacent-point spacing (4 x 50m =
/// 200m). Legacy track_json-sourced points (already stride-20'd by
/// legacyPointsFromRunRows against their own, coarser raw-fix spacing) pass
/// through this same stride-4 pass again on the union - harmless: stride-4
/// over an already-sparse list only removes points, never adds density.
@visibleForTesting
const int kFogPointStride = 4;
@visibleForTesting
const int kFogPointCap = 200;

List<LatLng> decimateAndCapFogPoints(List<LatLng> points) {
  final strided = <LatLng>[
    for (var i = 0; i < points.length; i += kFogPointStride) points[i],
  ];
  return strided.length > kFogPointCap
      ? strided.sublist(0, kFogPointCap)
      : strided;
}

/// Pure row-parser: PostgREST gps_samples rows -> LatLng. Isolated so it is
/// directly testable with synthetic row fixtures, with no live/fake
/// Supabase client involved.
List<LatLng> pointsFromGpsSampleRows(List<Map<String, dynamic>> rows) {
  final out = <LatLng>[];
  for (final row in rows) {
    final lat = row['lat'] as num?;
    final lng = row['lng'] as num?;
    if (lat == null || lng == null) continue;
    out.add(LatLng(lat.toDouble(), lng.toDouble()));
  }
  return out;
}

/// Parses every pre-cutover run row's track_json (non-null, not "{}") via
/// the existing stride-20 legacy parser. Post-cutover rows (track_json ==
/// "{}" or null) contribute nothing here - their points come from
/// gps_samples instead. track_json remains read-only; no writer is revived.
List<LatLng> legacyPointsFromRunRows(List<Map<String, dynamic>> runRows) {
  final out = <LatLng>[];
  for (final row in runRows) {
    final json = row['track_json'] as String?;
    if (json == null || json == '{}') continue;
    final pts = _parseLineString(json);
    for (var i = 0; i < pts.length; i += 20) {
      out.add(pts[i]);
    }
    if (pts.isNotEmpty) out.add(pts.last);
  }
  return out;
}

/// Returns a flat list of LatLng points sampled from all of [userId]'s run
/// history in [city] (real and simulated, on equal terms). Used by the
/// fog-of-war layer to punch visibility holes along paths the player has
/// already run. Sourced from gps_samples (the live write path) unioned with
/// legacy track_json points for pre-cutover runs, then decimated/capped
/// exactly once.
final userRunPointsProvider =
    FutureProvider.family<List<LatLng>, ({String userId, String city})>(
        (ref, args) async {
  if (args.userId.isEmpty || args.city.isEmpty) return const [];
  final cityLower = normalizeCityForRunsQuery(args.city);

  final runRows = await DatabaseService.instance
      .getUserRunSessions(args.userId, cityLower);
  if (runRows.isEmpty) return const [];

  final sessionIds = runRows
      .map((r) => r['session_id'] as String?)
      .whereType<String>()
      .toList();

  final sampleRows = await DatabaseService.instance
      .getGpsSamplesForSessions(args.userId, sessionIds);

  final points = <LatLng>[
    ...pointsFromGpsSampleRows(sampleRows),
    ...legacyPointsFromRunRows(runRows),
  ];
  return decimateAndCapFogPoints(points);
});

List<LatLng> _parseLineString(String geojson) {
  try {
    final dynamic d = jsonDecode(geojson);
    if (d is! Map || d['type'] != 'LineString') return const [];
    final dynamic coords = d['coordinates'];
    if (coords is! List) return const [];
    final out = <LatLng>[];
    for (final pt in coords) {
      if (pt is! List || pt.length < 2) continue;
      out.add(LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()));
    }
    return out;
  } catch (_) {
    return const [];
  }
}
