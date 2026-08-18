/// Pure re-engage predicate for run-session camera follow (rw_app-T0629).
/// Locked thresholds: 5 minutes elapsed AND more than 100 m traveled from
/// the suspend-time reference position, both required.
const Duration kFollowReengageMinElapsed = Duration(minutes: 5);
const double kFollowReengageMinDistanceMeters = 100.0;

/// Boundary convention: elapsed is INCLUSIVE at exactly 5 minutes ("at least
/// 5 minutes"), distance is EXCLUSIVE at exactly 100 m ("more than 100 m").
bool shouldReengageFollow({
  required Duration elapsed,
  required double distanceMeters,
}) {
  return elapsed >= kFollowReengageMinElapsed &&
      distanceMeters > kFollowReengageMinDistanceMeters;
}
