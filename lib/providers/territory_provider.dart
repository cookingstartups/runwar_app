import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/database/models/zone.dart';
import '../services/territory_service.dart';

final playerTerritoryKm2Provider = FutureProvider.family<double, String>(
  (ref, userId) async {
    final rows = await DatabaseService.instance.getZonesByOwner(userId);
    if (rows.isEmpty) return 0.0;
    var total = 0.0;
    for (final r in rows) {
      try {
        total += TerritoryService.polygonAreaKm2(Zone.fromGeoJsonRow(r).points);
      } catch (_) {
        // Skip degenerate zone geometry.
      }
    }
    return total;
  },
);
