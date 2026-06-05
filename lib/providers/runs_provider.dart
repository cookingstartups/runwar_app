import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/database_service.dart';

/// Returns a flat list of LatLng points sampled from all of [userId]'s run
/// tracks in [city].  Used by the fog-of-war layer to punch visibility holes
/// along paths the player has already run.
final userRunPointsProvider =
    FutureProvider.family<List<LatLng>, ({String userId, String city})>(
        (ref, args) async {
  if (args.userId.isEmpty || args.city.isEmpty) return const [];
  final rows = await DatabaseService.instance.getUserRuns(args.userId, args.city);
  final out = <LatLng>[];
  for (final row in rows) {
    final json = row['track_json'] as String?;
    if (json == null) continue;
    final pts = _parseLineString(json);
    // With 5 km radius holes, every 20th point is more than enough.
    for (var i = 0; i < pts.length; i += 20) {
      out.add(pts[i]);
    }
    if (pts.isNotEmpty) out.add(pts.last);
  }
  return out;
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
