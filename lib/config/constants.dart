// App-wide identity and UI constants.
//
// Gameplay constants (credits, decay rates, etc.) remain in game_config.dart.
// This file owns profile identity and unlock-gate configuration.

/// Territory threshold (km²) required to unlock username editing.
const double kUsernameUnlockKm2 = 1.0;

/// Login streak (days) required to unlock username editing.
const int kUsernameUnlockStreakDays = 7;

/// Canonical player color palette. Single source of truth — referenced by
/// AuthService.signUp (random pick), ProfileService._colorForId
/// (deterministic fallback), and ProfileEditScreen (color picker).
const List<String> kPlayerColors = [
  '#FF6B35', // orange
  '#00A8CC', // teal
  '#5CB85C', // green
  '#9B59B6', // purple
  '#E74C3C', // red
  '#3498DB', // blue
  '#27AE60', // emerald
  '#F39C12', // amber
  '#FFD23F', // yellow
  '#FF61E6', // magenta
];
