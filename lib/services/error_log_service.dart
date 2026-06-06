// lib/services/error_log_service.dart
//
// Remote error logger — fire-and-forget call to the `log_client_error` edge
// function. This method MUST NOT throw or rethrow under any circumstances.
//
// Usage (no await — callers do not await this):
//   ErrorLogService.logClientError(
//     provider: 'profileGateProvider', error: e, stackTrace: st,
//     retryCount: 0, userId: userId,
//   );
//
// Full spec: infra/meta/specs/runwar/mvp/boot-splash-unified/requirements.md

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'supabase_service.dart';

/// Remote error logger — fire-and-forget call to the `log_client_error` edge
/// function.  Callers MUST NOT await this call.
class ErrorLogService {
  ErrorLogService._();

  /// Logs a provider error to the Supabase `client_errors` table via the
  /// `log_client_error` edge function.
  ///
  /// - Never throws or rethrows — all failures are caught and printed via
  ///   [debugPrint].
  /// - Callers must NOT await the returned [Future].
  static Future<void> logClientError({
    required String provider,
    required Object error,
    required StackTrace stackTrace,
    required int retryCount,
    String? userId,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final devicePlugin = DeviceInfoPlugin();

      String device = 'unknown';
      String platform = 'android';

      if (Platform.isAndroid) {
        final info = await devicePlugin.androidInfo;
        device = '${info.manufacturer} ${info.model}';
        platform = 'android';
      } else if (Platform.isIOS) {
        final info = await devicePlugin.iosInfo;
        device = info.utsname.machine;
        platform = 'ios';
      }

      final stackLines = stackTrace
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final stackFirstLine = stackLines.isNotEmpty ? stackLines.first : '';

      await SupabaseService.instance.supabase.functions.invoke(
        'log_client_error',
        body: {
          'user_id': userId,
          'provider': provider,
          'error_class': error.runtimeType.toString(),
          'error_message': error.toString(),
          'stack_first_line': stackFirstLine,
          'retry_count': retryCount,
          'app_version': packageInfo.version,
          'device': device,
          'platform': platform,
        },
      );
    } catch (e, st) {
      debugPrint('[ErrorLogService] failed to log error: $e\n$st');
    }
  }
}
