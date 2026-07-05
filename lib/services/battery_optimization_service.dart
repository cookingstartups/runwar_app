import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'permission_service.dart';

/// Manages battery optimization exemption prompts and status checks.
///
/// AC-16: [isOptimizationActive] drives the warning banner on MapScreen.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  /// Requests the system battery optimization exemption dialog exactly once.
  ///
  /// The old private prompted-once flag is retired - its idempotency job is
  /// subsumed by PermissionService's persisted priming flag plus the live
  /// `isBatteryGranted` check (no duplicate grant-tracking flags). No-ops if
  /// already granted, or if the priming flow already asked once (granted or
  /// deferred - do not nag on every FAB tap). Falls back to the direct
  /// request only for the pre-priming-rollout edge case (a user mid-upgrade
  /// who reaches this call site before ever passing through the new gate).
  static Future<void> requestOnce() async {
    try {
      if (await PermissionService.instance.isBatteryGranted()) return;
      if (await PermissionService.instance.isPrimingDone()) return;
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
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
