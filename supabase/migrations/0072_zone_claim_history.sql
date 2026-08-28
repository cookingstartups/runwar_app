-- Migration 0072: permanent per-zone claim history for fog-of-war reveal.
--
-- Bug: fog visibility for a non-owned zone is gated on CURRENT ownership
-- only (map_screen.dart's visibleZones: z.ownerId == userId OR fog-circle
-- proximity). Once a player loses a zone (conquest, expiry, decay merge),
-- it can fall back under fog if the player never physically re-runs near
-- it - even though they once fully claimed it. Fog reveal must be
-- permanent-once-revealed per zone, independent of current ownership.
--
-- Fix: an append-only history table recording "user X has ever held zone
-- Y", written automatically via an AFTER INSERT/UPDATE-OF-owner_id trigger
-- on zones - this covers every owner-assignment path (claim_territory's
-- new-zone insert, conquest update, spawn_conquer_bot, ctf_claim_win,
-- resolve_decay_merges, etc.) with a single trigger, with no per-caller
-- edge-function edits required.
--
-- zones.id is UUID in the live table (re-verified directly against
-- information_schema.columns - see 0053_apply_zone_merge_tx.sql's own note;
-- the 0029 CREATE TABLE IF NOT EXISTS's "id TEXT" declaration was a no-op
-- against the already-existing remote table and does not reflect the real
-- column type).
--
-- Merge/split propagation (apply_zone_merge / apply_zone_split, migrations
-- 0053/0056): NEITHER path reassigns owner_id.
--   - Merge only unifies zones already owned by the same player (the
--     absorbed rows are deleted, the survivor row's id/owner_id are
--     unchanged) - both survivor and every absorbed zone already have a
--     history row for that player from their own original claim/conquest,
--     so no extra propagation step is needed. The absorbed rows' history
--     rows are removed via the zone_id FK's ON DELETE CASCADE below, which
--     is harmless since the absorbed zone id no longer exists in `zones`
--     and can never be rendered again.
--   - Split only rewrites the remainder zone's geometry in place (same id,
--     same owner_id); the re-run's own new ring goes through the ordinary
--     insert-and-merge-scan path and gets its own trigger-fired history
--     row like any other new claim.
-- Net effect: because both paths preserve owner_id and zone id stability
-- for every row that survives, the base owner_id trigger alone is a
-- complete history source with no separate merge/split-aware write path.

CREATE TABLE IF NOT EXISTS zone_claim_history (
  zone_id          UUID        NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
  user_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  first_claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (zone_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_zone_claim_history_user ON zone_claim_history(user_id);

ALTER TABLE zone_claim_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS zone_claim_history_read_own ON zone_claim_history;
CREATE POLICY zone_claim_history_read_own
  ON zone_claim_history FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- No INSERT/UPDATE/DELETE policy: all writes happen via the trigger below,
-- fired by claim_territory and other zone-owner-writing edge functions,
-- every one of which uses the service-role key (bypasses RLS entirely;
-- triggers still fire regardless of RLS).

CREATE OR REPLACE FUNCTION fn_record_zone_claim()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.owner_id IS NOT NULL THEN
    INSERT INTO zone_claim_history (zone_id, user_id, first_claimed_at)
    VALUES (NEW.id, NEW.owner_id, now())
    ON CONFLICT (zone_id, user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_zone_claim ON zones;
CREATE TRIGGER trg_record_zone_claim
  AFTER INSERT OR UPDATE OF owner_id ON zones
  FOR EACH ROW
  EXECUTE FUNCTION fn_record_zone_claim();

-- Backfill: the trigger above only fires on future owner_id writes, so seed
-- a history row for every zone's CURRENT owner now, or a zone already held
-- before this migration deployed would show no history until its next
-- conquest/re-claim.
INSERT INTO zone_claim_history (zone_id, user_id, first_claimed_at)
SELECT id, owner_id, COALESCE(created_at, now())
FROM zones
WHERE owner_id IS NOT NULL
ON CONFLICT (zone_id, user_id) DO NOTHING;

COMMENT ON TABLE zone_claim_history IS
  'Append-only "user X has ever held zone Y" record, written by '
  'trg_record_zone_claim on every zones.owner_id assignment. Used to keep '
  'fog-of-war permanently revealed for a zone once a player has ever '
  'claimed it, independent of current ownership.';
