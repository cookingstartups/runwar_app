-- HARD GATE: run only after all edge fns + Dart verified GREEN
--
-- Migration 0044: drop moved columns from players
-- Removes the 20 columns that have been moved to child tables.
-- Uses DROP COLUMN IF EXISTS for idempotent re-runs.
--
-- Pre-conditions that MUST be confirmed by a human before applying this migration:
--   1. Migrations 0035-0043 applied and verified on live database.
--   2. record_daily_login edge fn rewritten to read/write player_streaks.
--   3. apply_referral_kickback edge fn rewritten to read/write player_economy.
--   4. complete_first_attack edge fn rewritten to read/write player_progress.
--   5. claim_drop edge fn rewritten (uses apply_credit_delta -> player_economy).
--   6. spend_credits_on_power edge fn rewritten (uses apply_credit_delta -> player_economy).
--   7. database_service.dart updated with nested JOIN selects.
--   8. profile_provider.dart updated (reputationProvider reads player_economy.reputation).
--   9. daily_mission.dart updated (DailyStreak.fromMap reads 'streak' key).
--   10. APK built from updated Dart and installed on test device.
--   11. All acceptance criteria verified by QA.
--
-- After applying this migration, players retains exactly 12 columns:
--   id, username, color, phone, bio, avatar_url, avatar_metadata,
--   referral_code, is_active, is_tester, invited_at, created_at

ALTER TABLE players
  DROP COLUMN IF EXISTS credits,
  DROP COLUMN IF EXISTS total_kickback_earned,
  DROP COLUMN IF EXISTS subscription_tier,
  DROP COLUMN IF EXISTS subscription_expires,
  DROP COLUMN IF EXISTS reputation,
  DROP COLUMN IF EXISTS influence_total,
  DROP COLUMN IF EXISTS score,
  DROP COLUMN IF EXISTS first_mission_completed_at,
  DROP COLUMN IF EXISTS first_attack_completed_at,
  DROP COLUMN IF EXISTS streak,
  DROP COLUMN IF EXISTS current_streak,
  DROP COLUMN IF EXISTS longest_streak,
  DROP COLUMN IF EXISTS last_login_at,
  DROP COLUMN IF EXISTS streak_started_at,
  DROP COLUMN IF EXISTS milestones_claimed,
  DROP COLUMN IF EXISTS freeze_tokens,
  DROP COLUMN IF EXISTS freeze_refreshed_at,
  DROP COLUMN IF EXISTS trial_started_at,
  DROP COLUMN IF EXISTS trial_days_remaining,
  DROP COLUMN IF EXISTS trial_last_tick_date,
  DROP COLUMN IF EXISTS fcm_token;
