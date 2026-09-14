// ops/db_verification/checks.ts
//
// The six read-only per-deploy DB end-state checks. Each check documents a
// single, operator-pasteable SELECT (the `sql` field) and a pure evaluate()
// function that turns a fetched row set into a PASS/FAIL verdict. This is
// the whole point of the tool: "deployed" only means the migration ran, not
// that the observable end state actually looks the way the feature intends
// (the 2026-07-03 lesson - the zones table sat empty in production for
// weeks because nobody ever queried it after a deploy).
//
// evaluate() never talks to a database. The actual fetch is done by
// ops/verify_deploy.ts through read-only PostgREST GET requests; this file
// only declares WHAT to check and HOW to score the result.
//
// Table/column names are grounded against the committed migration history
// (supabase/migrations/) by ops_db_verification_schema_grounding_test.ts -
// see that file's own comment for the extraction rules. anticheat_flags'
// flag_type/created_at/details/run_id columns are documented for the first
// time by supabase/migrations/0075_anticheat_flags_schema_capture.sql
// (a pure schema-capture migration, same pattern as 0062/0064) - they were
// already real, live columns (written by supabase/functions/anticheat_score/
// index.ts) with no migration ever defining them until now.

export interface DbCheck {
  id: string;
  title: string;
  table: string;
  columns: string[];
  sql: string;
  evaluate(rows: unknown[]): { pass: boolean; detail: string };
}

function isNonEmptyArray(rows: unknown[]): boolean {
  return Array.isArray(rows) && rows.length > 0;
}

export const CHECKS: DbCheck[] = [
  {
    id: 'zones-geom-exists',
    title: 'The subject owns at least one zone with a non-null geometry',
    table: 'zones',
    columns: ['id', 'owner_id', 'geom'],
    sql:
      "SELECT id, owner_id, geom FROM zones WHERE owner_id = $1 AND status = 'owned' AND geom IS NOT NULL",
    evaluate(rows) {
      const row = Array.isArray(rows) ? rows[0] as Record<string, unknown> | undefined : undefined;
      const pass = !!row && row.geom != null;
      return {
        pass,
        detail: pass
          ? `zone ${String(row!.id)} has a non-null geom`
          : 'no owned zone with a non-null geom was found for the subject',
      };
    },
  },
  {
    id: 'zones-owner-matches',
    title: "The subject's zone rows are actually owned by the subject",
    table: 'zones',
    columns: ['id', 'owner_id'],
    sql: 'SELECT id, owner_id FROM zones WHERE owner_id = $1',
    evaluate(rows) {
      const pass = isNonEmptyArray(rows);
      return {
        pass,
        detail: pass
          ? `${(rows as unknown[]).length} zone row(s) owned by the subject`
          : 'no zone row is owned by the subject',
      };
    },
  },
  {
    id: 'zones-adjacent-merged',
    title: 'No two same-owner zones are left touching or intersecting, unmerged',
    table: 'zones',
    columns: ['id', 'owner_id', 'geom_json'],
    sql:
      "SELECT id, owner_id, geom_json, created_at, influence_level FROM zones WHERE owner_id = $1 AND status = 'owned' ORDER BY created_at",
    // Rows here are pre-computed unmerged-pair problems (a_id/b_id/owner_id),
    // produced client-side by ops/db_verification/adjacency.ts from the raw
    // zone rows the sql above returns - see that file's comment for why the
    // pairing itself is not done in evaluate().
    evaluate(rows) {
      const pass = !isNonEmptyArray(rows);
      if (pass) return { pass, detail: 'no unmerged adjacent same-owner zone pair found' };
      const first = (rows as Array<Record<string, unknown>>)[0];
      return {
        pass,
        detail:
          `zones ${String(first.a_id)} and ${String(first.b_id)} (owner ${String(first.owner_id)}) ` +
          'are adjacent and same-owner but were never merged',
      };
    },
  },
  {
    id: 'runs-finalized',
    title: "The subject's runs are all finalized - none stuck mid-flight",
    table: 'runs',
    columns: ['id', 'user_id', 'status', 'ended_at', 'finalized_at'],
    sql:
      "SELECT id, user_id, status, ended_at, finalized_at FROM runs WHERE user_id = $1 AND (status = 'active' OR ended_at IS NULL OR finalized_at IS NULL)",
    evaluate(rows) {
      const pass = !isNonEmptyArray(rows);
      if (pass) return { pass, detail: 'no stuck (non-finalized) run found for the subject' };
      const stuck = rows as Array<Record<string, unknown>>;
      return {
        pass,
        detail: `${stuck.length} run(s) stuck mid-flight, e.g. run ${String(stuck[0].id)}`,
      };
    },
  },
  {
    id: 'gps-samples-present',
    title: 'Every finalized run has at least one gps_samples row',
    table: 'gps_samples',
    columns: ['session_id', 'player_id', 'ts'],
    sql:
      'SELECT r.id AS run_id, r.session_id FROM runs r ' +
      'LEFT JOIN gps_samples g ON g.session_id = r.session_id ' +
      "WHERE r.user_id = $1 AND r.finalized_at IS NOT NULL AND g.id IS NULL",
    evaluate(rows) {
      const pass = !isNonEmptyArray(rows);
      if (pass) return { pass, detail: 'every finalized run has at least one gps_samples row' };
      const missing = rows as Array<Record<string, unknown>>;
      return {
        pass,
        detail: `${missing.length} finalized run(s) with zero gps_samples rows, ` +
          `e.g. run ${String(missing[0].run_id)}`,
      };
    },
  },
  {
    id: 'anticheat-flags-clear',
    title: 'No blocking/unresolved anticheat flag exists for the subject',
    table: 'anticheat_flags',
    columns: ['id', 'user_id', 'flag_type', 'created_at'],
    sql: 'SELECT id, user_id, flag_type, created_at FROM anticheat_flags WHERE user_id = $1',
    evaluate(rows) {
      const pass = !isNonEmptyArray(rows);
      if (pass) return { pass, detail: 'no anticheat flag exists for the subject' };
      const flags = rows as Array<Record<string, unknown>>;
      return {
        pass,
        detail: `${flags.length} unresolved anticheat flag(s), e.g. ${String(flags[0].flag_type)}`,
      };
    },
  },
];
