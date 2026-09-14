// supabase/functions/_shared/constants.ts
// Shared numeric constants for edge functions - single import location so
// every function that needs one of these values reads the same number
// instead of each function hand-rolling its own copy.

// Douglas-Peucker simplification epsilon (metres), applied to a captured
// claim ring before it is persisted as a zone's stored geometry - see
// geometry.ts's simplifyRingDouglasPeucker in this same directory.
//
// Must stay numerically identical to kDpSimplifyEpsilonM in
// lib/utils/runwar_constants.dart (the Dart side's own central constant) -
// the client simplifies before dispatch and the server re-simplifies the
// received ring idempotently with this same value, so an old client that
// has not yet picked up client-side simplification still yields simplified
// storage. If this value changes, change the Dart value too.
export const DP_SIMPLIFY_EPSILON_M = 10;

// Base hours of shield protection granted per point of a zone's current
// influence_level, at the moment a SHIELD grant is activated on that zone.
// Read once inside the activation transaction and used to write one
// absolute shield_expires_at; never recomputed later, so a zone leveling up
// mid-shield does not silently extend its own protection window.
//
// Currently 1.0, PROVISIONAL pending a game-balance pass: at level 1 this
// yields 1 hour (below the fixed 2 hour city-wide shield already granted by
// a CTF win, so that reward stays strictly better at low level); at the
// level cap of 15 it yields 15 hours, deliberately under 24 so an activated
// shield can never span two consecutive daily play sessions.
export const kShieldBaseHoursPerLevel = 1.0;

// Speed/teleport anti-cheat thresholds for claim_territory's evaluateTrackTiming
// gate (per-vertex timestamp check on a submitted claim ring). Reused verbatim
// from the existing anticheat_score reputation pipeline's own inline numbers
// (anticheat_score/index.ts) for cross-pipeline consistency - anticheat_score
// itself is not changed to import these in this pass, it keeps its own inline
// literals.
//
// Cross-referenced with lib/utils/runwar_constants.dart's mirror constants -
// the client does not run this check itself (it is server-authoritative), but
// the values still live here per this codebase's own convention of keeping
// cross-referenced numbers in one shared file even when only one side reads
// them.
export const kMaxSustainedSpeedMps = 12.0;
export const kTeleportDistanceM = 500;
export const kTeleportMaxElapsedS = 5;
