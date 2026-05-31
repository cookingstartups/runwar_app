// lib/providers/superpowers/superpower_runtime_provider.dart
//
// Provider for SuperpowerRuntime — architect addition (design.md §5.2).
// MapScreen calls ref.read(superpowerRuntimeProvider).bind(userId) in initState.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/superpower_runtime.dart';
import '../repositories.dart';

/// SuperpowerRuntime for the session.
/// ref.onDispose cancels the grants subscription.
/// MapScreen must call .bind(playerId) after login to start streaming.
final superpowerRuntimeProvider = Provider<SuperpowerRuntime>((ref) {
  final runtime = SuperpowerRuntime(repo: ref.read(superpowersRepoProvider));
  ref.onDispose(runtime.dispose);
  return runtime;
});
