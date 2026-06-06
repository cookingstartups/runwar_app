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
  });

  final String id;
  final String ownerId;
  final String city;

  /// Clamped 1..15 at construction time (design.md §1).
  final int influenceLevel;
  final ZoneStatus status;

  /// Polygon ring in lat/lng order, parsed from geom_json.coordinates[0]
  /// which uses GeoJSON [lng, lat] convention.
  final List<LatLng> points;

  /// Parse a row from the zones_geojson view.
  ///
  /// [row] is a Map<String, dynamic> with at minimum:
  ///   id, owner_id, city, influence_level, status, geom_json
  ///
  /// [geom_json] may arrive as a JSON string OR as a Map (Supabase JSONB).
  /// Both forms are handled here.
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

    // Extract the outer ring from the Polygon coordinates.
    // GeoJSON: coordinates[0] is the outer ring; each point is [lng, lat].
    final coordsRaw = geom['coordinates'];
    final List<LatLng> points;
    if (coordsRaw is List && coordsRaw.isNotEmpty) {
      final ring = coordsRaw[0];
      if (ring is List) {
        points = ring
            .whereType<List>()
            .where((pt) => pt.length >= 2)
            .map((pt) => LatLng(
                  (pt[1] as num).toDouble(), // lat
                  (pt[0] as num).toDouble(), // lng
                ))
            .toList();
      } else {
        points = const [];
      }
    } else {
      points = const [];
    }

    // Clamp influenceLevel to 1..15 (design.md §1).
    final rawLevel = (row['score'] as num?)?.toInt() ?? 1;
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
    );
  }

  @override
  String toString() =>
      'Zone(id: $id, owner: $ownerId, level: $influenceLevel, status: $status)';
}
