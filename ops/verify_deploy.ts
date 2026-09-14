#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env
// ops/verify_deploy.ts
//
// Per-deploy DB end-state verification entrypoint. Reads the six checks in
// ops/db_verification/checks.ts and either prints them (no flags,
// credential-free, no network call) or actually runs them as read-only
// PostgREST GET requests against a live Supabase project (--execute
// --env-file <path> [--subject <id>]).
//
// This exists because "the deploy succeeded" only means the migration ran,
// not that the database's observable end state looks the way the feature
// intends - the zones table sat empty in production for weeks in 2026-07
// because nobody ever queried it after a deploy. Run this after every
// deploy that touches zones/runs/gps_samples/anticheat_flags.
//
// Usage:
//   deno run --allow-read ops/verify_deploy.ts
//     Catalog mode (the default, and the no-flags invocation): prints all
//     six checks and their documented SELECT, reads no credential, makes no
//     network call, exits 0.
//
//   deno run --allow-read --allow-net --allow-env ops/verify_deploy.ts \
//     --execute --env-file /path/to/credentials.env --subject <player-id>
//     Execute mode: loads RUNWAR_SUPABASE_URL and
//     RUNWAR_SUPABASE_SERVICE_ROLE_KEY from the given env file, runs all
//     six checks as read-only GET requests, prints a PASS/FAIL line per
//     check, and exits non-zero if any check failed.
//
//   --execute with no --env-file silently falls back to catalog mode
//   (parseArgs' own contract - see ops/db_verification/cli.ts).

import { buildCheckQuery, buildRelatedQuery, CHECKS, deriveGpsSamplesRows, type DbCheck } from './db_verification/checks.ts';
import {
  isReadOnlyQuery,
  isServiceRoleToken,
  isValidSubject,
  parseArgs,
  summarize,
  type CheckResult,
  type Summary,
} from './db_verification/cli.ts';
import { computeZoneMerges, type ZoneInput } from '../supabase/functions/claim_territory/merge_geometry.ts';
import { ringSetsOf } from '../supabase/functions/claim_territory/handler.ts';

// Matches kMergeThresholdMeters in supabase/functions/claim_territory/handler.ts -
// the same 25 m same-owner contiguity threshold used to decide whether two
// zones should already have been merged into one row.
const ZONE_MERGE_THRESHOLD_M = 25;

function printCatalog(): void {
  console.log('RunWar per-deploy DB verification - catalog (no credentials read, no network call)\n');
  for (const check of CHECKS) {
    console.log(`[${check.id}] ${check.title}`);
    console.log(`  table:   ${check.table}`);
    console.log(`  columns: ${check.columns.join(', ')}`);
    console.log(`  sql:     ${check.sql}`);
    console.log('');
  }
  console.log('Run with --execute --env-file <path> [--subject <player-id>] to actually run these checks.');
}

// ---------------------------------------------------------------------------
// Credential loading (never printed, never logged)
// ---------------------------------------------------------------------------

function loadEnvFile(path: string): Map<string, string> {
  const text = Deno.readTextFileSync(path);
  const env = new Map<string, string>();
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const idx = line.indexOf('=');
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    value = value.split(' #')[0].trim().replace(/^['"]|['"]$/g, '');
    if (key) env.set(key, value);
  }
  return env;
}

export interface Credentials {
  url: string;
  serviceRoleKey: string;
}

// Thrown by loadCredentials() instead of calling Deno.exit() directly, so
// the credential logic itself stays a pure, unit-testable function - the
// CLI entrypoint (runExecuteMode) is the only place that turns this into a
// printed message and a process exit.
export class CredentialError extends Error {}

// Pure credential-resolution core, no file I/O and no Deno.env access of its
// own - a process-env lookup function and an already-parsed file map are
// passed in, so this is directly unit-testable with neither --allow-read nor
// --allow-env. loadCredentials() below is the only caller that wires it to
// the real filesystem and the real process environment.
export function resolveCredentials(
  envFile: string,
  fromFile: Map<string, string>,
  processEnv: (key: string) => string | undefined,
): Credentials {
  const url = processEnv('RUNWAR_SUPABASE_URL') ?? fromFile.get('RUNWAR_SUPABASE_URL');
  const key = processEnv('RUNWAR_SUPABASE_SERVICE_ROLE_KEY') ?? fromFile.get('RUNWAR_SUPABASE_SERVICE_ROLE_KEY');
  const missing = [
    ['RUNWAR_SUPABASE_URL', url],
    ['RUNWAR_SUPABASE_SERVICE_ROLE_KEY', key],
  ].filter(([, v]) => !v).map(([name]) => name);
  if (missing.length > 0) {
    throw new CredentialError(`missing required credential(s) in ${envFile}: ${missing.join(', ')}`);
  }
  if (!isServiceRoleToken(key!)) {
    // Never print the key itself. An RLS-denied read and a genuinely empty
    // result both return HTTP 200 with an empty array over PostgREST, so a
    // non-service-role key can silently turn a denied read into a false
    // PASS. Refuse before any check runs rather than let that happen.
    throw new CredentialError(
      'RUNWAR_SUPABASE_SERVICE_ROLE_KEY does not decode to a service_role JWT - refusing to run. ' +
        'A key of any other tier is subject to RLS, and an RLS-denied read is indistinguishable ' +
        'from a genuinely empty result, which would silently report a false PASS.',
    );
  }
  return { url: url!.replace(/\/$/, ''), serviceRoleKey: key! };
}

export function loadCredentials(envFile: string): Credentials {
  const fromFile = loadEnvFile(envFile);
  return resolveCredentials(envFile, fromFile, (key) => Deno.env.get(key));
}

// A fetch-shaped function, injectable so the live I/O layer below can be
// exercised with a fake in tests - no real network call, no real credential,
// and no global monkey-patching of `fetch` itself.
export type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

// ---------------------------------------------------------------------------
// Read-only PostgREST GET helper. Only ever issues a GET - no method is ever
// passed, so there is no write path reachable through this function.
// ---------------------------------------------------------------------------

export async function restGet(
  creds: Credentials,
  table: string,
  query: string,
  fetcher: Fetcher = fetch,
): Promise<Array<Record<string, unknown>>> {
  const res = await fetcher(`${creds.url}/rest/v1/${table}?${query}`, {
    method: 'GET',
    headers: {
      apikey: creds.serviceRoleKey,
      Authorization: `Bearer ${creds.serviceRoleKey}`,
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`GET ${table} failed: HTTP ${res.status} ${body.slice(0, 300)}`);
  }
  return await res.json();
}

// ---------------------------------------------------------------------------
// Per-check row fetch. Every branch is a plain GET; no check ever mutates.
// ---------------------------------------------------------------------------

export async function fetchRowsForCheck(
  check: DbCheck,
  creds: Credentials,
  subject: string,
  fetcher: Fetcher = fetch,
): Promise<unknown[]> {
  switch (check.id) {
    case 'zones-geom-exists':
    case 'zones-owner-matches':
    case 'runs-finalized':
    case 'anticheat-flags-clear':
      // The select= clause and table are built from check.columns/check.table
      // directly - there is no second, hand-copied query string to drift.
      return await restGet(creds, check.table, buildCheckQuery(check, subject), fetcher);

    case 'zones-adjacent-merged': {
      const rows = await restGet(creds, check.table, buildCheckQuery(check, subject), fetcher);
      const inputs: ZoneInput[] = rows.flatMap((r) => {
        const geomRaw = r.geom_json;
        const geom = typeof geomRaw === 'string' ? JSON.parse(geomRaw) : geomRaw;
        const id = typeof r.id === 'string' ? r.id : String(r.id);
        const createdAt = typeof r.created_at === 'string' ? r.created_at : String(r.created_at);
        const influenceLevel = typeof r.influence_level === 'number' ? r.influence_level : 1;
        return ringSetsOf(geom as { type?: string; coordinates?: unknown })
          .filter((rs) => rs[0] && rs[0].length >= 3)
          .map((rs) => ({
            id,
            ring: rs[0],
            holes: rs.length > 1 ? rs.slice(1) : undefined,
            createdAt,
            influenceLevel,
          }));
      });
      const groups = computeZoneMerges(inputs, ZONE_MERGE_THRESHOLD_M);
      // Any group with 2+ members is a same-owner, geometrically-adjacent
      // set that is STILL split across multiple rows - exactly the unmerged
      // state the check is guarding against. One representative pair per
      // group is enough to fail loudly; evaluate() only inspects rows[0].
      return groups.map((g) => ({ a_id: g.survivorId, b_id: g.absorbedIds[0], owner_id: subject }));
    }

    case 'gps-samples-present': {
      const finalizedRuns = await restGet(creds, check.table, buildCheckQuery(check, subject), fetcher) as Array<
        Record<string, unknown>
      >;
      const sampleCounts = new Map<string, number>();
      for (const run of finalizedRuns) {
        const sessionId = run.session_id;
        if (sessionId == null) continue;
        const key = String(sessionId);
        if (sampleCounts.has(key)) continue;
        const samples = await restGet(creds, check.related!.table, buildRelatedQuery(check, key), fetcher);
        sampleCounts.set(key, samples.length);
      }
      return deriveGpsSamplesRows(finalizedRuns, sampleCounts);
    }

    default:
      throw new Error(`no fetch implementation wired for check "${check.id}"`);
  }
}

export interface ExecuteModeResult {
  results: CheckResult[];
  summary: Summary;
}

// Runs every check and returns the aggregated results - it never prints and
// never calls Deno.exit() itself, so it is directly callable from a test
// with an injected fetcher. main() is the only caller that turns the
// returned summary into console output and a process exit code.
export async function runExecuteMode(
  envFile: string,
  subject: string | null,
  fetcher: Fetcher = fetch,
  // Defaults to the real filesystem+env-backed loader; a test injects a
  // fake resolver instead so no real file or environment variable is ever
  // touched (see resolveCredentials()).
  loadCreds: (envFile: string) => Credentials = loadCredentials,
): Promise<ExecuteModeResult> {
  if (!subject) {
    console.error('--execute requires --subject <player-id>');
    Deno.exit(2);
  }
  if (!isValidSubject(subject)) {
    // subject is interpolated directly into PostgREST filter query strings
    // (buildCheckQuery/buildRelatedQuery). An unvalidated value could carry
    // extra query params (e.g. "<uuid>&limit=0") and force a real FAIL into
    // a silent PASS, so it is validated once here before any check runs.
    console.error(`--subject must be a well-formed UUID, got: "${subject}"`);
    Deno.exit(2);
  }

  let creds: Credentials;
  try {
    creds = loadCreds(envFile);
  } catch (e) {
    if (e instanceof CredentialError) {
      console.error(e.message);
      Deno.exit(2);
    }
    throw e;
  }

  const results: CheckResult[] = [];
  for (const check of CHECKS) {
    // isReadOnlyQuery is run against every check's documented sql before use,
    // even though the actual fetch below is a PostgREST GET rather than raw
    // SQL - this keeps the guard load-bearing for the one thing that could
    // ever change it: a future edit to checks.ts introducing a non-SELECT
    // check.sql.
    if (!isReadOnlyQuery(check.sql)) {
      throw new Error(`refusing to run "${check.id}": its documented sql is not a single read-only SELECT`);
    }
    try {
      const rows = await fetchRowsForCheck(check, creds, subject, fetcher);
      const { pass, detail } = check.evaluate(rows);
      results.push({ id: check.id, pass, detail });
    } catch (e) {
      results.push({ id: check.id, pass: false, detail: `error: ${e instanceof Error ? e.message : String(e)}` });
    }
  }

  const summary = summarize(results);
  return { results, summary };
}

async function main(): Promise<void> {
  const parsed = parseArgs(Deno.args);
  if (parsed.mode === 'catalog') {
    printCatalog();
    return;
  }
  const { summary } = await runExecuteMode(parsed.envFile!, parsed.subject);
  for (const line of summary.lines) console.log(line);
  console.log(`\n${summary.verdict}: ${summary.passed} passed, ${summary.failed} failed`);
  if (summary.verdict !== 'PASS') Deno.exit(1);
}

if (import.meta.main) {
  await main();
}
