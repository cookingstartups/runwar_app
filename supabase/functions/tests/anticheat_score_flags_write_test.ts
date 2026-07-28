// supabase/functions/tests/anticheat_score_flags_write_test.ts
//
// Pass 1 of the anti-cheat pipeline fix: anticheat_score's writes redirect
// from the nonexistent anticheat_reports table to the live anticheat_flags
// table, one row per fired rule, with the batch's severity carried in the
// details jsonb column (there is no live severity column). Source inspection
// is used because anticheat_score is a Deno.serve handler with no injectable
// database client, matching this repo's existing convention for edge
// functions without a local Postgres harness.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_flags_write_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC_PATH = new URL('../anticheat_score/index.ts', import.meta.url);

function readSrc(): string {
  return Deno.readTextFileSync(SRC_PATH);
}

Deno.test('the function no longer inserts into the nonexistent anticheat_reports table', () => {
  const src = readSrc();
  assertFalse(/from\(\s*['"]anticheat_reports['"]\s*\)/.test(src),
    'anticheat_reports does not exist live - every reference to it must be removed, not just the insert');
});

Deno.test('a fired batch inserts one anticheat_flags row per rule name present in flags', () => {
  const src = readSrc();
  assert(src.includes("from('anticheat_flags')") || src.includes('from("anticheat_flags")'),
    'must insert into the live anticheat_flags table');
  assert(/flags\.map\(/.test(src),
    'must build one row per fired rule from the flags array, not a single combined row');
});

Deno.test('each anticheat_flags row carries the batch score in details, not a nonexistent severity column', () => {
  const src = readSrc();
  assert(/details\s*:\s*\{[^}]*severity/i.test(src),
    'the batch score must be written into the details jsonb column as its severity field');
  assertFalse(/\bseverity\s*:\s*score\b/.test(src),
    'must not assign a bare severity column - anticheat_flags has no such column live');
});

Deno.test('no anticheat_flags insert is attempted when zero rules fire in the batch', () => {
  const src = readSrc();
  assert(/if\s*\(\s*flag[A-Za-z]*\.length\s*>\s*0\s*\)/.test(src),
    'the anticheat_flags insert must be guarded so a batch with an empty flags array performs no insert call');
});
