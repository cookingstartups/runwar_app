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

// Minimum area (sqm) a split-off remainder fragment must clear when a
// re-run retraces part of a same-level-fused zone's own edge (see
// computeZoneSplit in supabase/functions/claim_territory/merge_geometry.ts).
// This gate is enforced server-side only, in claim_territory/handler.ts -
// the split decision needs the existing zone's stored geometry, which the
// client does not hold. This client-side copy exists purely as a documented
// numeric-parity reference (and a future display value), not a live gate;
// it performs no check on its own. Must stay numerically equal to the
// server-side kMinSplitFragmentAreaSqm in claim_territory/handler.ts.
const double kMinSplitFragmentAreaSqm = 375.0;

// Maximum number of session-elapsed-deferred loop closures held at once.
// SPEC-0143.
const int kMaxDeferredCrossings = 8;

// Upper bound (seconds) on a plausible session elapsed value. A computed
// elapsed above this, or below zero, means the two sides of the subtraction
// are not on the same timeline (a mis-seeded simulation start, or a skewed
// device clock) and the value must not be trusted. SPEC-0143.
const int kMaxPlausibleSessionElapsedSec = 86400; // 24 h

// Feature flag controlling enforcement of the three SHAPE gates on a
// captured auto-claim polygon: bounding-box diagonal (kMinCapturedAreaDiagonalM
// above), compactness (kMinCapturedAreaCompactness above), and loop path
// length (kMinCapturedPathLengthM above). Read by RunRecorderService
// (_scanForAutoClaim and the crash-resume rescan path in
// _rescanRehydratedTrack). Default OFF: a captured loop is gated on the
// area floor only, so a loop that legitimately extends an already-owned
// zone but is a thin wedge on its own is no longer rejected before it ever
// reaches the merge step. The three shape checks and their reasoning
// comments stay in place, not deleted - flipping this back to true is a
// fully reversible one-line change that restores exactly today's
// enforcement. This is a temporary loosening, not a permanent removal.
//
// Must stay numerically and behaviourally identical to kEnforceShapeGates
// in supabase/functions/claim_territory/handler.ts - the two are enforced
// independently (client gates before dispatch, server gates again on
// receipt) and a mismatch lets a claim pass one side and fail the other.
// If this value changes, change the server value too.
const bool kEnforceShapeGates = false;

// Minimum number of a detected loop closure's trail segments that must lie
// outside every span already consumed by a dispatched claim in this
// session, checked before the area floor in RunRecorderService's
// auto-claim scan (the consumed-span dedup gate). A detected closure whose
// candidate span [i..k] has fewer than this many segments outside every
// already-consumed span is silently skipped, not claimed.
//
// This admits a genuinely new loop that shares corridor with already-
// claimed ground - a big excursion loop that closes against early trail
// history a small loop already consumed - while blocking a near-duplicate
// re-crossing of a loop already claimed - the runner re-walking the same
// corridor and closing an almost-identical loop a few fixes later.
//
// At the 50 m point spacing (kTrackPointSpacingM), 4 segments is about
// 200 m of genuinely new trail.
const int kMinNewLoopTrailSegments = 4;
