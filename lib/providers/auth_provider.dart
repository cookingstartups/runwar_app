import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  final Map<String, dynamic>? user;
  final bool isLoading;
  final String? error;

  AuthState copyWith({
    Object? user = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
  }) =>
      AuthState(
        user: identical(user, _sentinel) ? this.user : user as Map<String, dynamic>?,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(AuthService authService)
      : _authService = authService,
        super(AuthState(user: authService.getCurrentUser()));

  final AuthService _authService;

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.signIn(email, password);
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid email or password',
        );
      } else {
        state = state.copyWith(isLoading: false, user: user, error: null);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.signUp(email, password);
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'An account with this email already exists',
        );
      } else {
        state = state.copyWith(isLoading: false, user: user, error: null);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.signInWithGoogle();
      if (user == null) {
        // User cancelled the picker — silently reset loading.
        state = state.copyWith(isLoading: false, error: null);
      } else {
        state = state.copyWith(isLoading: false, user: user, error: null);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> redeemCode(String code, String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _authService.redeemTesterCode(code, userId);
      if (success) {
        // Refresh current user so invited_at is treated as set.
        final updated = Map<String, dynamic>.from(state.user ?? {});
        updated['invited_at'] = DateTime.now().toUtc().toIso8601String();
        state = state.copyWith(isLoading: false, user: updated, error: null);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid or already used code',
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, error: null);
    await _authService.signOut();
    state = const AuthState();
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>(
        (ref) => AuthNotifier(AuthService.instance));
