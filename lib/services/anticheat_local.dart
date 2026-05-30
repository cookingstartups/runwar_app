import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

/// Collects GPS samples + mock-location flags and batches them to the
/// anticheat_score Edge Function every 30 seconds.
/// All anti-cheat evaluation is server-side; this service is telemetry-only.
class AnticheatLocal {
  AnticheatLocal._();
  static final AnticheatLocal instance = AnticheatLocal._();

  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  bool _mockDetected = false;

  void start() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flush());
  }

  void stop() {
    _flushTimer?.cancel();
    _flush(); // final flush on stop
  }

  /// Record one GPS sample. Call from the GPS stream.
  void record(Position position) {
    if (position.isMocked && !_mockDetected) {
      _mockDetected = true;
      _flushImmediate(isMockAlert: true);
    }

    _buffer.add({
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'is_mocked': position.isMocked,
      't': position.timestamp.millisecondsSinceEpoch,
    });
  }

  Future<void> _flushImmediate({required bool isMockAlert}) async {
    final samples = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    await _sendToEdgeFunction(samples, isMockAlert: isMockAlert);
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final samples = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    await _sendToEdgeFunction(samples, isMockAlert: false);
  }

  Future<void> _sendToEdgeFunction(
    List<Map<String, dynamic>> samples, {
    required bool isMockAlert,
  }) async {
    if (!SupabaseService.instance.isConnected) return;
    if (samples.isEmpty && !isMockAlert) return;

    try {
      await SupabaseService.instance.supabase.functions.invoke(
        SupabaseConfig.fnAnticheatScore,
        body: {
          'samples': samples,
          'is_mock_alert': isMockAlert,
        },
      );
    } catch (e) {
      debugPrint('[AnticheatLocal] flush error: $e');
    }
  }

  bool get mockLocationDetected => _mockDetected;
}
