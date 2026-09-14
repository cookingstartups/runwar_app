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

import { CHECKS, type DbCheck } from './db_verification/checks.ts';
import { isReadOnlyQuery, parseArgs, summarize, type CheckResult } from './db_verification/cli.ts';
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

interface Credentials {
  url: string;
  serviceRoleKey: string;
}

function loadCredentials(envFile: string): Credentials {
  const fromFile = loadEnvFile(envFile);
  const url = Deno.env.get('RUNWAR_SUPABASE_URL') ?? fromFile.get('RUNWAR_SUPABASE_URL');
  const key = Deno.env.get('RUNWAR_SUPABASE_SERVICE_ROLE_KEY') ?? fromFile.get('RUNWAR_SUPABASE_SERVICE_ROLE_KEY');
  const missing = [
    ['RUNWAR_SUPABASE_URL', url],
    ['RUNWAR_SUPABASE_SERVICE_ROLE_KEY', key],
  ].filter(([, v]) => !v).map(([name]) => name);
  if (missing.length > 0) {
    console.error(`missing required credential(s) in ${envFile}: ${missing.join(', ')}`);
    Deno.exit(2);
  }
  return { url: url!.replace(/\/$/, ''), serviceRoleKey: key! };
}

// ---------------------------------------------------------------------------
// Read-only PostgREST GET helper. Only ever issues a GET - no method is ever
// passed, so there is no write path reachable through this function.
// ---------------------------------------------------------------------------

async function restGet(
  creds: Credentials,
  table: string,
  query: string,
): Promise<Array<Record<string, unknown>>> {
  const res = await fetch(`${creds.url}/rest/v1/${table}?${query}`, {
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

async function fetchRowsForCheck(
  check: DbCheck,
  creds: Credentials,
  subject: string,
): Promise<unknown[]> {
  switch (check.id) {
    case 'zones-geom-exists':
      return await restGet(
        creds,
        'zones',
        `select=id,owner_id,geom&owner_id=eq.${subject}&status=eq.owned&geom=not.is.null&limit=1`,
      );

    case 'zones-owner-matches':
      return await restGet(creds, 'zones', `select=id,owner_id&owner_id=eq.${subject}`);

    case 'zones-adjacent-merged': {
      const rows = await restGet(
        creds,
        'zones',
        `select=id,owner_id,geom_json,created_at,influence_level&owner_id=eq.${subject}&status=eq.owned&order=created_at`,
      );
      const inputs: ZoneInput[] = rows.flatMap((r) => {
        const geomRaw = r.geom_json;
        const geom = typeof geomRaw === 'string' ? JSON.parse(geomRaw) : geomRaw;
        return ringSetsOf(geom as { type?: string; coordinates?: unknown })
          .filter((rs) => rs[0] && rs[0].length >= 3)
          .map((rs) => ({
            id: r.id as string,
            ring: rs[0],
            holes: rs.length > 1 ? rs.slice(1) : undefined,
            createdAt: r.created_at as string,
            influenceLevel: (r.influence_level as number | null) ?? 1,
          }));
      });
      const groups = computeZoneMerges(inputs, ZONE_MERGE_THRESHOLD_M);
      // Any group with 2+ members is a same-owner, geometrically-adjacent
      // set that is STILL split across multiple rows - exactly the unmerged
      // state the check is guarding against. One representative pair per
      // group is enough to fail loudly; evaluate() only inspects rows[0].
      return groups.map((g) => ({ a_id: g.survivorId, b_id: g.absorbedIds[0], owner_id: subject }));
    }

    case 'runs-finalized':
      return await restGet(
        creds,
        'runs',
        `select=id,user_id,status,ended_at,finalized_at&user_id=eq.${subject}&or=(status.eq.active,ended_at.is.null,finalized_at.is.null)`,
      );

    case 'gps-samples-present': {
      const finalizedRuns = await restGet(
        creds,
        'runs',
        `select=id,session_id&user_id=eq.${subject}&finalized_at=not.is.null`,
      );
      const missing: Array<Record<string, unknown>> = [];
      for (const run of finalizedRuns) {
        const sessionId = run.session_id;
        if (!sessionId) {
          missing.push({ run_id: run.id, session_id: null });
          continue;
        }
        const samples = await restGet(
          creds,
          'gps_samples',
          `select=id&session_id=eq.${sessionId}&limit=1`,
        );
        if (samples.length === 0) missing.push({ run_id: run.id, session_id: sessionId });
      }
      return missing;
    }

    case 'anticheat-flags-clear':
      return await restGet(
        creds,
        'anticheat_flags',
        `select=id,user_id,flag_type,created_at&user_id=eq.${subject}`,
      );

    default:
      throw new Error(`no fetch implementation wired for check "${check.id}"`);
  }
}

async function runExecuteMode(envFile: string, subject: string | null): Promise<void> {
  if (!subject) {
    console.error('--execute requires --subject <player-id>');
    Deno.exit(2);
  }
  const creds = loadCredentials(envFile);

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
      const rows = await fetchRowsForCheck(check, creds, subject);
      const { pass, detail } = check.evaluate(rows);
      results.push({ id: check.id, pass, detail });
    } catch (e) {
      results.push({ id: check.id, pass: false, detail: `error: ${e instanceof Error ? e.message : String(e)}` });
    }
  }

  const summary = summarize(results);
  for (const line of summary.lines) console.log(line);
  console.log(`\n${summary.verdict}: ${summary.passed} passed, ${summary.failed} failed`);
  if (summary.verdict !== 'PASS') Deno.exit(1);
}

async function main(): Promise<void> {
  const parsed = parseArgs(Deno.args);
  if (parsed.mode === 'catalog') {
    printCatalog();
    return;
  }
  await runExecuteMode(parsed.envFile!, parsed.subject);
}

if (import.meta.main) {
  await main();
}
