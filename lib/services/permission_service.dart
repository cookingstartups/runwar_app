// lib/services/permission_service.dart
//
// Single owner of permission state for the post-login priming flow.
// Wraps Geolocator (foreground location), NotificationGateway (local
// notification permission), FlutterForegroundTask (battery exemption) and
// permission_handler (background location, settings deep link, unified
// status polling) instead of duplicating their request logic.
//
// Design reference: infra/meta/specs/runwar/permission-priming/design.md

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/run_recorder_provider.dart' show NotificationGateway;

/// The three permission types this feature centralizes. Order here is the
/// canonical display/request order used everywhere.
enum PermKind { location, notifications, battery }

/// Live per-type check result. `notAsked` and `denied` are collapsed to
/// "missing" for skip-logic purposes.
enum PermState { granted, missing }

const _kPrimingDoneKey = 'perm_priming_done';

/// Case-insensitive match against Xiaomi/Redmi/POCO manufacturers.
/// Pure logic - no platform channel - kept standalone for unit testability.
bool classifyMiui(String rawManufacturer) {
  final normalized = rawManufacturer.toLowerCase();
  return normalized.contains('xiaomi') ||
      normalized.contains('redmi') ||
      normalized.contains('poco');
}

/// Filters the canonical [location, notifications, battery] order down to
/// only the members present in [missing]. Pure logic - no platform channel -
/// kept standalone for unit testability.
List<PermKind> orderMissing(Set<PermKind> missing) {
  const canonicalOrder = [
    PermKind.location,
    PermKind.notifications,
    PermKind.battery,
  ];
  return canonicalOrder.where(missing.contains).toList();
}

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  // ── Priming lifecycle ───────────────────────────────────────────────────

  Future<bool> isPrimingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPrimingDoneKey) ?? false;
  }

  Future<void> markPrimingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrimingDoneKey, true);
  }

  /// Live check of all three types, fixed order (location, notifications,
  /// battery). Returns the subset still missing. Android-only; returns []
  /// unconditionally on iOS (platform gate).
  Future<List<PermKind>> missingPermissions() async {
    if (!Platform.isAndroid) return const [];

    final missing = <PermKind>{};
    if (!await isLocationGranted()) missing.add(PermKind.location);
    if (!await isNotificationsGranted()) missing.add(PermKind.notifications);
    if (!await isBatteryGranted()) missing.add(PermKind.battery);
    return orderMissing(missing);
  }

  /// Auto-heal path: if isPrimingDone() is false but a live check shows
  /// nothing missing, mark done without ever showing a card.
  Future<void> autoCompleteIfAllGranted() async {
    final missing = await missingPermissions();
    if (missing.isEmpty) {
      await markPrimingDone();
    }
  }

  // ── Location ─────────────────────────────────────────────────────────────

  Future<bool> isLocationGranted() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<bool> isLocationDeniedForever() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.deniedForever;
  }

  /// Fires the OS foreground location dialog. Only ever called from an
  /// explicit CTA tap.
  Future<LocationPermission> requestForegroundLocation() {
    return Geolocator.requestPermission();
  }

  /// Android 13+ two-step. No-op returning true on API < 33 or iOS.
  /// Outcome never blocks progression (background is a soft upgrade).
  Future<bool> requestBackgroundLocationIfSupported() async {
    if (!Platform.isAndroid) return true;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 33) return true;
      final status = await ph.Permission.locationAlways.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('[PermissionService] background location request failed: $e');
      return false;
    }
  }

  // ── Notifications ───────────────────────────────────────────────────────

  Future<bool> isNotificationsGranted() async {
    try {
      return (await ph.Permission.notification.status).isGranted;
    } catch (e) {
      debugPrint('[PermissionService] isNotificationsGranted failed: $e');
      return false;
    }
  }

  /// Delegates to [NotificationGateway.requestPermission] so the request
  /// logic (Android 13+ POST_NOTIFICATIONS, iOS alert/badge/sound) is not
  /// duplicated (design.md Package Decision).
  Future<bool> requestNotifications() {
    return NotificationGateway.requestPermission();
  }

  // ── Battery ──────────────────────────────────────────────────────────────

  Future<bool> isBatteryGranted() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestBattery() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e) {
      debugPrint('[PermissionService] requestBattery failed: $e');
    }
  }

  // ── MIUI note ────────────────────────────────────────────────────────────

  /// Case-insensitive match against Xiaomi/Redmi/POCO. Defaults to false on
  /// any exception or unrecognized platform - never blocks card render.
  Future<bool> isMiuiManufacturer() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return classifyMiui(info.manufacturer);
    } catch (e) {
      debugPrint('[PermissionService] isMiuiManufacturer failed: $e');
      return false;
    }
  }

  // ── Recovery ─────────────────────────────────────────────────────────────

  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      debugPrint('[PermissionService] openSettings failed: $e');
    }
  }
}
