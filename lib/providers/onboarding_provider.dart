import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/profile_service.dart';

class OnboardingState {
  const OnboardingState({
    this.username = '',
    this.city = 'Valencia',
    this.color = '#FF7A00',
    this.step = 0,
    this.isLoading = false,
    this.error,
  });

  final String username;
  final String city;
  final String color;
  final int step;
  final bool isLoading;
  final String? error;

  OnboardingState copyWith({
    String? username,
    String? city,
    String? color,
    int? step,
    bool? isLoading,
    Object? error = _sentinel,
  }) =>
      OnboardingState(
        username: username ?? this.username,
        city: city ?? this.city,
        color: color ?? this.color,
        step: step ?? this.step,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState());

  /// Updates username and advances step to 1 (step = city picker).
  /// Call only after validating the value at the UI layer.
  void setUsername(String v) {
    state = state.copyWith(username: v, step: 1, error: null);
  }

  /// Updates city and advances step to 2 (step = color picker).
  /// Call only after validating the value at the UI layer.
  void setCity(String v) {
    state = state.copyWith(city: v, step: 2, error: null);
  }

  /// Updates color in-memory only; does NOT advance step.
  void setColor(String v) {
    state = state.copyWith(color: v, error: null);
  }

  /// Persists all three fields in one ProfileService.updateProfile call.
  /// Sets isLoading during the call; sets error on failure.
  /// POC-013 (main.dart) owns route re-evaluation after this succeeds.
  Future<void> submit(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await ProfileService.instance.updateProfile(
        userId,
        username: state.username,
        city: state.city,
        color: state.color,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not save profile: $e',
      );
    }
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
        (ref) => OnboardingNotifier());
