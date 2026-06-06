-- Migration 0033: account-uniqueness sprint.
-- - Drop legacy fallback column players.display_name if present (no-op on live).
-- - Drop players.city (multi-city users live in city_waitlists).
-- - Drop players.is_bot (bots table is the authoritative NPC home; 0 prod rows have is_bot=1).
-- - Drop & recreate dependent objects: view players_and_bots, policy zones_city_read.
-- - Enable citext + convert players.username to citext.
-- - Partial UNIQUE on phone, partial UNIQUE on username, CHECK forbidding blank username.
-- Spec: specs/runwar/poc/account-uniqueness/requirements.md
-- Design: specs/runwar/poc/account-uniqueness/design.md
-- Prod backfill safety: current prod = 1 player row (algife) with non-blank username,
-- is_bot=0, blank-string default city tolerated; migration runs cleanly.

BEGIN;

-- 1. Safety guards. Refuse to migrate if duplicate live data would violate the
--    new constraints or if any players row still claims is_bot=1 (such rows
--    would need to migrate to the bots table first, see db-review §1).
--    Blank-string usernames are NORMALISED (not aborted on) because the live
--    column has DEFAULT '' — see step 4 below.
DO $$
DECLARE
  dup_phones    INT;
  dup_usernames INT;
  bot_players   INT;
BEGIN
  SELECT count(*) INTO dup_phones FROM (
    SELECT phone FROM players
     WHERE phone IS NOT NULL
     GROUP BY phone HAVING count(*) > 1
  ) d;
  SELECT count(*) INTO dup_usernames FROM (
    SELECT lower(username) AS u FROM players
     WHERE username IS NOT NULL AND username <> ''
     GROUP BY lower(username) HAVING count(*) > 1
  ) d;
  -- is_bot is BOOLEAN on the live schema (migration 0029 declared INTEGER but
  -- Supabase applied it as boolean); check the boolean truthy value.
  SELECT count(*) INTO bot_players FROM players WHERE is_bot = true;

  IF dup_phones > 0 THEN
    RAISE EXCEPTION 'Migration 0033 aborted: % duplicate phone groups exist. Resolve before re-running.', dup_phones;
  END IF;
  IF dup_usernames > 0 THEN
    RAISE EXCEPTION 'Migration 0033 aborted: % duplicate case-insensitive username groups exist. Resolve before re-running.', dup_usernames;
  END IF;
  IF bot_players > 0 THEN
    RAISE EXCEPTION 'Migration 0033 aborted: % players rows still have is_bot<>0. Migrate them into the bots table before re-running.', bot_players;
  END IF;
END $$;

-- 2. Drop dependent objects that reference the columns we are about to remove.
--    These will be re-created (view) or rewritten (policy) below.
DROP VIEW   IF EXISTS players_and_bots;
DROP POLICY IF EXISTS zones_city_read ON zones;

-- 3. Drop the deprecated columns.
--    - display_name: never existed on the live timeline; IF EXISTS makes it a no-op.
--    - city: stale vs city_waitlists for multi-city users (db-review §3).
--    - is_bot: bots table is the authoritative NPC home (db-review §1).
ALTER TABLE players
  DROP COLUMN IF EXISTS display_name,
  DROP COLUMN IF EXISTS city,
  DROP COLUMN IF EXISTS is_bot;

-- 4. Normalise blank-string usernames to NULL BEFORE adding the CHECK and the
--    UNIQUE index. The live column carries DEFAULT '' so newly-signed-up
--    accounts that haven't completed onboarding may legitimately hold ''.
--    The new contract: NULL = "not yet onboarded"; non-NULL = "onboarded, must
--    be non-blank and unique". Existing '' rows convert losslessly to NULL —
--    the route guard's "is onboarded" predicate already treats blank and NULL
--    identically (see SignUpFlow: usernameValid requires _usernameCtrl.text
--    .isNotEmpty, lib/screens/onboarding/sign_up_flow.dart:148).
UPDATE players SET username = NULL WHERE username = '';

-- Drop the NOT NULL DEFAULT '' contract from migration 0029 — username is now
-- NULLable to distinguish "not onboarded" from "blank (invalid) onboarded".
ALTER TABLE players
  ALTER COLUMN username DROP DEFAULT,
  ALTER COLUMN username DROP NOT NULL;

-- 5. Enable citext for case-insensitive username comparisons.
CREATE EXTENSION IF NOT EXISTS citext;

-- 6. Convert username to citext. The USING cast is safe for any TEXT value.
ALTER TABLE players
  ALTER COLUMN username TYPE CITEXT USING username::citext;

-- 7. Forbid blank-string usernames. NULL remains allowed for not-yet-onboarded users.
ALTER TABLE players
  ADD CONSTRAINT players_username_not_blank
  CHECK (username IS NULL OR length(trim(username)) > 0);

-- 8. Partial unique on phone (NULL-allowed; see requirements AC-1).
CREATE UNIQUE INDEX IF NOT EXISTS players_phone_unique
  ON players (phone)
  WHERE phone IS NOT NULL;

-- 9. Partial unique on username (NULL- and blank-excluded; blank already blocked
--    by the CHECK above, but the partial predicate documents intent).
CREATE UNIQUE INDEX IF NOT EXISTS players_username_unique
  ON players (username)
  WHERE username IS NOT NULL AND username <> '';

-- 10. Recreate the dependent objects with the new schema.
--     - players_and_bots no longer exposes a players.city column. Map and
--       leaderboard callers needing a city per real player now read it from
--       city_waitlists (see §4.4 onboarding wiring).
CREATE OR REPLACE VIEW players_and_bots AS
  SELECT id, username::text AS username, color,
         0   AS score,
         false AS is_bot
    FROM players
  UNION ALL
  SELECT id, username, color,
         score,
         true AS is_bot
    FROM bots
   WHERE is_active = true;

--     - zones_city_read previously gated zone reads by `p.city`. Replace with
--       a city_waitlists subquery so any city a user has joined is readable.
CREATE POLICY zones_city_read ON zones
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND city IN (
      SELECT lower(cw.city_slug) FROM city_waitlists cw
       WHERE cw.user_id = auth.uid()
    )
  );

COMMIT;
