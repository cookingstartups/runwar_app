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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// True only for a strict, well-formed UUID. --subject is interpolated
/// directly into PostgREST filter query strings (ops/verify_deploy.ts), so
/// an unvalidated value like `<uuid>&limit=0` could force an affected
/// check's GET to return zero rows regardless of real DB state, turning a
/// real FAIL into a silent PASS.
export function isValidSubject(subject: string): boolean {
  return UUID_RE.test(subject);
}

/// Decodes a JWT's payload and returns its `role` claim, or null if the
/// token is not a well-formed three-part JWT or has no string `role` claim.
/// No network call, never logs or returns the token itself.
export function decodeJwtRole(token: string): string | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
    const payload = JSON.parse(atob(padded));
    return typeof payload?.role === 'string' ? payload.role : null;
  } catch {
    return null;
  }
}

/// True only when the given credential decodes to a service_role JWT. A
/// non-service-role key is silently subject to RLS, which returns HTTP 200
/// with an empty array on denial - indistinguishable from a genuinely
/// empty/clean result. Checking this before any check runs is what
/// prevents an RLS-denied read from being mistaken for a clean PASS.
export function isServiceRoleToken(token: string): boolean {
  return decodeJwtRole(token) === 'service_role';
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
