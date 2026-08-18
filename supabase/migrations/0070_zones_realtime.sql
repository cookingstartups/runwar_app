-- Migration 0070: enable Supabase Realtime on zones
-- Required by SupabaseZonesRepository's existing (currently inert) Realtime
-- channel subscription to receive live INSERT/UPDATE/DELETE payloads when
-- zones rows change (own claims, other players' claims, conquest, dispute,
-- decay merges).
--
-- Without this migration, zones is not a member of the supabase_realtime
-- publication, so .onPostgresChanges() on table 'zones' never fires; the
-- map's only refresh path is the manual invalidate() after a local claim.
--
-- REPLICA IDENTITY FULL is required so that RLS-filtered subscribers (the
-- zones_city_read policy) receive the full new-row payload rather than only
-- PK columns - same rationale as 0045_player_economy_realtime.sql.

ALTER TABLE zones REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'zones'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.zones;
  END IF;
END $$;
