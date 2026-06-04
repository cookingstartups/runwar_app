import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Schedules or cancels the daily streak reminder notification.
///
/// Only schedules when streak >= 3. Cancels when:
///   - streak < 3, or
///   - player has already logged in today.
///
/// Notification fires at 18:00 local time (or 18:00 tomorrow if past 18:00).
class StreakReminderScheduler {
  static const int notificationId = 7777;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Ensure timezone data is loaded. Safe to call multiple times.
  static void ensureTimezoneInitialized() {
    tz_data.initializeTimeZones();
  }

  static Future<void> scheduleOrCancel({
    required int currentStreak,
    required DateTime? lastLoginAt,
  }) async {
    if (currentStreak < 3) {
      await _plugin.cancel(notificationId);
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    if (lastLoginAt != null && lastLoginAt.isAfter(todayStart)) {
      // Already logged in today — cancel pending notification.
      await _plugin.cancel(notificationId);
      return;
    }

    // Schedule for today 18:00 or tomorrow 18:00 if past 18:00.
    var scheduledDate = DateTime(now.year, now.month, now.day, 18, 0);
    if (now.isAfter(scheduledDate)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'streak_reminder',
      'Streak Reminders',
      channelDescription: 'Daily streak reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      notificationId,
      "Don't break your streak!",
      'You\'re on a $currentStreak-day streak. Log in before midnight!',
      tzScheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
