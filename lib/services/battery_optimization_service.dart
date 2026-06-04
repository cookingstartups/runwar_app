import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages battery optimization exemption prompts and status checks.
///
/// AC-15: prompt shown exactly once per install (gated by SharedPreferences).
/// AC-16: [isOptimizationActive] drives the warning banner on MapScreen.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const _prefsKey = 'battery_opt_prompted';

  /// Requests the system battery optimization exemption dialog exactly once.
  ///
  /// After the first call, sets [_prefsKey]=true so subsequent calls are
  /// no-ops. Returns immediately if the exemption is already granted.
  static Future<void> requestOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) ?? false) return;
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {}
  }

  /// Returns true if battery optimization is still active (exemption NOT granted).
  /// Used by [BatteryWarningBanner] to decide whether to render.
  static Future<bool> isOptimizationActive() async {
    try {
      return !await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }
}
