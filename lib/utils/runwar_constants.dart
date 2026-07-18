// lib/utils/runwar_constants.dart
//
// Unified gameplay proximity constants. Single source of truth for any
// "is the player close enough to X" check across the app.
//
// Geometric correctness: stored vertices are >= kTrackPointSpacingM apart.
// A kProximityTriggerM radius covers a half-segment of 25 m on each side,
// so every point on the trail is within range of at least one stored vertex.
// Zero dead-zone for the 10-49 m band.

const double kProximityTriggerM = 25.0;
const double kTrackPointSpacingM = 50.0;
const double kGeolocatorDistanceFilterM = 25.0;

// Minimum number of trail points that must separate a candidate
// vertex-proximity closure (see detectSelfIntersection in lasso.dart) from the
// current position. Guards against the fallback firing on ordinary
// consecutive fixes that merely happen to pass close to an old vertex without
// enclosing a real loop.
const int kMinProximityClosureTrailPoints = 4;

// Minimum bounding-box diagonal (metres) of the candidate proximity-closure
// polygon. A genuine city-block-scale loop comfortably clears this; a
// spurious closure between a handful of nearby fixes does not.
const double kMinProximityClosureDiagonalM = 50.0;

// Tester-only run replay simulation. Divides every real inter-fix delay by
// this factor when the operator picks accelerated timing, so a run recorded
// over tens of real minutes plays back in a few minutes on-device while
// keeping the fixes in their original relative order and spacing. Named so
// the multiplier is a single, discoverable knob rather than a magic number
// scattered across the replay driver.
const double kSimulationAccelerationMultiplier = 12.0;

// Hard floor and ceiling on the delay between two simulated fixes, applied
// after the acceleration multiplier. Keeps degenerate fixture gaps (a fix
// captured a few seconds after the previous one, or a multi-minute gap while
// the original device lost a GPS lock) from turning into either an
// instantaneous jump or an unreasonably long stall during a replay the
// operator is actively watching.
const int kSimulationMinFixDelayMs = 120;
const int kSimulationMaxFixDelayMs = 4000;
