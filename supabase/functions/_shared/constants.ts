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
