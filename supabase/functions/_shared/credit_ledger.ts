// supabase/functions/_shared/credit_ledger.ts
// Thin wrapper around the apply_credit_delta RPC.
// Every edge fn that moves credits MUST use this - never UPDATE players.credits directly.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export type LedgerReason =
  | 'claim'
  | 'conquest'
  | 'run'
  | 'passive_income'
  | 'passive_catchup'
  | 'drop_pickup'
  | 'ctf_win'
  | 'referral_kick'
  | 'spend_power'
  | 'dispute_defense'
  | 'admin_grant'
  | 'admin_clawback'

export interface LedgerWriteInput {
  playerId: string
  delta: number                          // negative for spend, positive for earn
  reason: LedgerReason
  relatedEntityId?: string | null
  relatedEntityType?: 'run' | 'zone' | 'drop' | 'offer' | 'ctf_event' | null
  metadata?: Record<string, unknown>
}

export interface LedgerWriteResult {
  newBalance: number
}

export async function writeLedger(
  supabase: SupabaseClient,
  input: LedgerWriteInput,
): Promise<LedgerWriteResult> {
  const { data, error } = await supabase.rpc('apply_credit_delta', {
    p_player_id:           input.playerId,
    p_delta:               input.delta,
    p_reason:              input.reason,
    p_related_entity_id:   input.relatedEntityId   ?? null,
    p_related_entity_type: input.relatedEntityType ?? null,
    p_metadata:            input.metadata           ?? {},
  })
  if (error) {
    throw new Error(`writeLedger(${input.reason}, delta=${input.delta}): ${error.message}`)
  }
  return { newBalance: data as number }
}
