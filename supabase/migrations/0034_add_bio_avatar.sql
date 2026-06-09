-- Add bio and avatar_url columns to players (idempotent)
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;
