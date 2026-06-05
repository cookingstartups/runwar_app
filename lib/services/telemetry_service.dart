import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'supabase_service.dart';

// Singleton telemetry. All events stored in Supabase `events` table.

class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  Future<void> logEvent(String name, {Map<String, dynamic>? props}) async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      await DatabaseService.instance.insertEvent(
        _uuid(),
        userId,
        name,
        props: props,
      );
      debugPrint('[Telemetry] $name ${props ?? ''}');
    } catch (e) {
      debugPrint('[Telemetry] log error: $e');
    }
  }

  // Supported event names (pass as string constants):
  // app_open, map_view, run_start, run_complete, loop_closed, claim_made,
  // share_tapped, timelapse_started, timelapse_replayed, session_duration

  static String _uuid() {
    // Simple time-based ID sufficient for telemetry
    return '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  }

  static int _counter = 0;
}
