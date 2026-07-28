// supabase/functions/tests/anticheat_score_challenges_insert_test.ts
//
// Pass 1's corrected challenges insert: status must be pending (the live
// CHECK constraint rejects 'open'), challenge_type must be set, and the
// phantom anticheat_report_id/trigger columns must be dropped. A duplicate
// pending challenge for the same user hits the live one-pending-per-user
// unique index and must be caught as an expected, non-fatal outcome. Source
// inspection, same convention as the sibling tests in this directory.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_challenges_insert_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readSrc(): string {
  return Deno.readTextFileSync(new URL('../anticheat_score/index.ts', import.meta.url));
}

function challengesInsertWindow(src: string): string {
  const idx = src.search(/from\(\s*['"]challenges['"]\s*\)\s*\.insert/);
  assert(idx >= 0, 'expected a challenges insert to exist');
  return src.slice(idx, idx + 500);
}

Deno.test('the challenges insert sets status to pending, never the illegal open value', () => {
  const src = readSrc();
  const w = challengesInsertWindow(src);
  assert(/status\s*:\s*['"]pending['"]/.test(w), 'status must be pending - the live CHECK constraint rejects open');
  assertFalse(/status\s*:\s*['"]open['"]/.test(w), 'status must never be open');
});

Deno.test('the challenges insert sets challenge_type and drops the phantom anticheat_report_id/trigger fields', () => {
  const src = readSrc();
  const w = challengesInsertWindow(src);
  assert(/challenge_type\s*:\s*['"]motion_capture['"]/.test(w), 'challenge_type must be set (NOT NULL live column)');
  assertFalse(/anticheat_report_id/.test(w), 'anticheat_report_id does not exist live and must not appear in the payload');
  assertFalse(/\btrigger\s*:/.test(w), 'a bare trigger field does not exist live and must not appear in the payload');
});

Deno.test('a unique-violation on a duplicate pending challenge is caught by its specific error code, not surfaced as a failure', () => {
  const src = readSrc();
  assert(src.includes("'23505'"), 'must check for the unique-violation error code 23505');
  const codeIdx = src.indexOf("'23505'");
  const window = src.slice(Math.max(0, codeIdx - 200), codeIdx + 200);
  assertFalse(/writeErrors\.push/.test(window),
    'the 23505 branch must not push into the general write-errors surface - it is an expected outcome, not a failure');
});

Deno.test('a non-23505 challenges insert error still goes through normal error surfacing', () => {
  const src = readSrc();
  const w = challengesInsertWindow(src);
  assert(/else\s*\{/.test(w) || /else\s+if/.test(w),
    'a distinct branch must handle any other error code (not silently ignored like the 23505 case)');
});
