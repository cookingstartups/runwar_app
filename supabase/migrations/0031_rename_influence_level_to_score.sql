DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'players' AND column_name = 'influence_level'
  ) THEN
    ALTER TABLE players RENAME COLUMN influence_level TO score;
  END IF;
END $$;
