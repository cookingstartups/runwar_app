-- Add missing INSERT and UPDATE RLS policies for player_streaks.
-- Only SELECT existed; app failed with "violates row-level security policy"
-- on first login when attempting to upsert the streak row.

CREATE POLICY player_streaks_insert_own
  ON player_streaks FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY player_streaks_update_own
  ON player_streaks FOR UPDATE
  TO authenticated
  USING  (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());
