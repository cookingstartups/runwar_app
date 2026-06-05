import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

const Duration kPresenceBroadcastInterval = Duration(seconds: 5);
const Duration kPresenceStaleTtl = Duration(seconds: 15);

class PlayerPresence {
  const PlayerPresence({
    required this.playerId,
    required this.displayName,
    required this.color,
    required this.position,
    required this.updatedAt,
    this.isRecording = false,
    this.colorHex,
  });

  final String playerId;
  final String displayName;
  final String color;
  final LatLng position;
  final DateTime updatedAt;
  final bool isRecording;
  final String? colorHex;

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
        isRecording: (p['rec'] as bool?) ?? false,
        colorHex: p['color_hex'] as String?,
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
  bool _isRecording = false;
  String? _colorHex;

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

  void setRecording(bool v) => _isRecording = v;
  void setColorHex(String? v) => _colorHex = v;

  void _startBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(kPresenceBroadcastInterval, (_) {
      final pos = _currentPosition;
      if (pos == null || _channel == null || _myPlayerId == null) return;
      _channel!.track({
        'player_id': _myPlayerId!,
        'display_name': _myDisplayName ?? '?',
        'color': _myColor ?? '#FF7A00',
        'lat': pos.latitude,
        'lng': pos.longitude,
        't': DateTime.now().millisecondsSinceEpoch,
        'rec': _isRecording,
        'color_hex': _colorHex ?? _myColor ?? '#FF7A00',
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
    final fresh = others
        .where(
          (p) => DateTime.now().difference(p.updatedAt) <= kPresenceStaleTtl,
        )
        .toList();
    _controller.add(fresh);
  }

  Future<void> dispose() async {
    _broadcastTimer?.cancel();
    await _channel?.unsubscribe();
    await _controller.close();
  }
}
