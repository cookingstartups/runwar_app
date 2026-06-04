import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../theme.dart';

/// Slim amber banner shown during an active run when battery optimization
/// is NOT disabled. Tapping opens the system battery settings (AC-16).
class BatteryWarningBanner extends StatelessWidget {
  const BatteryWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
      },
      child: Material(
        color: kAccent2.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.black87, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Battery optimization active — GPS may stop in background. Fix',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.black54, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
