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
// ops/verify_deploy.ts through read-only PostgREST GET requests. That fetch
// is built by buildCheckQuery()/buildRelatedQuery() below, straight from
// this check's own `table`/`columns`/`buildFilter` fields - there is no
// second, hand-copied representation of the select clause anywhere. This is
// deliberate: a check whose declared `columns` diverges from the columns
// the query actually needs used to be able to survive unnoticed (a renamed
// column sat in `columns` for documentation only, while the real fetch used
// a completely different, hand-written select= string). Deriving the
// executed request from `columns` makes that specific drift structurally
// impossible - the declared columns ARE the select clause.
//
// Table/column names are grounded against the committed migration history
// (supabase/migrations/) by ops_db_verification_schema_grounding_test.ts -
// see that file's own comment for the extraction rules. anticheat_flags'
// flag_type/created_at/details/run_id columns are documented for the first
// time by supabase/migrations/0075_anticheat_flags_schema_capture.sql
// (a pure schema-capture migration, same pattern as 0062/0064) - they were
// already real, live columns (written by supabase/functions/anticheat_score/
// index.ts) with no migration ever defining them until now.

export interface RelatedQuery {
  table: string;
  columns: string[];
  buildFilter(id: string): string;
}

export interface DbCheck {
  id: string;
  title: string;
  table: string;
  columns: string[];
  sql: string;
  /** PostgREST filter query params (everything after the `select=` clause)
   * for this check's primary table, keyed on the given subject id. */
  buildFilter(subject: string): string;
  /** Set only for checks whose real end state also depends on a second
   * table (a follow-up existence lookup keyed on a value from the primary
   * fetch, e.g. gps-samples-present's per-session gps_samples lookup). */
  related?: RelatedQuery;
  evaluate(rows: unknown[]): { pass: boolean; detail: string };
}

/** Builds the actual PostgREST query string for a check's primary table.
 * The select= clause is `check.columns.join(',')` - not a second, separately
 * maintained list - so a check's declared columns and its executed query
 * cannot silently diverge. */
export function buildCheckQuery(check: DbCheck, subject: string): string {
  return `select=${check.columns.join(',')}&${check.buildFilter(subject)}`;
}

/** Same guarantee as buildCheckQuery(), for a check's `related` table. */
export function buildRelatedQuery(check: DbCheck, id: string): string {
  if (!check.related) {
    throw new Error(`check "${check.id}" has no related query`);
  }
  return `select=${check.related.columns.join(',')}&${check.related.buildFilter(id)}`;
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
    buildFilter: (subject) => `owner_id=eq.${subject}&status=eq.owned&geom=not.is.null&limit=1`,
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
    buildFilter: (subject) => `owner_id=eq.${subject}`,
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
    columns: ['id', 'owner_id', 'geom_json', 'created_at', 'influence_level'],
    sql:
      "SELECT id, owner_id, geom_json, created_at, influence_level FROM zones WHERE owner_id = $1 AND status = 'owned' ORDER BY created_at",
    buildFilter: (subject) => `owner_id=eq.${subject}&status=eq.owned&order=created_at`,
    // Rows returned by fetchRowsForCheck (ops/verify_deploy.ts) here are
    // pre-computed unmerged-pair problems (a_id/b_id/owner_id), produced
    // client-side from the raw zone rows the buildFilter() query above
    // returns, by reusing the production computeZoneMerges/ringSetsOf
    // geometry helpers - see ops/verify_deploy.ts's zones-adjacent-merged
    // case for that logic.
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
    title: "The subject's runs all exist and are finalized - none stuck mid-flight",
    table: 'runs',
    columns: ['id', 'user_id', 'status', 'ended_at', 'finalized_at'],
    sql: 'SELECT id, user_id, status, ended_at, finalized_at FROM runs WHERE user_id = $1',
    buildFilter: (subject) => `user_id=eq.${subject}`,
    evaluate(rows) {
      // An empty result is a FAIL, not a vacuous PASS - a subject with zero
      // runs at all has nothing this check has actually verified.
      if (!isNonEmptyArray(rows)) {
        return { pass: false, detail: 'no run exists for the subject - nothing to verify as finalized' };
      }
      const all = rows as Array<Record<string, unknown>>;
      const stuck = all.filter((r) => r.status === 'active' || r.ended_at == null || r.finalized_at == null);
      if (stuck.length === 0) {
        return { pass: true, detail: `${all.length} run(s) found for the subject, all finalized` };
      }
      return {
        pass: false,
        detail: `${stuck.length} run(s) stuck mid-flight, e.g. run ${String(stuck[0].id)}`,
      };
    },
  },
  {
    id: 'gps-samples-present',
    title: 'Every finalized run has at least one gps_samples row',
    table: 'runs',
    columns: ['id', 'session_id', 'user_id', 'finalized_at'],
    sql:
      "SELECT id, session_id, user_id, finalized_at FROM runs WHERE user_id = $1 AND finalized_at IS NOT NULL",
    buildFilter: (subject) => `user_id=eq.${subject}&finalized_at=not.is.null`,
    related: {
      table: 'gps_samples',
      columns: ['id', 'session_id'],
      buildFilter: (sessionId) => `session_id=eq.${sessionId}&limit=1`,
    },
    evaluate(rows) {
      const list = rows as Array<Record<string, unknown>>;
      if (list.length === 1 && list[0].reason === 'no-finalized-runs') {
        return {
          pass: false,
          detail: 'no finalized run exists for the subject - nothing to verify for gps_samples',
        };
      }
      const pass = list.length === 0;
      if (pass) return { pass, detail: 'every finalized run has at least one gps_samples row' };
      return {
        pass,
        detail: `${list.length} finalized run(s) with zero gps_samples rows, ` +
          `e.g. run ${String(list[0].run_id)}`,
      };
    },
  },
  {
    id: 'anticheat-flags-clear',
    title: 'No blocking/unresolved anticheat flag exists for the subject',
    table: 'anticheat_flags',
    columns: ['id', 'user_id', 'flag_type', 'created_at'],
    sql: 'SELECT id, user_id, flag_type, created_at FROM anticheat_flags WHERE user_id = $1',
    buildFilter: (subject) => `user_id=eq.${subject}`,
    evaluate(rows) {
      // Empty here is the genuine pass condition (no flags = clean). This
      // is exactly why loadCredentials() (ops/verify_deploy.ts) validates
      // the key is service-role tier before any check runs: an RLS-denied
      // read also returns an empty array over PostgREST, so this check
      // alone cannot distinguish "genuinely clean" from "silently denied".
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

/** Pure derivation of gps-samples-present's fetch result from the raw
 * finalized-run rows and a session-id to sample-count map. Extracted out of
 * ops/verify_deploy.ts's I/O loop so this logic is unit-testable with no
 * network and no live database. */
export function deriveGpsSamplesRows(
  finalizedRuns: Array<Record<string, unknown>>,
  sampleCounts: Map<string, number>,
): Array<Record<string, unknown>> {
  if (finalizedRuns.length === 0) {
    return [{ run_id: null, session_id: null, reason: 'no-finalized-runs' }];
  }
  const missing: Array<Record<string, unknown>> = [];
  for (const run of finalizedRuns) {
    const sessionId = run.session_id;
    if (sessionId == null) {
      missing.push({ run_id: run.id, session_id: null });
      continue;
    }
    const count = sampleCounts.get(String(sessionId)) ?? 0;
    if (count === 0) missing.push({ run_id: run.id, session_id: sessionId });
  }
  return missing;
}
