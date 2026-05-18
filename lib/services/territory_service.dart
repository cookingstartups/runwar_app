import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'database_service.dart';
import 'zones_service.dart';

enum TerritoryResult { claimed, conquered, disputed, failed }

class ClaimOutcome {
  const ClaimOutcome(this.result, this.affectedZoneId);
  final TerritoryResult result;
  final String? affectedZoneId;
}

class TerritoryService {
  TerritoryService._();
  static final TerritoryService instance = TerritoryService._();

  Future<ClaimOutcome> evaluateClaim(
    String userId,
    String city,
    List<LatLng> track,
  ) async {
    if (track.length < 3) {
      return const ClaimOutcome(TerritoryResult.failed, null);
    }

    final rivals = await ZonesService.instance.fetchZonesByCity(city);
    final newBBox = _bbox(track);
    final conqueredIds = <String>[];
    final disputedIds = <String>[];

    for (final r in rivals) {
      final rivalOwnerId = r['owner_id'] as String?;
      if (rivalOwnerId == null || rivalOwnerId == userId) continue;

      final geom = r['geom_json'];
      if (geom is! String) continue;
      final rivalPoints = _parseRing(geom);
      if (rivalPoints == null || rivalPoints.length < 3) continue;

      final rivalBBox = _bbox(rivalPoints);
      if (!_bboxesIntersect(newBBox, rivalBBox)) continue;

      // Full-containment test — conquest priority
      var allInside = true;
      for (final v in rivalPoints) {
        if (!_pointInRing(v, track)) {
          allInside = false;
          break;
        }
      }
      if (allInside) {
        conqueredIds.add(r['id'] as String);
        continue;
      }

      // Partial overlap test — vertex-exchange
      var anyOverlap = false;
      for (final v in rivalPoints) {
        if (_pointInRing(v, track)) {
          anyOverlap = true;
          break;
        }
      }
      if (!anyOverlap) {
        for (final v in track) {
          if (_pointInRing(v, rivalPoints)) {
            anyOverlap = true;
            break;
          }
        }
      }
      if (anyOverlap) {
        disputedIds.add(r['id'] as String);
      }
    }

    final db = DatabaseService.instance.db;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    return db.transaction<ClaimOutcome>((txn) async {
      for (final id in conqueredIds) {
        await txn.update(
          'zones',
          {
            'owner_id': userId,
            'influence': 1,
            'status': 'owned',
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      for (final id in disputedIds) {
        await txn.update(
          'zones',
          {'status': 'disputed', 'updated_at': nowIso},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (conqueredIds.isEmpty && disputedIds.isEmpty) {
        final newId = _uuidV4();
        await txn.insert('zones', {
          'id': newId,
          'owner_id': userId,
          'city': city,
          'geom_json': _encodePolygon(track),
          'influence': 1,
          'status': 'owned',
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        return ClaimOutcome(TerritoryResult.claimed, newId);
      }
      if (conqueredIds.isNotEmpty) {
        return ClaimOutcome(TerritoryResult.conquered, conqueredIds.first);
      }
      return ClaimOutcome(TerritoryResult.disputed, disputedIds.first);
    });
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static String _encodePolygon(List<LatLng> ring) {
    final closed =
        (ring.isNotEmpty && ring.first == ring.last) ? ring : [...ring, ring.first];
    return jsonEncode({
      'type': 'Polygon',
      'coordinates': [
        closed.map((p) => [p.longitude, p.latitude]).toList(),
      ],
    });
  }

  static List<LatLng>? _parseRing(String geomJson) {
    try {
      final d = jsonDecode(geomJson);
      if (d is! Map) return null;
      if (d['type'] != 'Polygon') return null;
      final coords = d['coordinates'];
      if (coords is! List || coords.isEmpty) return null;
      final ring = coords[0];
      if (ring is! List || ring.length < 3) return null;
      final out = <LatLng>[];
      for (final pt in ring) {
        if (pt is! List || pt.length < 2) return null;
        out.add(LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  static ({double minLat, double maxLat, double minLng, double maxLng}) _bbox(
      List<LatLng> pts) {
    var nLat = pts.first.latitude, xLat = pts.first.latitude;
    var nLng = pts.first.longitude, xLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < nLat) nLat = p.latitude;
      if (p.latitude > xLat) xLat = p.latitude;
      if (p.longitude < nLng) nLng = p.longitude;
      if (p.longitude > xLng) xLng = p.longitude;
    }
    return (minLat: nLat, maxLat: xLat, minLng: nLng, maxLng: xLng);
  }

  static bool _bboxesIntersect(
    ({double minLat, double maxLat, double minLng, double maxLng}) a,
    ({double minLat, double maxLat, double minLng, double maxLng}) b,
  ) {
    if (a.maxLat < b.minLat || a.minLat > b.maxLat) return false;
    if (a.maxLng < b.minLng || a.minLng > b.maxLng) return false;
    return true;
  }

  static bool _pointInRing(LatLng p, List<LatLng> ring) {
    var inside = false;
    final n = ring.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = ring[i].longitude, yi = ring[i].latitude;
      final xj = ring[j].longitude, yj = ring[j].latitude;
      final dy = yj - yi;
      final denom = dy == 0 ? 1e-12 : dy;
      final intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / denom + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static final math.Random _rng = math.Random.secure();

  static String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
