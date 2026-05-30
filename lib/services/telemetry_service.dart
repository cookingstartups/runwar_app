import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

// Singleton local telemetry. All events stored in sqflite `events` table.
// events table schema (already created by DatabaseService v2):
//   id TEXT PK, name TEXT NOT NULL, props_json TEXT, created_at TEXT NOT NULL

class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  Future<void> logEvent(String name, {Map<String, dynamic>? props}) async {
    try {
      final db = DatabaseService.instance.db;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('events', {
        'id': _uuid(),
        'name': name,
        'props_json': props != null ? jsonEncode(props) : null,
        'created_at': now,
      });
      debugPrint('[Telemetry] $name ${props ?? ''}');
    } catch (e) {
      debugPrint('[Telemetry] log error: $e');
    }
  }

  // Supported event names (pass as string constants):
  // app_open, map_view, run_start, run_complete, loop_closed, claim_made,
  // share_tapped, timelapse_started, timelapse_replayed, session_duration

  static String _uuid() {
    // Simple time-based ID sufficient for local telemetry
    return '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  }

  static int _counter = 0;
}
