// supabase/functions/tests/account_deletion_executor_migration_test.ts
//
// Source-inspection coverage for the bot-transfer executor migration: pg_net
// enablement, bot resolution, the claim-then-transact idempotency guard, and
// the daily pg_cron sweep. Same escape hatch as
// resolve_zone_disputes_migration_test.ts - no live Postgres instance
// available in this sandbox.
//
// Run: npx deno test supabase/functions/tests/account_deletion_executor_migration_test.ts

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const MIGRATIONS_DIR = new URL('../../migrations/', import.meta.url);

function findMigration(nameFragment: string): string {
  const dirPath = MIGRATIONS_DIR.pathname;
  const matches: string[] = [];
  for (const entry of Deno.readDirSync(dirPath)) {
    if (entry.isFile && entry.name.includes(nameFragment)) matches.push(entry.name);
  }
  assert(
    matches.length > 0,
    `No migration file matching "${nameFragment}" found - the account-deletion executor migration has not been created yet.`,
  );
  return Deno.readTextFileSync(dirPath + matches[0]);
}

Deno.test('pg_net is enabled as the migration\'s first real statement', () => {
  const sql = findMigration('account_deletion_executor');
  const trimmed = sql.trimStart();
  assert(/^CREATE EXTENSION IF NOT EXISTS pg_net;/i.test(trimmed),
    'CREATE EXTENSION IF NOT EXISTS pg_net; must be the first statement in this migration');
});

Deno.test('resolve_deletion_target_bot picks from the bots table, never the stale players/spawn_conquer_bot pattern', () => {
  const sql = findMigration('account_deletion_executor');
  assert(sql.includes('resolve_deletion_target_bot'), 'bot-resolution function must be defined');
  assert(/from\s+bots/i.test(sql), 'must select from the bots table');
  assert(!sql.includes('spawn_conquer_bot'), 'must not reference the stale spawn_conquer_bot function');
});

Deno.test('claim_and_transfer_zones claims the row FIRST (idempotency guard against concurrent execution)', () => {
  const sql = findMigration('account_deletion_executor');
  const fnIdx = sql.indexOf('claim_and_transfer_zones');
  assert(fnIdx > -1, 'claim_and_transfer_zones function must be defined');
  const body = sql.substring(fnIdx);
  const updateStatusIdx = body.search(/update\s+account_deletion_requests[\s\S]*?set\s+status\s*=\s*'executed'/i);
  const zoneTransferIdx = body.search(/update\s+zones[\s\S]*?owner_id\s*=\s*v_bot_id/i);
  assert(updateStatusIdx > -1, 'the claim UPDATE (status = executed) must exist');
  assert(zoneTransferIdx > -1, 'the zone-transfer UPDATE must exist');
  assert(updateStatusIdx < zoneTransferIdx,
    'the claim must happen BEFORE the zone transfer, so a concurrent invocation on the same row is blocked/no-ops via the row lock and WHERE status = pending predicate');
});

Deno.test('the claim guards on status = pending and scheduled_deletion_at <= now()', () => {
  const sql = findMigration('account_deletion_executor');
  assert(/status\s*=\s*'pending'\s+and\s+scheduled_deletion_at\s*<=\s*now\(\)/i.test(sql),
    'the claiming UPDATE must only match still-pending, past-due rows');
});

Deno.test('a null bot resolution rolls back rather than transferring to nothing', () => {
  const sql = findMigration('account_deletion_executor');
  assert(/if\s+v_bot_id\s+is\s+null\s+then/i.test(sql));
  assert(/raise exception/i.test(sql),
    'no resolvable bot must raise (rolling back the whole transaction, including the claim), never fail open');
});

Deno.test('attacker references are cleared before zones are transferred', () => {
  const sql = findMigration('account_deletion_executor');
  const clearIdx = sql.search(/contested_by_id\s*=\s*null/i);
  const transferIdx = sql.search(/owner_id\s*=\s*v_bot_id/i);
  assert(clearIdx > -1 && transferIdx > -1);
  assert(clearIdx < transferIdx, 'attacker-reference clearing must precede the owned-zone transfer');
});

Deno.test('the zone transfer uses the exact resolve_zone_disputes field-reset set', () => {
  const sql = findMigration('account_deletion_executor');
  for (const field of ['influence_level = 1', "status = 'owned'", 'shield_active = FALSE', 'shield_expires_at = NULL']) {
    assert(sql.toLowerCase().includes(field.toLowerCase()), `missing expected field reset: ${field}`);
  }
});

Deno.test('a daily pg_cron sweep schedules the executor via net.http_post', () => {
  const sql = findMigration('account_deletion_executor');
  assert(sql.includes('cron.schedule'), 'must schedule a daily pg_cron job');
  assert(sql.includes('net.http_post'), 'the sweep must invoke the edge function over HTTP via pg_net');
});
