// lib/services/superpower_runtime.dart
//
// SuperpowerRuntime — derives client-visible runtime flags from active grants.
// Phase 2 design.md §4.1 + §4.2.
//
// CONTRACT:
//   - Other services / widgets read boolean flags (rushArmed, ghostArmed, etc.)
//     — they MUST NOT inspect the raw grant list directly.
//   - bind(playerId) may be called multiple times (e.g. re-login). The previous
//     subscription is cancelled before a new one is attached.
//   - dispose() is idempotent. Called by Riverpod via ref.onDispose().
//   - No supabase_flutter import — depends on SuperpowersRepository only.

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'database/superpowers_repository.dart';

/// Derives and caches superpower runtime flags from the active-grants stream.
///
/// Instantiated once per session via [superpowerRuntimeProvider].
/// Call [bind(playerId)] after login to start the grant subscription.
class SuperpowerRuntime {
  SuperpowerRuntime({required SuperpowersRepository repo}) : _repo = repo;

  final SuperpowersRepository _repo;

  StreamSubscription<List<SuperpowerGrant>>? _sub;

  bool _rushArmed = false;
  bool _ghostArmed = false;
  DateTime? _shieldUntil;
  DateTime? _overclockUntil;
  String? _playerId;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Bind to [playerId]'s active-grants stream.
  /// Cancels any previous subscription first — safe to call on re-login.
  void bind(String playerId) {
    _playerId = playerId;
    _sub?.cancel();
    _sub = _repo.watchActiveGrants(playerId).listen(
      _recompute,
      onError: (Object e) {
        debugPrint('[SuperpowerRuntime] grants stream error: $e');
      },
    );
  }

  bool get rushArmed => _rushArmed;
  bool get ghostArmed => _ghostArmed;
  bool get shieldActive =>
      _shieldUntil != null && _shieldUntil!.isAfter(DateTime.now());
  bool get overclockActive =>
      _overclockUntil != null && _overclockUntil!.isAfter(DateTime.now());
  DateTime? get shieldUntil => _shieldUntil;
  DateTime? get overclockUntil => _overclockUntil;
  String? get currentPlayerId => _playerId;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _recompute(List<SuperpowerGrant> grants) {
    _rushArmed =
        grants.any((g) => g.powerType == 'RUSH' && g.chargesRemaining > 0);
    _ghostArmed =
        grants.any((g) => g.powerType == 'GHOST_RUN' && g.chargesRemaining > 0);
    _shieldUntil = _latestExpiry(grants, 'SHIELD');
    _overclockUntil = _latestExpiry(grants, 'OVERCLOCK');
  }

  DateTime? _latestExpiry(List<SuperpowerGrant> grants, String powerType) =>
      grants
          .where((g) =>
              g.powerType == powerType &&
              g.expiresAt != null &&
              g.chargesRemaining > 0)
          .map((g) => g.expiresAt!)
          .fold<DateTime?>(
            null,
            (a, b) => a == null || b.isAfter(a) ? b : a,
          );
}
