import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

class PlayerPresence {
  const PlayerPresence({
    required this.playerId,
    required this.displayName,
    required this.color,
    required this.position,
    required this.updatedAt,
  });

  final String playerId;
  final String displayName;
  final String color;
  final LatLng position;
  final DateTime updatedAt;

  factory PlayerPresence.fromPayload(Map<String, dynamic> p) =>
      PlayerPresence(
        playerId: p['player_id'] as String? ?? '',
        displayName: p['display_name'] as String? ?? '?',
        color: p['color'] as String? ?? '#FF7A00',
        position: LatLng(
          (p['lat'] as num? ?? 0).toDouble(),
          (p['lng'] as num? ?? 0).toDouble(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (p['t'] as int?) ?? 0,
        ),
      );
}

/// Broadcasts own GPS position at 1 Hz via Supabase Presence.
/// Other players' positions are emitted via [playersStream].
class RealtimePresenceService {
  RealtimePresenceService._();
  static final RealtimePresenceService instance = RealtimePresenceService._();

  RealtimeChannel? _channel;
  Timer? _broadcastTimer;
  LatLng? _currentPosition;

  final _controller =
      StreamController<List<PlayerPresence>>.broadcast();

  Stream<List<PlayerPresence>> get playersStream => _controller.stream;

  /// Last known GPS position for this player. Null until first GPS fix.
  LatLng? get currentPosition => _currentPosition;

  bool _inited = false;
  String? _myPlayerId;
  String? _myDisplayName;
  String? _myColor;

  /// Call once after auth to begin presence tracking.
  void init({
    required String playerId,
    required String displayName,
    required String color,
  }) {
    if (_inited) return;
    _inited = true;
    _myPlayerId = playerId;
    _myDisplayName = displayName;
    _myColor = color;

    _channel = SupabaseService.instance.supabase
        .channel(SupabaseConfig.channelPresence)
        .onPresenceSync((payload) => _emitState())
        .onPresenceJoin((payload) => _emitState())
        .onPresenceLeave((payload) => _emitState())
        .subscribe((status, error) async {
          if (error != null) {
            debugPrint('[Presence] subscribe error: $error');
            return;
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({
              'player_id': playerId,
              'display_name': displayName,
              'color': color,
              'lat': 0,
              'lng': 0,
              't': DateTime.now().millisecondsSinceEpoch,
            });
          }
        });

    _startBroadcasting();
  }

  /// Update local position — broadcast will pick it up on next tick.
  void updatePosition(LatLng position) {
    _currentPosition = position;
  }

  void _startBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final pos = _currentPosition;
      if (pos == null || _channel == null || _myPlayerId == null) return;
      _channel!.track({
        'player_id': _myPlayerId!,
        'display_name': _myDisplayName ?? '?',
        'color': _myColor ?? '#FF7A00',
        'lat': pos.latitude,
        'lng': pos.longitude,
        't': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _emitState() {
    if (_channel == null) return;
    // presenceState() returns List<SinglePresenceState>.
    // Each entry has .presences: List<Presence>, where Presence.payload
    // is the Map<String,dynamic> we passed to channel.track().
    final state = _channel!.presenceState();
    final others = state
        .expand((s) => s.presences.map((p) => p.payload))
        .where((payload) =>
            (payload['player_id'] as String?) != _myPlayerId)
        .map((payload) {
          try {
            return PlayerPresence.fromPayload(payload);
          } catch (_) {
            return null;
          }
        })
        .whereType<PlayerPresence>()
        .toList();
    _controller.add(others);
  }

  Future<void> dispose() async {
    _broadcastTimer?.cancel();
    await _channel?.unsubscribe();
    await _controller.close();
  }
}
