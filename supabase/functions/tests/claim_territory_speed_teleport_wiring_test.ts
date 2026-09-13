// supabase/functions/tests/claim_territory_speed_teleport_wiring_test.ts
//
// R2 call-site wiring: handleClaimTerritoryRequest itself is not
// injectable (it builds its own Supabase client from env vars, no DI
// boundary - confirmed by grepping supabase/functions/tests/ for any
// existing caller: claim_territory_merge_wiring_test.ts,
// claim_territory_split_wiring_test.ts, claim_territory_dispute_timer_test.ts
// and claim_territory_shape_gate_flag_test.ts all mention
// handleClaimTerritoryRequest only in comments, none actually calls it end
// to end against a mocked client). Per design.md section 12.1 items 7-10,
// this is exactly the "confirm at implementation time... to avoid a
// duplicate harness" case - no such harness exists, so this file follows
// claim_territory_merge_wiring_test.ts's own established landmark-anchored
// source-inspection convention instead of fabricating a mock-client
// integration harness this codebase has no existing pattern for.
//
// KNOWN COVERAGE GAP (recorded per RED-Author's HIGH-tier process, not
// silently dropped): design.md item 10 (the coordinate-normalization
// boundary keeping alt/ts_ms out of persisted geom_json) cannot be proven
// executing without a genuine DI seam into handleClaimTerritoryRequest's
// zone-write path. The ordering assertion below is the closest structural
// proxy available pre-implementation; a true executing regression test for
// this specific case should be added once/if handleClaimTerritoryRequest
// grows an injectable database client (see claim_territory_merge_wiring_test.ts's
// own runSplitAndMerge precedent for what that seam would look like).
//
// Run: ~/.deno/bin/deno test --allow-all supabase/functions/tests/claim_territory_speed_teleport_wiring_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../claim_territory/handler.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

function findAnchor(src: string, marker: string, label: string): number {
  const idx = src.indexOf(marker);
  assert(idx >= 0, `Landmark not found: ${label} ("${marker}"). handler.ts's structure moved, or the fix has not landed yet - update this anchor once evaluateTrackTiming is wired in, do not delete the check.`);
  return idx;
}

Deno.test('R2 wiring: evaluateTrackTiming is called at all, anywhere in handler.ts', () => {
  const src = readSrc();
  assert(src.includes('evaluateTrackTiming('),
    'handleClaimTerritoryRequest must call the new evaluateTrackTiming gate somewhere - today it is entirely unwired, so every claim request skips the speed/teleport check regardless of what the pure function itself does. Reverting the call site (while keeping the function defined) makes this test fail again.');
});

Deno.test('R2 wiring: the single-track path calls evaluateTrackTiming after hasCorruptHop(coords), before the ring reaches ringsRaw', () => {
  const src = readSrc();
  // hasCorruptHop(coords) is the exact call-site literal quoted in design.md
  // section 7.2 for the singular-track path (handler.ts:634 at the SHA this
  // spec was written against).
  const hopIdx = findAnchor(src, 'hasCorruptHop(coords)', 'single-track hasCorruptHop call');
  const timingIdx = src.indexOf('evaluateTrackTiming(', hopIdx);
  assert(timingIdx > hopIdx,
    'evaluateTrackTiming must be called AFTER hasCorruptHop(coords) in the single-track path - today there is no such call at all after this point, so a teleporting single-track submission is never rejected by this gate. Reverting the call site placement (or removing it) fails this test again.');
});

Deno.test('R2 wiring: a failed timing gate short-circuits with reason threaded from the gate result, before zone evaluation', () => {
  const src = readSrc();
  // The exact response-construction literal proposed in design.md section
  // 7.2: `return ok({ result: 'failed', reason: timing.reason });` - the
  // specific shape that threads the gate's own reason through rather than
  // hardcoding a single string.
  assert(src.includes('reason: timing.reason'),
    'a failed evaluateTrackTiming result must produce a response whose reason field is the GATE\'S OWN reason (speed_violation or teleport), not a hardcoded or generic string. Today no such response construction exists at all. Reverting to a hardcoded reason (or removing the early return) fails this test again.');
});

Deno.test('R2 wiring: the multi-tracks path also calls evaluateTrackTiming per member ring', () => {
  const src = readSrc();
  const firstIdx = findAnchor(src, 'evaluateTrackTiming(', 'first evaluateTrackTiming call site');
  const secondIdx = src.indexOf('evaluateTrackTiming(', firstIdx + 'evaluateTrackTiming('.length);
  assert(secondIdx > firstIdx,
    'evaluateTrackTiming must be called at TWO distinct call sites: once for the single-track path and once per member of the multi-tracks path (mirroring the existing per-member hasCorruptHop pattern at handler.ts:592-598) - today there is zero call sites, so this also fails. Collapsing the multi-tracks path down to a single shared call site (or removing the per-member check) fails this test again.');
});

Deno.test('R2 wiring: a successful response threads speed_check: skipped_no_timestamps for the legacy no-timestamp path', () => {
  const src = readSrc();
  assert(src.includes("speed_check: 'skipped_no_timestamps'"),
    'the success-path response body must carry speed_check: \'skipped_no_timestamps\' when evaluateTrackTiming passed only because timestamps were absent (design.md section 7.3) - today this field does not exist anywhere in handler.ts. Removing this field (or never setting it) fails this test again.');
});

Deno.test('R2 wiring: evaluateTrackTiming is called before the coordinate-normalization boundary that strips alt/ts_ms for geom_json (structural proxy, see KNOWN COVERAGE GAP above)', () => {
  const src = readSrc();
  const timingIdx = findAnchor(src, 'evaluateTrackTiming(', 'evaluateTrackTiming call site');
  const geomIdx = findAnchor(src, 'p_geom_json', 'persisted geom_json write parameter (design.md section 7.2\'s verified write sites)');
  assert(timingIdx < geomIdx,
    'evaluateTrackTiming must run and short-circuit BEFORE any code path reaches a persisted geom_json write, so a teleporting/speed-violating claim never reaches zone storage. Today there is no evaluateTrackTiming call at all, so this ordering cannot hold. This is a structural proxy for the real requirement (alt/ts_ms must never appear in persisted geom_json) - see the KNOWN COVERAGE GAP note above for why a true executing test is deferred.');
});

Deno.test("R2: hasCorruptHop's doc comment is corrected to no longer claim this file owns no genuine speed/teleport check", () => {
  const src = readSrc();
  // Comments may be wrapped across multiple `//` lines - normalize away
  // comment markers and collapse whitespace so a line-wrap in the source
  // cannot make this substring match silently (and wrongly) fail to find
  // text that is actually present, verbatim, per requirements.md's own
  // quoted baseline ("Verified baselines" section).
  const normalized = src.replace(/\/\//g, ' ').replace(/\s+/g, ' ');
  assert(!normalized.includes('Real speed/teleport anti-cheat is owned by the separate anti-cheat pipeline, not by this gate'),
    'the stale doc comment (accurate before R2, false after) must be corrected in the same change per design.md section 7.4 - today it is still present verbatim, which is now a false claim about this file\'s own responsibilities once evaluateTrackTiming ships.');
});
