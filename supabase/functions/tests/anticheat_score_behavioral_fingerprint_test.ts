// supabase/functions/tests/anticheat_score_behavioral_fingerprint_test.ts
//
// Pass 1 net-new write plus the corrected repeated_gps_pattern read path.
// The read against behavioral_fingerprints must run BEFORE this batch's own
// fingerprint row is written - reversed ordering makes every first-time
// gps_pattern_hash submission self-match and false-positive. Source
// inspection, same convention as the sibling tests in this directory.
//
// Run: npx deno test supabase/functions/tests/anticheat_score_behavioral_fingerprint_test.ts

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';

function readSrc(): string {
  return Deno.readTextFileSync(new URL('../anticheat_score/index.ts', import.meta.url));
}

Deno.test('a behavioral_fingerprints row is inserted with the live column shape', () => {
  const src = readSrc();
  const insertIdx = src.search(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.insert/);
  assert(insertIdx >= 0, 'must insert into behavioral_fingerprints');
  const window = src.slice(insertIdx, insertIdx + 350);
  for (const col of ['user_id', 'run_id', 'gyro_summary', 'gps_pattern_hash', 'sample_count', 'recorded_at']) {
    assert(window.includes(col), `behavioral_fingerprints insert must set ${col}`);
  }
});

Deno.test('the behavioral_fingerprints insert is guarded so a batch with neither gyro nor gps data writes nothing', () => {
  const src = readSrc();
  assert(/if\s*\(\s*body\.gyro_summary\s*\|\|\s*body\.gps_pattern_hash\s*\)/.test(src),
    'the insert must only run when gyro_summary or gps_pattern_hash is present on the batch');
});

Deno.test('the repeated_gps_pattern rule reads from behavioral_fingerprints, never anticheat_reports', () => {
  const src = readSrc();
  assert(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.select/.test(src),
    'the repeated-pattern lookup must query behavioral_fingerprints');
  assertFalse(/from\(\s*['"]anticheat_reports['"]\s*\)\s*\.select/.test(src),
    'no select against anticheat_reports may remain - that table does not exist live');
});

Deno.test('the fingerprint read happens before this batch\'s own fingerprint row is written', () => {
  const src = readSrc();
  const readIdx = src.search(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.select/);
  const writeIdx = src.search(/from\(\s*['"]behavioral_fingerprints['"]\s*\)\s*\.insert/);
  assert(readIdx >= 0 && writeIdx >= 0, 'both the read and the write against behavioral_fingerprints must exist');
  assert(readIdx < writeIdx,
    'reading for a prior match must happen before this batch writes its own row, or every first-time submission self-matches and false-positives');
});
