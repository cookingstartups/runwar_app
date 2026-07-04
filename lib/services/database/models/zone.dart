// lib/services/database/models/zone.dart
//
// Immutable Zone model parsed from the zones_geojson view.
// Design.md §1 — Zone.fromGeoJsonRow contract.

import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Status values emitted by the zones_geojson view `status` column.
enum ZoneStatus { owned, disputed }

/// Immutable snapshot of a zone as delivered by the zones_geojson view.
class Zone {
  const Zone({
    required this.id,
    required this.ownerId,
    required this.city,
    required this.influenceLevel,
    required this.status,
    required this.points,
    List<List<LatLng>>? outlines,
  }) : _outlines = outlines;

  final String id;
  final String ownerId;
  final String city;

  /// Clamped 1..15 at construction time (design.md §1).
  final int influenceLevel;
  final ZoneStatus status;

  /// Primary outer ring in lat/lng order - for a `Polygon` zone (the only
  /// shape the single-rule adjacent-zone merge contract produces, design.md
  /// Section 4) this is its only outline; for a legacy or fallback
  /// `MultiPolygon` zone this is the FIRST member outline only. Existing
  /// single-ring consumers (tap hit-test, fog centroid, area calc) keep
  /// reading this field unchanged. Callers that must see every outline of a
  /// multi-outline zone (e.g. map_screen's render-time union) should read
  /// [outlines] instead.
  final List<LatLng> points;

  final List<List<LatLng>>? _outlines;

  /// Every outer ring for this zone: one entry for a `Polygon`, one entry
  /// per member polygon for a `MultiPolygon`. Always non-empty when
  /// [points] is non-empty (`outlines.first == points`); empty only when
  /// parsing failed entirely. Falls back to `[points]` for any `Zone`
  /// constructed without an explicit `outlines` argument (e.g. existing
  /// test fixtures / call sites predating the MultiPolygon fix), so a
  /// single-outline zone always behaves exactly as it did before this
  /// field was added.
  List<List<LatLng>> get outlines =>
      _outlines ?? (points.isEmpty ? const <List<LatLng>>[] : <List<LatLng>>[points]);

  /// Parse a row from the zones_geojson view.
  ///
  /// [row] is a Map<String, dynamic> with at minimum:
  ///   id, owner_id, city, influence_level, status, geom_json
  ///
  /// [geom_json] may arrive as a JSON string OR as a Map (Supabase JSONB).
  /// Both forms are handled here. Handles both `Polygon` (the single-rule
  /// adjacent-zone merge contract's only output shape, design.md Section 4)
  /// and `MultiPolygon` (legacy/fallback only - never produced by the
  /// current merge algorithm) shapes.
  factory Zone.fromGeoJsonRow(Map<String, dynamic> row) {
    // Parse geom_json — Supabase may send JSONB as Map or as a String.
    final geomRaw = row['geom_json'];
    final Map<String, dynamic> geom;
    if (geomRaw is String) {
      geom = jsonDecode(geomRaw) as Map<String, dynamic>;
    } else if (geomRaw is Map<String, dynamic>) {
      geom = geomRaw;
    } else {
      geom = const {};
    }

    final outlines = _parseOutlines(geom);
    final points = outlines.isEmpty ? const <LatLng>[] : outlines.first;

    // Clamp influenceLevel to 1..15 (design.md §1).
    final rawLevel = (row['influence_level'] as num?)?.toInt() ?? 1;
    final influenceLevel = rawLevel.clamp(1, 15);

    // Parse status — default to owned for unknown values.
    final statusStr = row['status'] as String? ?? 'owned';
    final status =
        statusStr == 'disputed' ? ZoneStatus.disputed : ZoneStatus.owned;

    return Zone(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String? ?? '',
      city: row['city'] as String? ?? 'Valencia',
      influenceLevel: influenceLevel,
      status: status,
      points: points,
      outlines: outlines,
    );
  }

  /// Extracts one outer-ring outline per member polygon from GeoJSON [geom].
  /// `Polygon` -> one outline (coordinates[0]); `MultiPolygon` -> one
  /// outline per member (coordinates[i][0]). Never throws — malformed rings
  /// are skipped, an entirely-unparseable shape yields an empty list.
  static List<List<LatLng>> _parseOutlines(Map<String, dynamic> geom) {
    final coordsRaw = geom['coordinates'];
    if (coordsRaw is! List || coordsRaw.isEmpty) return const [];

    List<LatLng>? ringFrom(dynamic rawRing) {
      if (rawRing is! List || rawRing.length < 3) return null;
      final out = <LatLng>[];
      for (final pt in rawRing) {
        if (pt is! List || pt.length < 2) return null;
        out.add(LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()));
      }
      return out;
    }

    if (geom['type'] == 'MultiPolygon') {
      final result = <List<LatLng>>[];
      for (final poly in coordsRaw) {
        if (poly is! List || poly.isEmpty) continue;
        final ring = ringFrom(poly[0]);
        if (ring != null) result.add(ring);
      }
      return result;
    }

    // Polygon (default/legacy) — single outer ring at coordinates[0].
    final ring = ringFrom(coordsRaw[0]);
    return ring == null ? const [] : [ring];
  }

  @override
  String toString() =>
      'Zone(id: $id, owner: $ownerId, level: $influenceLevel, status: $status)';
}
