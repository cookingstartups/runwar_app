import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'database_service.dart';
import 'zones_service.dart';
import 'supabase_service.dart';
import 'telemetry_service.dart';
import '../config/supabase_config.dart';

enum TerritoryResult { claimed, conquered, disputed, failed }

class ClaimOutcome {
  const ClaimOutcome(this.result, this.affectedZoneId,
      {this.disputeResolved = false});
  final TerritoryResult result;
  final String? affectedZoneId;

  /// True when this claim resolved an existing open dispute (conquered path).
  /// Parsed from claim_territory Edge fn response field `dispute_resolved`.
  /// Defaults to false for all existing call sites.
  final bool disputeResolved;
}

class TerritoryService {
  TerritoryService._();
  static final TerritoryService instance = TerritoryService._();

  static const bool kDemoMode = true;

  // ── Supabase Edge Function path ───────────────────────────────────────────

  /// Call when Supabase is connected. Delegates claim validation to the
  /// claim_territory Edge Function (speed gate, teleport check, lasso, H3).
  /// Falls back to null on any error so the caller can retry locally.
  Future<ClaimOutcome?> claimViaEdgeFunction(
    List<LatLng> track,
    String city,
  ) async {
    if (!SupabaseService.instance.isConnected) return null;

    final coords =
        track.map((p) => [p.longitude, p.latitude]).toList();
    final geoJson = {
      'type': 'LineString',
      'coordinates': coords,
    };

    try {
      final response =
          await SupabaseService.instance.supabase.functions.invoke(
        SupabaseConfig.fnClaimTerritory,
        body: {
          'track': geoJson,
          'city': city,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;

      final result = data['result'] as String?;
      final zoneId = data['zone_id'] as String?;
      final disputeResolved = data['dispute_resolved'] as bool? ?? false;

      return ClaimOutcome(
        switch (result) {
          'claimed' => TerritoryResult.claimed,
          'conquered' => TerritoryResult.conquered,
          'disputed' => TerritoryResult.disputed,
          _ => TerritoryResult.failed,
        },
        zoneId,
        disputeResolved: disputeResolved,
      );
    } catch (e) {
      debugPrint('[TerritoryService] claimViaEdgeFunction error: $e');
      return null;
    }
  }

  /// Grace period before decay starts: 15s demo, 72h production.
  static Duration get kDecayGracePeriod =>
      kDemoMode ? const Duration(seconds: 15) : const Duration(hours: 72);

  /// How often decay runs: 15s demo, 24h production.
  static Duration get kDecayInterval =>
      kDemoMode ? const Duration(seconds: 15) : const Duration(hours: 24);

  /// Influence lost per day from inactivity.
  static const double kDecayPerDay = 14.0 / 365.0;

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
    final defendedIds = <String>[];
    final ownedOverlapIds = <String>[];

    // Zones requiring instant intersection transfer: (rivalRow, intersection pts).
    final intersectJobs = <(Map<String, Object?>, List<LatLng>)>[];

    for (final r in rivals) {
      final rivalOwnerId = r['owner_id'] as String?;
      if (rivalOwnerId == null) continue;

      final geom = r['geom_json'];
      if (geom is! String) continue;
      final rivalPoints = _parseRing(geom);
      if (rivalPoints == null || rivalPoints.length < 3) continue;

      final rivalBBox = _bbox(rivalPoints);
      if (!_bboxesIntersect(newBBox, rivalBBox)) continue;

      if (rivalOwnerId == userId) {
        if ((r['status'] as String?) == 'disputed') {
          var anyOverlap = false;
          for (final v in rivalPoints) {
            if (_pointInRing(v, track)) { anyOverlap = true; break; }
          }
          if (!anyOverlap) {
            for (final v in track) {
              if (_pointInRing(v, rivalPoints)) { anyOverlap = true; break; }
            }
          }
          if (anyOverlap) {
            defendedIds.add(r['id'] as String);
            continue;
          }
        }
        ownedOverlapIds.add(r['id'] as String);
        continue;
      }

      // Full containment → direct conquest.
      var allInside = true;
      for (final v in rivalPoints) {
        if (!_pointInRing(v, track)) { allInside = false; break; }
      }
      if (allInside) {
        conqueredIds.add(r['id'] as String);
        continue;
      }

      // Partial overlap → compute intersection for instant transfer.
      final intersection = _sutherlandHodgman(rivalPoints, track);
      if (intersection.length >= 3) {
        intersectJobs.add((r, intersection));
      }
    }

    final ds = DatabaseService.instance;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Sequential Supabase calls — no ACID transaction (acceptable for MVP).

    // Full conquests.
    for (final id in conqueredIds) {
      await ds.updateZone(id, {
        'owner_id': userId,
        'influence': 1.0,
        'status': 'owned',
        'contested_by_id': null,
        'last_active_at': nowIso,
        'updated_at': nowIso,
      });
    }

    // Instant intersection transfers: carve intersection out of rival zone.
    for (final (rivalRow, intersection) in intersectJobs) {
      final rivalId = rivalRow['id'] as String;
      final rivalOwnerId = rivalRow['owner_id'] as String;
      final rivalGeom = rivalRow['geom_json'] as String;
      final rivalPoints = _parseRing(rivalGeom)!;

      // Remainder = rival points not inside the intersection.
      final remainder = rivalPoints
          .where((pt) => !_pointInRing(pt, intersection))
          .toList();

      if (remainder.length >= 3) {
        final remainderHull = _convexHull(remainder);
        if (remainderHull.length >= 3) {
          await ds.updateZone(rivalId, {
            'geom_json': _encodePolygon(remainderHull),
            'dispute_at': nowIso,
            'updated_at': nowIso,
          });
        } else {
          await ds.deleteZone(rivalId);
        }
      } else {
        // Rival loses the whole zone.
        await ds.deleteZone(rivalId);
      }

      // New zone for attacker from the intersection polygon.
      final newId = _uuidV4();
      await ds.insertZone({
        'id': newId,
        'owner_id': userId,
        'city': rivalRow['city'] as String,
        'geom_json': _encodePolygon(intersection),
        'influence': 1.0,
        'status': 'owned',
        'contested_by_id': null,
        'created_at': nowIso,
        'updated_at': nowIso,
        'credits_earned': 0.0,
        'last_income_at': null,
        'last_active_at': nowIso,
        'dispute_at': nowIso,
        'parent_id': rivalId,
      });

      debugPrint('[Territory] instant transfer $rivalId → $newId ($rivalOwnerId→$userId)');
      conqueredIds.add(newId);
    }

    // Defended zones.
    for (final id in defendedIds) {
      await ds.updateZone(id, {
        'status': 'owned',
        'contested_by_id': null,
        'updated_at': nowIso,
      });
    }

    final hasActivity = conqueredIds.isNotEmpty ||
        intersectJobs.isNotEmpty ||
        defendedIds.isNotEmpty;

    ClaimOutcome outcome;
    if (!hasActivity) {
      final newId = _uuidV4();
      await ds.insertZone({
        'id': newId,
        'owner_id': userId,
        'city': city,
        'geom_json': _encodePolygon(track),
        'influence': 1.0,
        'status': 'owned',
        'contested_by_id': null,
        'created_at': nowIso,
        'updated_at': nowIso,
        'credits_earned': 0.0,
        'last_income_at': null,
        'last_active_at': nowIso,
        'dispute_at': null,
        'parent_id': null,
      });
      outcome = ClaimOutcome(TerritoryResult.claimed, newId);
    } else if (conqueredIds.isNotEmpty) {
      outcome = ClaimOutcome(TerritoryResult.conquered, conqueredIds.first);
    } else if (defendedIds.isNotEmpty) {
      outcome = ClaimOutcome(TerritoryResult.claimed, defendedIds.first);
    } else {
      outcome = const ClaimOutcome(TerritoryResult.disputed, null);
    }

    if (outcome.result != TerritoryResult.failed) {
      await _mergeAdjacentZones(userId, city);
      if (outcome.result == TerritoryResult.claimed) {
        TelemetryService.instance.logEvent('claim_made', props: {'zone_id': outcome.affectedZoneId ?? ''}).catchError((_) {});
      } else if (outcome.result == TerritoryResult.conquered) {
        TelemetryService.instance.logEvent('conquest_made', props: {'zone_id': outcome.affectedZoneId ?? ''}).catchError((_) {});
      }
    }
    return outcome;
  }

  // ── Daily decay ───────────────────────────────────────────────────────────

  /// Call once on app open. Reads `prefs.last_decay_at` and skips if not due.
  Future<void> runDailyDecayIfDue(String city, String userId) async {
    final ds = DatabaseService.instance;

    final lastDecayStr = await ds.getPref(userId, 'last_decay_at');
    final lastDecay =
        lastDecayStr != null ? DateTime.tryParse(lastDecayStr) : null;
    final now = DateTime.now().toUtc();

    if (lastDecay != null && now.difference(lastDecay) < kDecayInterval) {
      return;
    }

    await _applyDecay(city, now);

    await ds.setPref(userId, 'last_decay_at', now.toIso8601String());
  }

  Future<void> _applyDecay(String city, DateTime now) async {
    final ds = DatabaseService.instance;
    final nowIso = now.toIso8601String();

    final owned = await ds.getZonesByCity(city, status: 'owned');
    if (owned.isEmpty) return;

    var decayed = 0;
    for (final z in owned) {
      final lastActiveStr = z['last_active_at'] as String?;
      final lastActive =
          lastActiveStr != null ? DateTime.tryParse(lastActiveStr) : null;

      final inGracePeriod = lastActive != null &&
          now.difference(lastActive) < kDecayGracePeriod;
      if (inGracePeriod) continue;

      final currentInf = (z['influence'] as num).toDouble();
      if (currentInf <= 1.0) continue;

      final newInf = (currentInf - kDecayPerDay).clamp(1.0, 15.0);
      await ds.updateZone(z['id'] as String, {
        'influence': newInf,
        'updated_at': nowIso,
      });
      decayed++;
    }

    if (decayed > 0) {
      debugPrint('[Territory] decay applied to $decayed zones in $city');
    }
  }

  // ── Passive income ────────────────────────────────────────────────────────

  /// Accumulate credits for owned zones. Call periodically (e.g. every 60
  /// simulation ticks, or on app open alongside decay).
  Future<void> accruePassiveIncome(String city) async {
    final ds = DatabaseService.instance;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final owned = await ds.getZonesByCity(city, status: 'owned');

    for (final z in owned) {
      final lastStr = z['last_income_at'] as String?;
      final last = lastStr != null ? DateTime.tryParse(lastStr) : null;
      final now = DateTime.now().toUtc();
      final elapsedHours =
          last != null ? now.difference(last).inSeconds / 3600.0 : 0.0;
      if (elapsedHours < 0.001) continue;

      final influence = (z['influence'] as num).toDouble();
      final pts = _parseRing(z['geom_json'] as String);
      if (pts == null) continue;
      final areaKm2 = polygonAreaKm2(pts);
      final earned = influence * areaKm2 * elapsedHours;
      final current = (z['credits_earned'] as num?)?.toDouble() ?? 0.0;

      await ds.updateZone(z['id'] as String, {
        'credits_earned': current + earned,
        'last_income_at': nowIso,
      });
    }
  }

  // ── Zone merging ──────────────────────────────────────────────────────────

  Future<void> _mergeAdjacentZones(String userId, String city) async {
    final ds = DatabaseService.instance;
    final ownedRows = await ds.getOwnedZonesByUser(userId, city);
    if (ownedRows.length < 2) return;

    final zones = <({
      String id,
      List<LatLng> pts,
      double inf,
      double minLat,
      double maxLat,
      double minLng,
      double maxLng
    })>[];
    for (final r in ownedRows) {
      final pts = _parseRing(r['geom_json'] as String);
      if (pts == null || pts.length < 3) continue;
      final bb = _bbox(pts);
      zones.add((
        id: r['id'] as String,
        pts: pts,
        inf: (r['influence'] as num?)?.toDouble() ?? 1.0,
        minLat: bb.minLat,
        maxLat: bb.maxLat,
        minLng: bb.minLng,
        maxLng: bb.maxLng,
      ));
    }
    if (zones.length < 2) return;

    const kProximityDeg = 0.0015;
    final parent = List<int>.generate(zones.length, (i) => i);

    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final a = zones[i], b = zones[j];
        final touching = !(a.maxLat + kProximityDeg < b.minLat ||
            a.minLat - kProximityDeg > b.maxLat ||
            a.maxLng + kProximityDeg < b.minLng ||
            a.minLng - kProximityDeg > b.maxLng);
        if (touching) union(i, j);
      }
    }

    final groups = <int, List<int>>{};
    for (var i = 0; i < zones.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final group in groups.values) {
      if (group.length < 2) continue;

      final allPts = <LatLng>[];
      var totalInf = 0.0;
      for (final idx in group) {
        allPts.addAll(zones[idx].pts);
        totalInf += zones[idx].inf;
      }
      final avgInf = (totalInf / group.length).clamp(1.0, 15.0);
      final hull = _convexHull(allPts);
      if (hull.length < 3) continue;

      final keepId = zones[group.first].id;
      for (final idx in group.skip(1)) {
        await ds.deleteZone(zones[idx].id);
      }
      await ds.updateZone(keepId, {
        'geom_json': _encodePolygon(hull),
        'influence': avgInf,
        'updated_at': nowIso,
      });
      debugPrint(
          '[Territory] merged ${group.length} zones for $userId → hull ${hull.length} pts, inf $avgInf');
    }
  }

  // ── Sutherland-Hodgman polygon clipping ──────────────────────────────────

  static List<LatLng> _sutherlandHodgman(
      List<LatLng> subject, List<LatLng> clip) {
    var output = List<LatLng>.from(subject);
    if (output.isEmpty) return output;
    final n = clip.length;
    for (var i = 0; i < n; i++) {
      if (output.isEmpty) break;
      final input = List<LatLng>.from(output);
      output.clear();
      final edgeA = clip[i];
      final edgeB = clip[(i + 1) % n];
      for (var j = 0; j < input.length; j++) {
        final current = input[j];
        final prev = input[(j + input.length - 1) % input.length];
        final currentInside = _isInsideEdge(current, edgeA, edgeB);
        final prevInside = _isInsideEdge(prev, edgeA, edgeB);
        if (currentInside) {
          if (!prevInside) {
            final inter = _lineIntersect(prev, current, edgeA, edgeB);
            if (inter != null) output.add(inter);
          }
          output.add(current);
        } else if (prevInside) {
          final inter = _lineIntersect(prev, current, edgeA, edgeB);
          if (inter != null) output.add(inter);
        }
      }
    }
    return output;
  }

  static bool _isInsideEdge(LatLng p, LatLng a, LatLng b) {
    return (b.longitude - a.longitude) * (p.latitude - a.latitude) -
            (b.latitude - a.latitude) * (p.longitude - a.longitude) >=
        0;
  }

  static LatLng? _lineIntersect(
      LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    final d1lat = p2.latitude - p1.latitude;
    final d1lng = p2.longitude - p1.longitude;
    final d2lat = p4.latitude - p3.latitude;
    final d2lng = p4.longitude - p3.longitude;
    final denom = d1lat * d2lng - d1lng * d2lat;
    if (denom.abs() < 1e-10) return null;
    final t = ((p3.latitude - p1.latitude) * d2lng -
            (p3.longitude - p1.longitude) * d2lat) /
        denom;
    return LatLng(p1.latitude + t * d1lat, p1.longitude + t * d1lng);
  }

  // ── Polygon area (Shoelace → km²) ────────────────────────────────────────

  static double polygonAreaKm2(List<LatLng> pts) {
    final n = pts.length;
    if (n < 2) return 0.0;
    double area = 0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += pts[i].longitude * pts[j].latitude;
      area -= pts[j].longitude * pts[i].latitude;
    }
    area = area.abs() / 2.0;
    final centerLat =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / n;
    final cosLat = math.cos(centerLat * math.pi / 180);
    return area * 111.32 * 111.32 * cosLat;
  }

  // ── Convex hull (Graham scan) ─────────────────────────────────────────────

  static List<LatLng> _convexHull(List<LatLng> pts) {
    if (pts.length <= 2) return pts;
    final sorted = List<LatLng>.from(pts)
      ..sort((a, b) {
        final c = a.longitude.compareTo(b.longitude);
        return c != 0 ? c : a.latitude.compareTo(b.latitude);
      });

    final lower = <LatLng>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <LatLng>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    return [
      ...lower.sublist(0, lower.length - 1),
      ...upper.sublist(0, upper.length - 1),
    ];
  }

  static double _cross(LatLng o, LatLng a, LatLng b) =>
      (a.longitude - o.longitude) * (b.latitude - o.latitude) -
      (a.latitude - o.latitude) * (b.longitude - o.longitude);

  // ── Helpers ───────────────────────────────────────────────────────────────

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
