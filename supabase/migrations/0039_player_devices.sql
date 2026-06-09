-- Migration 0039: player_devices child table (1:N)
-- Replaces the scalar fcm_token column on players with a multi-device table.
-- Composite PK (player_id, device_token) prevents duplicate device registrations.

CREATE TABLE IF NOT EXISTS player_devices (
  player_id    uuid        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  device_token text        NOT NULL,
  platform     text        NOT NULL DEFAULT 'android'
    CHECK (platform IN ('android', 'ios', 'web')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, device_token)
);

-- Backfill: migrate existing fcm_token values, platform defaults to 'android'.
-- Players with NULL fcm_token are intentionally excluded (no device row created).
DO $$
DECLARE
  expected_count INT;
  actual_count   INT;
BEGIN
  INSERT INTO player_devices (player_id, device_token, platform)
  SELECT id, fcm_token, 'android'
  FROM players
  WHERE fcm_token IS NOT NULL
  ON CONFLICT DO NOTHING;

  SELECT COUNT(*) INTO expected_count
  FROM players
  WHERE fcm_token IS NOT NULL;

  SELECT COUNT(*) INTO actual_count FROM player_devices;

  IF actual_count <> expected_count THEN
    RAISE EXCEPTION
      'player_devices backfill mismatch: expected %, got %',
      expected_count, actual_count;
  END IF;
END $$;

-- RLS: enable and restrict reads to own rows only; no write policies (service_role bypasses RLS)
ALTER TABLE player_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS player_devices_select_own ON player_devices;
CREATE POLICY player_devices_select_own ON player_devices
  FOR SELECT
  USING (player_id = auth.uid());
