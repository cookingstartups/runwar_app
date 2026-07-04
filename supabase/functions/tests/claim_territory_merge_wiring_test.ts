// supabase/functions/tests/claim_territory_merge_wiring_test.ts
//
// RED phase - R2-AC1 invariant (never merge across owners/cities), R2's
// disputed-exclusion edge case, and Q2's oldest-survivor ordering. These are
// source-inspection checks against index.ts's call-site wiring (query scope,
// guard conditions) rather than the pure geometry algorithm covered by
// claim_territory_merge_test.ts - the DB query filters themselves are only
// meaningfully verifiable by reading the actual Supabase query construction,
// not by a mocked client (which would just echo back whatever the test
// asserts). This mirrors the Dart source-inspection precedent in
// test/connectivity_gate_outbox_test.dart.
//
// Run: npx deno test supabase/functions/tests/claim_territory_merge_wiring_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../claim_territory/index.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

Deno.test('R2-AC1 invariant: the merge candidate query scopes to owner_id AND city', () => {
  const src = readSrc();
  assert(src.includes("eq('owner_id'"),
    "The merge query must filter .eq('owner_id', playerId) so merges never cross owners");
  assert(src.includes("eq('city'"),
    "The merge query must filter .eq('city', city) so merges never cross cities");
});

Deno.test('Q2: merge candidates are ordered oldest-first so the surviving id is well-defined', () => {
  const src = readSrc();
  assert(src.includes("order('created_at'"),
    'The merge query must order by created_at so "oldest survives" is well-defined, not query-order-dependent');
});

Deno.test('R2 edge case: merge never runs for a disputed outcome', () => {
  const src = readSrc();
  assert(src.includes('mergeAdjacentZones') || src.includes('computeZoneMerges'),
    'index.ts must call the merge routine for claimed/conquered outcomes');
  const mergeCallIdx = src.search(/mergeAdjacentZones|computeZoneMerges/);
  assert(mergeCallIdx >= 0);
  const disputedGuardIdx = src.lastIndexOf('disputedId', mergeCallIdx);
  assert(disputedGuardIdx >= 0 && disputedGuardIdx < mergeCallIdx,
    'The merge call must be guarded so it never runs when this claim resolved to disputed (e.g. `if (!disputedId)`)');
});

Deno.test('R2 response contract: claimed/conquered responses expose merged, absorbed_zone_ids, zone_geom_json', () => {
  const src = readSrc();
  assert(src.includes('merged'), 'Response must include the new `merged` boolean field');
  assert(src.includes('absorbed_zone_ids'), 'Response must include the new `absorbed_zone_ids` field');
  assert(src.includes('zone_geom_json'), 'Response must include the new `zone_geom_json` field');
});

Deno.test('Unification keeps no history: absorbed zone ids are passed to the atomic merge RPC for deletion, not lineage-tracked', () => {
  const src = readSrc();
  assert(src.includes("supabase.rpc('apply_zone_merge'"),
    'The merge path must delete absorbed rows outright (via the atomic apply_zone_merge RPC), not lineage-track them');
  assert(src.includes('p_absorbed_ids: uniqueAbsorbedIds'),
    'The absorbed zone ids must be passed to apply_zone_merge so the RPC deletes them in the same transaction as the survivor write');
  assert(!src.includes('parent_id'),
    'No parent_id lineage write is permitted - unification keeps no history, exactly one row survives');
});

Deno.test('Unification takes the MAX influence_level across the merged group (never summed, never a free level-up)', () => {
  const src = readSrc();
  assert(src.includes('survivorInfluenceLevel') && src.includes('p_influence_level: survivorInfluenceLevel'),
    'The apply_zone_merge RPC call must be given influence_level aggregated as the MAX across the merged group');
  const reduceIdx = src.indexOf('const survivorInfluenceLevel');
  assert(reduceIdx >= 0, 'survivorInfluenceLevel must be computed, not hardcoded');
  const reduceSnippet = src.slice(reduceIdx, reduceIdx + 200);
  assert(reduceSnippet.includes('Math.max'),
    'influence_level aggregation must take the MAX across group members, never a sum or average (merging grants no free fortification level)');
  assert(!src.includes('influence_level: survivorInfluence,'),
    'influence_level must never be assigned the summed influence value');
});

Deno.test('Unification applies the survivor UPDATE and absorbed DELETEs atomically via the apply_zone_merge RPC, not step-wise table writes', () => {
  const src = readSrc();
  const groupBlockStart = src.indexOf('if (group) {');
  assert(groupBlockStart >= 0, 'The merge application block (if (group) {...}) must exist');
  const groupBlockEnd = src.indexOf('if (conqueredId)', groupBlockStart);
  assert(groupBlockEnd > groupBlockStart, 'The merge application block must end before the response-building section');
  const groupBlock = src.slice(groupBlockStart, groupBlockEnd);

  assert(groupBlock.includes("supabase.rpc('apply_zone_merge'"),
    'The merge application block must call the apply_zone_merge RPC so the survivor write and absorbed deletes are one transaction');
  assert(!groupBlock.includes("from('zones').update("),
    'The merge application block must not issue a separate step-wise UPDATE outside the atomic RPC');
  assert(!groupBlock.includes("from('zones').delete("),
    'The merge application block must not issue separate step-wise DELETEs outside the atomic RPC');
  assert(groupBlock.includes('mergeErr') && groupBlock.includes('return err('),
    'A failure from the apply_zone_merge RPC must be surfaced as an error response, not swallowed silently');
});

Deno.test('Unification aggregates additive fields into the survivor', () => {
  const src = readSrc();
  assert(src.includes('survivorInfluence') && src.includes('influence: survivorInfluence'),
    'The survivor row update must aggregate influence (sum across the merged group), not just copy one member\'s value');
});

Deno.test('Unification sums credits_earned across the merged group', () => {
  const src = readSrc();
  assert(src.includes('survivorCreditsEarned') && src.includes('credits_earned: survivorCreditsEarned'),
    'The survivor row update must aggregate credits_earned (sum across the merged group)');
  const reduceIdx = src.indexOf('const survivorCreditsEarned');
  assert(reduceIdx >= 0, 'survivorCreditsEarned must be computed, not hardcoded');
  const reduceSnippet = src.slice(reduceIdx, reduceIdx + 200);
  assert(reduceSnippet.includes('.reduce'),
    'credits_earned aggregation must sum group members via reduce, not copy a single value');
});

Deno.test('Unification takes the max last_active_at across the merged group', () => {
  const src = readSrc();
  assert(src.includes('survivorLastActiveAt') && src.includes('last_active_at: survivorLastActiveAt'),
    'The survivor row update must aggregate last_active_at (max across the merged group)');
  const reduceIdx = src.indexOf('const survivorLastActiveAt');
  assert(reduceIdx >= 0, 'survivorLastActiveAt must be computed, not hardcoded');
  const reduceSnippet = src.slice(reduceIdx, reduceIdx + 300);
  assert(reduceSnippet.includes('.reduce'),
    'last_active_at aggregation must scan group members for the max value, not copy a single member\'s value');
});

Deno.test('Unification recomputes area_m2 from the merged geometry instead of summing source areas', () => {
  const src = readSrc();
  assert(src.includes("import { area as turfArea } from 'https://esm.sh/@turf/area@7';"),
    'index.ts must import turf area to recompute area_m2 from the merged geometry');
  assert(src.includes('survivorAreaM2') && src.includes('area_m2: survivorAreaM2'),
    'The survivor row update must write area_m2 recomputed from the merged geometry');
  assert(src.includes('turfArea(group.geometry)'),
    'area_m2 must be recomputed via turfArea(group.geometry) on the MERGED geometry, not derived by summing source zone areas');
  assert(!/area_m2.*\breduce\(/.test(src) && !src.includes('sum + (areaM2') && !src.includes('sum, id) => sum + (area'),
    'area_m2 must never be computed by summing source zone areas - overlapping zones would double count');
});

Deno.test('Unification updates shield_active/shield_expires_at using ANY-active / max-expiry semantics', () => {
  const src = readSrc();
  assert(src.includes('anyShieldActive') && src.includes('shield_active: anyShieldActive'),
    'The survivor row update must set shield_active to true if ANY group member has an active shield');
  assert(src.includes('survivorShieldExpiresAt') && src.includes('shield_expires_at: survivorShieldExpiresAt'),
    'The survivor row update must aggregate shield_expires_at from the merged group');
  const someIdx = src.indexOf('groupIds.some((id) => shieldActiveById.get(id)');
  assert(someIdx >= 0,
    'shield_active must be computed via .some() across every member of the merged group, not copied from the survivor alone');
});
