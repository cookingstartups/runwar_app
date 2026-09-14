// ops/db_verification/cli.ts
//
// Pure helpers for the per-deploy DB verification CLI: the read-only-SELECT
// guard, argument parsing, and result summarization. No I/O in this file -
// the actual PostgREST fetch and Deno.args wiring live in
// ops/verify_deploy.ts, which is what makes these three functions cheaply
// unit-testable with no database and no Deno.env access.

const MUTATING_KEYWORD_RE = /\b(insert|update|delete|drop|alter|truncate|grant|create)\b/i;

/// True only for a single, well-formed SELECT statement. Rejects any
/// mutating keyword, any DDL keyword, and any input containing more than
/// one statement (a second statement after a `;` could itself be a mutation
/// even when the first statement is a harmless SELECT).
export function isReadOnlyQuery(sql: string): boolean {
  const trimmed = sql.trim();
  if (!/^select\s/i.test(trimmed)) return false;
  if (/;\s*\S/.test(trimmed)) return false;
  if (MUTATING_KEYWORD_RE.test(trimmed)) return false;
  return true;
}

export interface ParsedArgs {
  mode: 'catalog' | 'execute';
  envFile: string | null;
  subject: string | null;
}

/// The no-flags invocation always yields catalog mode (credential-free by
/// default). `--execute` only takes effect when paired with `--env-file`;
/// `--execute` alone silently degrades back to catalog mode rather than
/// attempting to run anything with no credentials to run it against.
export function parseArgs(argv: string[]): ParsedArgs {
  let execute = false;
  let envFile: string | null = null;
  let subject: string | null = null;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--execute') {
      execute = true;
    } else if (arg === '--env-file') {
      envFile = argv[++i] ?? null;
    } else if (arg === '--subject') {
      subject = argv[++i] ?? null;
    }
  }

  const mode: 'catalog' | 'execute' = execute && envFile !== null ? 'execute' : 'catalog';
  return { mode, envFile: mode === 'execute' ? envFile : null, subject };
}

export interface CheckResult {
  id: string;
  pass: boolean;
  detail: string;
}

export interface Summary {
  passed: number;
  failed: number;
  verdict: 'PASS' | 'FAIL';
  lines: string[];
}

/// An empty result set is a FAIL, never a vacuous PASS - "no checks ran" is
/// never itself an acceptable verification outcome.
export function summarize(results: CheckResult[]): Summary {
  const passed = results.filter((r) => r.pass).length;
  const failed = results.length - passed;
  const lines = results.map((r) => `${r.pass ? 'PASS' : 'FAIL'} ${r.id}: ${r.detail}`);
  const verdict: 'PASS' | 'FAIL' = results.length > 0 && failed === 0 ? 'PASS' : 'FAIL';
  return { passed, failed, verdict, lines };
}
