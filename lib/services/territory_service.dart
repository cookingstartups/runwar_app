import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'database_service.dart';
import 'zones_service.dart';
import 'supabase_service.dart';
import 'telemetry_service.dart';
import 'error_log_service.dart';
import '../config/supabase_config.dart';

enum TerritoryResult { claimed, conquered, disputed, failed }

class ClaimOutcome {
  const ClaimOutcome(this.result, this.affectedZoneId,
      {this.disputeResolved = false, this.reason});
  final TerritoryResult result;
  final String? affectedZoneId;

  /// True when this claim resolved an existing open dispute (conquered path).
  /// Parsed from claim_territory Edge fn response field `dispute_resolved`.
  /// Defaults to false for all existing call sites.
  final bool disputeResolved;

  /// Underlying failure reason (server `reason` field, e.g. `too_short`,
  /// `corrupt_track`, or a local exception's message) — carried for
  /// diagnostics on a `failed` outcome (R4-AC4). Null for non-failed
  /// outcomes and for legacy call sites that do not supply one.
  final String? reason;
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
      final reason = data['reason'] as String?;

      // Defensive parse only — no current consumer needs these this cycle
      // (design.md Q1/Section 3). The zones table / Realtime stream is what
      // the client relies on to observe a merged row; `zonesProvider(city)`
      // is invalidated by the caller after every non-failed claim, which is
      // a full re-fetch and therefore already reflects server-side deletes
      // of absorbed zone rows without any separate client-side cache to evict.
      final merged = data['merged'] as bool? ?? false;
      final absorbedZoneIds =
          (data['absorbed_zone_ids'] as List?)?.cast<String>() ?? const <String>[];
      debugPrint('[TerritoryService] claim merged=$merged absorbed=${absorbedZoneIds.length}');

      return ClaimOutcome(
        switch (result) {
          'claimed' => TerritoryResult.claimed,
          'conquered' => TerritoryResult.conquered,
          'disputed' => TerritoryResult.disputed,
          _ => TerritoryResult.failed,
        },
        zoneId,
        disputeResolved: disputeResolved,
        reason: reason,
      );
    } catch (e, st) {
      // Distinguish a real edge-function error response (e.g. a merge
      // failure returned as a 5xx) from a genuine network-unreachable
      // failure. FunctionException (thrown by the Supabase functions client
      // for any non-2xx response) always carries a `status` field; a true
      // connectivity failure (timeout, DNS, socket) does not. Read it
      // dynamically rather than importing supabase_flutter's type here -
      // this file stays the one permitted Edge Function invocation site
      // without becoming a second DatabaseService-style import boundary.
      int? status;
      dynamic details;
      try {
        status = (e as dynamic).status as int?;
        details = (e as dynamic).details;
      } catch (_) {
        status = null;
        details = null;
      }

      ErrorLogService.logClientError(
        provider: 'claimViaEdgeFunction',
        error: 'status=$status details=$details error=$e',
        stackTrace: st,
        retryCount: 0,
      );

      if (status != null) {
        // The edge function responded, but with an error (e.g. the merge
        // step failed server-side). Surface a failed outcome instead of
        // silently falling back to the offline path, which would evaluate
        // the claim locally and mask the server-side merge failure.
        return ClaimOutcome(
          TerritoryResult.failed,
          null,
          reason: 'edge_function_error_$status',
        );
      }

      // No status means the request never got a response at all (network
      // unreachable, timeout, etc.) - fall back to the offline path as
      // designed.
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
      return const ClaimOutcome(TerritoryResult.failed, null, reason: 'too_short');
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

  /// R2-AC6 interim decision (design.md Section 3b, option 2 - recommended):
  /// the offline fallback no longer performs a local merge. This used to run
  /// a bbox-proximity union-find + convex-hull merge, both of which are
  /// rejected by the corrected spec (a convex hull can silently grant ground
  /// the player never ran, and ~166 m bbox proximity is not real contiguity).
  /// Porting the server's true single-rule polygon-union algorithm (exact
  /// union sealed by a bounded morphological closing) to pure Dart for this
  /// rarely-hit offline-only path was judged not worth the new surface area
  /// (design.md Section 3b rationale).
  ///
  /// Contiguous same-owner zones created while offline now simply remain
  /// independent rows locally. The next ONLINE claim's server-side merge
  /// (`claim_territory`) performs a full rescan of the owner's zones in the
  /// city and reconciles them (R2-AC3). In the meantime, the player-visible
  /// territory still looks unified because the render-time union
  /// (`map_screen.dart`'s `_buildUnifiedOwnedPolygons` / R3) is independent
  /// of database row count by design.
  Future<void> _mergeAdjacentZones(String userId, String city) async {
    // Intentionally a no-op — see doc comment above.
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

  /// Extracts one outline ring per member polygon from [geomJson]. Handles
  /// both `Polygon` (the single-rule adjacent-zone merge contract's only
  /// output shape, design.md Section 4) and `MultiPolygon` (legacy/fallback
  /// only - never produced by the current merge algorithm) shapes. Returns
  /// an empty list on any parse failure or malformed ring - never throws.
  static List<List<LatLng>> _parseOutlines(String geomJson) {
    try {
      final d = jsonDecode(geomJson);
      if (d is! Map) return const [];
      final coords = d['coordinates'];
      if (coords is! List || coords.isEmpty) return const [];

      List<LatLng>? ringFrom(dynamic rawRing) {
        if (rawRing is! List || rawRing.length < 3) return null;
        final out = <LatLng>[];
        for (final pt in rawRing) {
          if (pt is! List || pt.length < 2) return null;
          out.add(LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()));
        }
        return out;
      }

      if (d['type'] == 'MultiPolygon') {
        final outlines = <List<LatLng>>[];
        for (final poly in coords) {
          if (poly is! List || poly.isEmpty) continue;
          final ring = ringFrom(poly[0]);
          if (ring != null) outlines.add(ring);
        }
        return outlines;
      }

      // Polygon (default/legacy) — single outer ring at coordinates[0].
      final ring = ringFrom(coords[0]);
      return ring == null ? const [] : [ring];
    } catch (_) {
      return const [];
    }
  }

  /// Backward-compatible single-ring accessor. For a `MultiPolygon` (a
  /// legacy or fallback shape only - the single-rule merge contract never
  /// produces one), returns only the FIRST member outline - call sites that
  /// need every outline of a multi-outline zone must use [_parseOutlines]
  /// directly (design.md Section 4/Consequences #3 flags the remaining
  /// single-ring call sites in this file, e.g. the rival-overlap scan, as a
  /// known, lower-severity gap left for a future cycle rather than a hard
  /// rejection).
  static List<LatLng>? _parseRing(String geomJson) {
    final outlines = _parseOutlines(geomJson);
    return outlines.isEmpty ? null : outlines.first;
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
