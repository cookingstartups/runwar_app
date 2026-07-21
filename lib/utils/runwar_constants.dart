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

// Minimum bounding-box diagonal (metres) of a captured auto-claim polygon,
// checked alongside kMinCapturedAreaSqm-equivalent area floor in
// RunRecorderService (client) and claim_territory (server). Rejects thin
// slivers that clear the area floor only because they are long and narrow,
// not because they enclose a real block-scale loop. Same reasoning as
// kMinProximityClosureDiagonalM above, generalised to the main auto-claim
// path rather than only the vertex-proximity fallback.
//
// Derived from a single observed live run (n=1): the one genuine loop
// closure measured about 24 972 sqm with a diagonal far above this; every
// spurious closure logged in the same run measured 0.4-40.8 sqm and never
// approached a real block-scale extent. 30 m sits comfortably below a real
// loop's diagonal while still rejecting degenerate slivers.
const double kMinCapturedAreaDiagonalM = 30.0;

// Minimum compactness ratio (area_sqm / diagonal_m^2) an auto-claim polygon
// must clear, checked alongside the area and diagonal floors above. The
// diagonal floor alone does not catch a long thin sliver that has enough
// area and enough diagonal to pass both checks individually - a perfect
// square scores 0.5, a 1:4 rectangle scores about 0.19, a needle-thin shape
// scores near zero. 0.15 still admits the elongated rectangular loops real
// street grids naturally produce (e.g. down one street, back along a
// parallel one), so it is deliberately not set any higher.
const double kMinCapturedAreaCompactness = 0.15;

// Minimum distance (metres) actually travelled along the trail to close an
// auto-claim loop, measured with trackDistanceM over the captured polygon's
// own vertices. Unlike area or diagonal, path length cannot be gamed by
// shape alone - it requires the phone to have physically moved that far.
// 150 m in player terms is well under a single lap of a real city block.
const double kMinCapturedPathLengthM = 150.0;

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

// Maximum number of session-elapsed-deferred loop closures held at once.
// SPEC-0143.
const int kMaxDeferredCrossings = 8;

// Upper bound (seconds) on a plausible session elapsed value. A computed
// elapsed above this, or below zero, means the two sides of the subtraction
// are not on the same timeline (a mis-seeded simulation start, or a skewed
// device clock) and the value must not be trusted. SPEC-0143.
const int kMaxPlausibleSessionElapsedSec = 86400; // 24 h
