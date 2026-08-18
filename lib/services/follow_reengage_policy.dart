/// Pure re-engage predicate for run-session camera follow (rw_app-T0629).
/// Locked thresholds: 5 minutes elapsed AND more than 100 m traveled from
/// the suspend-time reference position, both required.
///
/// Signature-only stub for the RED phase - the body is intentionally
/// unimplemented so behavioral tests fail for the right reason instead of
/// failing to compile.
bool shouldReengageFollow({
  required Duration elapsed,
  required double distanceMeters,
}) {
  throw UnimplementedError();
}
