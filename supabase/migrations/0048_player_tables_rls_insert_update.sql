-- Add missing INSERT + UPDATE RLS policies for all player-owned tables.
-- All these tables had SELECT-only, causing "violates row-level security"
-- errors when the app tried to upsert rows on login/session init.

CREATE POLICY player_devices_insert_own  ON player_devices  FOR INSERT TO authenticated WITH CHECK (player_id = auth.uid());
CREATE POLICY player_devices_update_own  ON player_devices  FOR UPDATE TO authenticated USING (player_id = auth.uid()) WITH CHECK (player_id = auth.uid());

CREATE POLICY player_economy_insert_own  ON player_economy  FOR INSERT TO authenticated WITH CHECK (player_id = auth.uid());
CREATE POLICY player_economy_update_own  ON player_economy  FOR UPDATE TO authenticated USING (player_id = auth.uid()) WITH CHECK (player_id = auth.uid());

CREATE POLICY player_progress_insert_own ON player_progress FOR INSERT TO authenticated WITH CHECK (player_id = auth.uid());
CREATE POLICY player_progress_update_own ON player_progress FOR UPDATE TO authenticated USING (player_id = auth.uid()) WITH CHECK (player_id = auth.uid());

CREATE POLICY player_trial_insert_own    ON player_trial    FOR INSERT TO authenticated WITH CHECK (player_id = auth.uid());
CREATE POLICY player_trial_update_own    ON player_trial    FOR UPDATE TO authenticated USING (player_id = auth.uid()) WITH CHECK (player_id = auth.uid());
