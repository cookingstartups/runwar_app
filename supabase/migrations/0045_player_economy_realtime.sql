-- Migration 0045: enable Supabase Realtime on player_economy
-- Required by SupabaseCreditsRepository.watchBalance to receive live UPDATE
-- payloads when apply_credit_delta mutates player_economy.credits.
--
-- Without this migration, .stream() on player_economy emits exactly once
-- (on subscribe) and never receives subsequent server-side updates.
--
-- REPLICA IDENTITY FULL is required so that RLS-filtered subscribers (the
-- player_economy_select_own policy from migration 0035) receive the full
-- new-row payload on UPDATE rather than only PK columns.

-- Set replica identity first so any UPDATE between the two statements
-- carries the full row (safer ordering; either order is legal).
ALTER TABLE player_economy REPLICA IDENTITY FULL;

-- Add to the supabase_realtime publication. Idempotent via DO block so the
-- migration can be re-applied without erroring if the table is already a
-- publication member.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'player_economy'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.player_economy;
  END IF;
END $$;
