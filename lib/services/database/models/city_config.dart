// lib/services/database/models/city_config.dart
//
// Immutable CityConfig model parsed from the city_config view.
// Design.md §1 — CityConfig.fromJsonRow + CityConfig.valencia contract.
//
// IMPORTANT: CityConfig.valencia is `static final` NOT `static const` because
// LatLngBounds (flutter_map ^6.1.0) validates in its constructor body and is
// not const-constructable. The CityConfig constructor itself is const.

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// City-level configuration loaded from the city_config view.
class CityConfig {
  const CityConfig({
    required this.launchCity,
    required this.center,
    required this.bounds,
  });

  final String launchCity;
  final LatLng center;
  final LatLngBounds bounds;

  /// Locked Valencia fallback. Used when Supabase is unreachable or times out.
  /// `static final` — not const — because LatLngBounds is not const-constructable.
  static final CityConfig valencia = CityConfig(
    launchCity: 'Valencia',
    center: const LatLng(39.4699, -0.3763),
    bounds: LatLngBounds(
      const LatLng(39.38, -0.50), // south-west
      const LatLng(39.55, -0.29), // north-east
    ),
  );

  /// Parse a row from the city_config view.
  ///
  /// The view emits a single row with one `config` JSONB column containing:
  ///   launch_city, city_center_lat, city_center_lng,
  ///   city_bounds_north, city_bounds_south, city_bounds_east, city_bounds_west
  factory CityConfig.fromJsonRow(Map<String, dynamic> row) {
    final config = row['config'] as Map<String, dynamic>;

    final launchCity = config['launch_city'] as String? ?? 'Valencia';
    final centerLat = _toDouble(config['city_center_lat']) ?? 39.4699;
    final centerLng = _toDouble(config['city_center_lng']) ?? -0.3763;
    final north = _toDouble(config['city_bounds_north']) ?? 39.55;
    final south = _toDouble(config['city_bounds_south']) ?? 39.38;
    final east = _toDouble(config['city_bounds_east']) ?? -0.29;
    final west = _toDouble(config['city_bounds_west']) ?? -0.50;

    return CityConfig(
      launchCity: launchCity,
      center: LatLng(centerLat, centerLng),
      bounds: LatLngBounds(
        LatLng(south, west), // south-west corner
        LatLng(north, east), // north-east corner
      ),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  String toString() => 'CityConfig($launchCity, center: $center)';
}
