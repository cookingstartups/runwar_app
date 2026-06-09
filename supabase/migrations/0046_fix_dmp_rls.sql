-- =============================================================================
-- 0046_fix_dmp_rls.sql
-- Defect C - Daily Missions: replace user_id-anchored RLS with player_id-anchored.
-- The 0030 dmp_own_all policy was written against the abandoned 0029 schema
-- (user_id column). After this fix the Dart client upserts using player_id
-- (matching the live 0027 schema), so the policy must be re-anchored or all
-- authenticated upserts will fail with 403.
-- =============================================================================

-- Drop the stale user_id-anchored policy added by 0030.
DROP POLICY IF EXISTS dmp_own_all ON daily_mission_progress;

-- Replace with player_id-anchored policy.
CREATE POLICY dmp_own_all ON daily_mission_progress
  FOR ALL
  USING  (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);
