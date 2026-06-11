import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_log_service.dart';
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
        playerId: p['user_id'] as String? ?? '',
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
/// Presence is only published to rivals while recording is active
/// (between setRecording(true) and setRecording(false)).
class RealtimePresenceService {
  RealtimePresenceService._();
  static final RealtimePresenceService instance = RealtimePresenceService._();

  RealtimeChannel? _channel;
  Timer? _broadcastTimer;
  LatLng? _currentPosition;

  final _controller =
      StreamController<List<PlayerPresence>>.broadcast();

  // Per-player position history buffer for the RunnerComet tail.
  // Updated on every _emitState() pass; cleared when a player goes stale or leaves.
  // Never persisted, never broadcast.
  final Map<String, List<PlayerPresence>> _playerHistory = {};
  static const int _kHistoryMaxEntries = 12;
  static const int _kHistoryMaxAgeSeconds = 60;

  Stream<List<PlayerPresence>> get playersStream => _controller.stream;

  /// Last known GPS position for this player. Null until first GPS fix.
  LatLng? get currentPosition => _currentPosition;

  bool _inited = false;
  String? _myPlayerId;
  String? _myDisplayName;
  String? _myColor;
  bool _isRecording = false;
  String? _colorHex;

  // Test seam: captures the last payload constructed by updatePosition/broadcast timer.
  Map<String, dynamic> _lastBroadcastPayload = const {};

  /// Returns the buffered position history for [playerId], oldest-first.
  /// Returns an empty list when no history exists yet (cold start, first emission).
  /// Filters out entries older than [_kHistoryMaxAgeSeconds] at read time so
  /// callers always receive fresh data regardless of when the buffer was last pruned.
  List<PlayerPresence> historyFor(String playerId) {
    final cutoff = DateTime.now().subtract(
      const Duration(seconds: _kHistoryMaxAgeSeconds),
    );
    return List.unmodifiable(
      (_playerHistory[playerId] ?? const <PlayerPresence>[])
          .where((e) => e.updatedAt.isAfter(cutoff))
          .toList(),
    );
  }

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
            ErrorLogService.logClientError(
              provider: 'RealtimePresenceService.init',
              error: error,
              stackTrace: StackTrace.current,
              retryCount: 0,
            );
            return;
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            // Channel is live but we publish nothing until setRecording(true).
          }
        });

    _startBroadcasting();
  }

  /// Update local position - broadcast will pick it up on next tick when recording.
  void updatePosition(LatLng position) {
    _currentPosition = position;
    // For the test seam: build the payload that would be broadcast.
    // This mirrors what _startBroadcasting() sends without actually
    // requiring an active channel (supports instanceForTesting()).
    _lastBroadcastPayload = {
      // Invariant: lat/lng only. Never include trace/track/polyline data here.
      // Rival comet tail is reconstructed client-side from a rolling buffer of
      // these single-point emissions (see _playerHistory). Adding track data
      // would leak the runner's full path to all subscribers.
      'user_id': _myPlayerId ?? '',
      'display_name': _myDisplayName ?? '?',
      'color': _myColor ?? '#FF7A00',
      'lat': position.latitude,
      'lng': position.longitude,
      't': DateTime.now().millisecondsSinceEpoch,
      'rec': _isRecording,
      'color_hex': _colorHex ?? _myColor ?? '#FF7A00',
    };
  }

  void setRecording(bool v) {
    final wasRecording = _isRecording;
    _isRecording = v;
    if (wasRecording && !v) {
      // Recording just stopped: drop our presence slot so rivals see leave.
      _untrackSafely();
    }
  }

  void setColorHex(String? v) => _colorHex = v;

  void _untrackSafely() {
    // Record that untrack was requested (test seam tracks intent, not result).
    _untrackCalled = true;
    final ch = _channel;
    if (ch == null) return;
    try {
      // untrack() is idempotent in the Supabase Realtime SDK; calling
      // before any track() is a no-op rather than an error.
      unawaited(ch.untrack());
    } catch (e) {
      debugPrint('[Presence] untrack failed: $e');
    }
  }

  void _startBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(kPresenceBroadcastInterval, (_) {
      if (!_isRecording) return; // Gate: only broadcast during active recording
      final pos = _currentPosition;
      if (pos == null || _channel == null || _myPlayerId == null) return;
      // Invariant: lat/lng only. Never include trace/track/polyline data here.
      // Rival comet tail is reconstructed client-side from a rolling buffer of
      // these single-point emissions (see _playerHistory). Adding track data
      // would leak the runner's full path to all subscribers.
      final payload = {
        'user_id': _myPlayerId!,
        'display_name': _myDisplayName ?? '?',
        'color': _myColor ?? '#FF7A00',
        'lat': pos.latitude,
        'lng': pos.longitude,
        't': DateTime.now().millisecondsSinceEpoch,
        'rec': true, // always true when published
        'color_hex': _colorHex ?? _myColor ?? '#FF7A00',
      };
      _lastBroadcastPayload = payload;
      _channel!.track(payload);
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
            (payload['user_id'] as String?) != _myPlayerId)
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
    _updateHistoryBuffer(fresh);
    _controller.add(fresh);
  }

  void _updateHistoryBuffer(List<PlayerPresence> fresh) {
    final now = DateTime.now();
    final freshIds = <String>{};
    for (final p in fresh) {
      freshIds.add(p.playerId);
      final list = _playerHistory.putIfAbsent(p.playerId, () => <PlayerPresence>[]);
      // Skip if the newest entry is the same timestamp (duplicate emission).
      if (list.isNotEmpty && list.last.updatedAt == p.updatedAt) continue;
      list.add(p);
      // Trim by length.
      while (list.length > _kHistoryMaxEntries) {
        list.removeAt(0);
      }
      // Trim by age.
      list.removeWhere(
        (e) => now.difference(e.updatedAt).inSeconds > _kHistoryMaxAgeSeconds,
      );
    }
    // Purge players no longer in the fresh set.
    _playerHistory.removeWhere((id, _) => !freshIds.contains(id));
  }

  Future<void> dispose() async {
    _broadcastTimer?.cancel();
    _playerHistory.clear();
    await _channel?.unsubscribe();
    await _controller.close();
  }

  // ── Test seams ─────────────────────────────────────────────────────────────

  /// Creates an isolated instance not backed by Supabase.
  /// For use in unit tests only.
  @visibleForTesting
  static RealtimePresenceService instanceForTesting() =>
      RealtimePresenceService._();

  @visibleForTesting
  bool get isRecordingForTesting => _isRecording;

  // Tracks whether _untrackSafely() has been called. Read via public getter below.
  bool _untrackCalled = false;

  @visibleForTesting
  bool get untrackCalledForTesting => _untrackCalled;

  @visibleForTesting
  void resetForTesting() {
    _isRecording = false;
    _untrackCalled = false;
    _currentPosition = null;
  }

  /// Injects a presence entry directly into the history buffer for testing.
  @visibleForTesting
  void injectPresence(String playerId, PlayerPresence presence) {
    final list = _playerHistory.putIfAbsent(playerId, () => []);
    list.add(presence);
    if (list.length > _kHistoryMaxEntries) list.removeAt(0);
  }

  /// Simulates a fresh player list emission, purging any absent player IDs.
  @visibleForTesting
  void injectFreshPlayerList(List<String> playerIds) {
    _playerHistory.removeWhere((k, _) => !playerIds.contains(k));
  }

  /// Clears all history. Call in tearDown to prevent state leaking between tests.
  @visibleForTesting
  void disposeForTesting() {
    _playerHistory.clear();
  }

  /// Returns the last payload that would have been broadcast via track().
  /// Used by tests to verify the payload schema contains no trace/track fields.
  /// Returns an empty map before [updatePosition] is called.
  @visibleForTesting
  Map<String, dynamic> captureLastBroadcastPayload() => _lastBroadcastPayload;
}
