// supabase/functions/tests/ops_db_verification_schema_grounding_test.ts
//
// Every table and column the per-deploy DB verification catalog (checks.ts)
// references must exist in the committed migration history under
// runwar_app/supabase/migrations/, which is the deploying schema history
// (venture MISTAKES.md 2026-07-05 - runwar_database is retired/stale). This
// makes the catalog checkable offline with no live database: a typo or a
// stale column name fails here instead of at deploy time.
//
// Schema is extracted from CREATE TABLE column lists, ALTER TABLE
// ADD COLUMN / ALTER COLUMN / RENAME COLUMN statements, across every
// migration file. A handful of real live columns (zones.geom, zones.id,
// zones.owner_id) predate this repo's visible migration history and were
// only ever referenced via ALTER COLUMN TYPE / COMMENT ON COLUMN, the same
// "documents existing live drift" pattern already used by
// 0062_db_only_table_schema_capture.sql and 0064_run_summary_schema_capture.sql.
//
// Run: npx deno test --allow-read supabase/functions/tests/ops_db_verification_schema_grounding_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { CHECKS } from '../../../ops/db_verification/checks.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function extractSchema(): Map<string, Set<string>> {
  const schema = new Map<string, Set<string>>();
  const ensure = (t: string) => {
    if (!schema.has(t)) schema.set(t, new Set());
    return schema.get(t)!;
  };

  const dirPath = MIGRATIONS_DIR.pathname;
  const files = [...Deno.readDirSync(dirPath)]
    // *_rollback.sql files (e.g. 0050_rollback.sql) are manual-only undo
    // scripts - each one's own header says "apply this file only to revert
    // a post-N production regression" - not part of the forward sequence
    // Supabase actually applies on deploy. Including them here would let a
    // rollback's reverse RENAME COLUMN undo a real forward rename (e.g.
    // 0050_rollback.sql renaming gps_samples.user_id back to player_id),
    // which would ground the tool against the wrong, un-deployed schema.
    .filter((e) => e.isFile && e.name.endsWith('.sql') && !/_rollback\.sql$/i.test(e.name))
    .map((e) => e.name)
    .sort();

  for (const name of files) {
    const sql = Deno.readTextFileSync(dirPath + name);

    for (const stmt of sql.split(';')) {
      const createMatch = stmt.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?(\w+)\s*\(/i);
      if (createMatch) {
        const table = createMatch[1].toLowerCase();
        const cols = ensure(table);
        const openIdx = createMatch.index! + createMatch[0].length - 1;
        const rest = stmt.slice(openIdx + 1);
        let depth = 1;
        let end = 0;
        for (; end < rest.length && depth > 0; end++) {
          if (rest[end] === '(') depth++;
          else if (rest[end] === ')') depth--;
        }
        const body = rest.slice(0, Math.max(end - 1, 0));

        let colDepth = 0;
        let current = '';
        const parts: string[] = [];
        for (const ch of body) {
          if (ch === '(') colDepth++;
          if (ch === ')') colDepth--;
          if (ch === ',' && colDepth === 0) {
            parts.push(current);
            current = '';
          } else {
            current += ch;
          }
        }
        if (current.trim()) parts.push(current);

        for (const part of parts) {
          const trimmed = part.trim();
          if (/^(PRIMARY\s+KEY|UNIQUE|FOREIGN\s+KEY|CHECK|CONSTRAINT)/i.test(trimmed)) continue;
          const colMatch = trimmed.match(/^(\w+)\s+/);
          if (colMatch) cols.add(colMatch[1].toLowerCase());
        }
        continue;
      }

      const alterMatch = stmt.match(/ALTER\s+TABLE\s+(?:public\.)?(\w+)/i);
      if (alterMatch) {
        const table = alterMatch[1].toLowerCase();
        const cols = ensure(table);

        const addRe = /ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/gi;
        let m: RegExpExecArray | null;
        while ((m = addRe.exec(stmt))) cols.add(m[1].toLowerCase());

        const alterColRe = /ALTER\s+COLUMN\s+(\w+)/gi;
        while ((m = alterColRe.exec(stmt))) cols.add(m[1].toLowerCase());

        // A RENAME COLUMN removes the old name and adds the new one - a
        // later migration renaming a column away must make the old name
        // stop being grounded, not just add the new one on top of it. This
        // is what let checks.ts keep declaring gps_samples.player_id long
        // after 0050_player_id_to_user_id_unification.sql renamed it to
        // user_id: the old extraction only ever added names, never removed
        // one, so a renamed-away column stayed permanently "grounded".
        const renameRe = /RENAME\s+COLUMN\s+(\w+)\s+TO\s+(\w+)/gi;
        while ((m = renameRe.exec(stmt))) {
          cols.delete(m[1].toLowerCase());
          cols.add(m[2].toLowerCase());
        }
        continue;
      }

      const commentMatch = stmt.match(/COMMENT\s+ON\s+COLUMN\s+(?:public\.)?(\w+)\.(\w+)/i);
      if (commentMatch) {
        const cols = ensure(commentMatch[1].toLowerCase());
        cols.add(commentMatch[2].toLowerCase());
      }
    }
  }
  return schema;
}

Deno.test('the catalog has checks to ground (non-empty precondition)', () => {
  assert(CHECKS.length > 0, 'CHECKS must not be empty for this test to be meaningful');
});

Deno.test('a column a later migration RENAMEs away is not grounded under its old name', () => {
  // Regression for council finding 1: checks.ts declared gps_samples.player_id
  // long after 0050_player_id_to_user_id_unification.sql renamed it to
  // user_id, and this suite's own extraction never caught it because the old
  // logic only ever added names on RENAME, never removed the old one. This
  // asserts the extraction itself, not just the current catalog - reverting
  // the extraction fix (but not checks.ts) must still make this fail.
  const schema = extractSchema();
  const gpsSamples = schema.get('gps_samples');
  assert(gpsSamples, 'gps_samples table must be found in the migration history');
  assert(!gpsSamples!.has('player_id'), 'gps_samples.player_id was renamed to user_id by 0050 - it must not be grounded');
  assert(gpsSamples!.has('user_id'), 'gps_samples.user_id must be grounded (the rename target)');
});

Deno.test("every check's table and columns exist in the committed migration history", () => {
  assert(CHECKS.length > 0, 'CHECKS must not be empty for this loop to check anything');
  const schema = extractSchema();
  for (const check of CHECKS) {
    const table = check.table.toLowerCase();
    const known = schema.get(table);
    assert(known, `${check.id}: table "${check.table}" not found in any migration`);
    for (const col of check.columns) {
      assert(
        known!.has(col.toLowerCase()),
        `${check.id}: column "${col}" not found for table "${check.table}" in any migration`,
      );
    }
  }
});
