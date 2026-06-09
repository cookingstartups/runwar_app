-- Migration 0043: signup trigger for player child rows
-- Creates an AFTER INSERT trigger on players that atomically inserts default rows
-- into all four 1:1 child tables: player_economy, player_progress, player_streaks, player_trial.
-- player_devices is NOT included -- device registration is an explicit separate action.
--
-- Atomicity: the trigger runs in the same transaction as the parent INSERT INTO players.
-- If any child INSERT raises an exception, the entire parent INSERT is rolled back.
-- ON CONFLICT DO NOTHING makes the trigger safe against the backfill race window
-- (between 0035-0039 backfill and this trigger being installed).
--
-- Depends on: 0035, 0036, 0037, 0038 (all four 1:1 child tables must exist).

CREATE OR REPLACE FUNCTION fn_players_create_child_rows()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO player_economy  (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_progress (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_streaks  (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO player_trial    (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  -- NOT player_devices: device registration is explicit per spec.
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_players_create_child_rows ON players;
CREATE TRIGGER trg_players_create_child_rows
  AFTER INSERT ON players
  FOR EACH ROW
  EXECUTE FUNCTION fn_players_create_child_rows();
