-- 0062_db_only_table_schema_capture.sql
-- Idempotent capture of five tables (referrals, challenges, invitation_codes,
-- drops, passive_income_runs) that are live in production but whose CREATE
-- TABLE history only ever existed in runwar_database's migrations
-- (0002/0018/0019/0022-0024) and was never replayed here. Written the same
-- way 0029_runwar_full_schema.sql captured drift: from the live
-- information_schema.columns / pg_indexes / pg_policies state, not from the
-- old migration files, since those files are known to have been superseded
-- by later remediation migrations in that repo.
--
-- All five tables and their edge functions (apply_referral_kickback,
-- complete_challenge, complete_daily_mission, complete_first_attack,
-- expire_drops, finalize_run, generate_invite_code, passive_income_tick,
-- redeem_invite_code, spawn_conquer_bot, spawn_drops) are confirmed ACTIVE
-- in the live Supabase project as of this migration's authoring date. This
-- file only documents the existing live shape; it does not change
-- production schema, and running it against the live database is a no-op
-- (every statement is IF NOT EXISTS / idempotent).

-- ---------------------------------------------------------------------------
-- referrals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  invitee_id  uuid        NOT NULL PRIMARY KEY REFERENCES auth.users(id),
  inviter_id  uuid        NOT NULL REFERENCES auth.users(id),
  via_code    text        NOT NULL REFERENCES public.invitation_codes(code),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referrals_inviter
  ON public.referrals (inviter_id);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS referrals_participant_read ON public.referrals;
CREATE POLICY referrals_participant_read ON public.referrals
  FOR SELECT
  USING (inviter_id = auth.uid() OR invitee_id = auth.uid());

-- ---------------------------------------------------------------------------
-- invitation_codes (created before referrals: referrals.via_code FKs into it)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invitation_codes (
  code            text        NOT NULL PRIMARY KEY,
  created_at      timestamptz NOT NULL DEFAULT now(),
  max_redemptions integer     NOT NULL DEFAULT 1,
  created_by      uuid        NULL REFERENCES auth.users(id),
  redeemed_count  integer     NOT NULL DEFAULT 0,
  expires_at      timestamptz NULL,
  reserved_label  text        NULL
);

CREATE INDEX IF NOT EXISTS idx_invitation_codes_created_by
  ON public.invitation_codes (created_by);

ALTER TABLE public.invitation_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS codes_select_all ON public.invitation_codes;
CREATE POLICY codes_select_all ON public.invitation_codes
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS invitation_codes_owner_read ON public.invitation_codes;
CREATE POLICY invitation_codes_owner_read ON public.invitation_codes
  FOR SELECT
  USING (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- challenges
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.challenges (
  id              uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id         uuid        NOT NULL REFERENCES auth.users(id),
  trigger_run_id  uuid        NULL,
  challenge_type  text        NOT NULL,
  status          text        NOT NULL DEFAULT 'pending',
  pending_payload jsonb       NULL,
  motion_target   jsonb       NULL,
  issued_at       timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz NULL,
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '24:00:00')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_challenges_one_open_per_player
  ON public.challenges (user_id)
  WHERE status = 'pending';

ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS challenges_self_read ON public.challenges;
CREATE POLICY challenges_self_read ON public.challenges
  FOR SELECT
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- drops
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.drops (
  id             uuid             NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  city           text             NOT NULL,
  lat            double precision NOT NULL,
  lng            double precision NOT NULL,
  drop_type      text             NOT NULL,
  value          integer          NOT NULL DEFAULT 50,
  created_at     timestamptz      NOT NULL DEFAULT now(),
  claimed_by     uuid             NULL REFERENCES auth.users(id),
  claimed_at     timestamptz      NULL,
  expires_at     timestamptz      NOT NULL,
  expired        boolean          NOT NULL DEFAULT false,
  status         text             NOT NULL DEFAULT 'active',
  spawn_batch_id uuid             NULL,
  metadata       jsonb            NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS drops_active_city_idx
  ON public.drops (city, expires_at)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS drops_geo_idx
  ON public.drops (city, lat, lng)
  WHERE status = 'active';

ALTER TABLE public.drops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS drops_read_active ON public.drops;
CREATE POLICY drops_read_active ON public.drops
  FOR SELECT
  USING (status = 'active');

-- ---------------------------------------------------------------------------
-- passive_income_runs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.passive_income_runs (
  id               uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  invoked_at       timestamptz NOT NULL DEFAULT now(),
  invocation_mode  text        NOT NULL,
  zones_processed  integer     NOT NULL,
  players_paid     integer     NOT NULL,
  total_credits    bigint      NOT NULL,
  duration_ms      integer     NOT NULL,
  errors           jsonb       NOT NULL DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS passive_income_runs_invoked_idx
  ON public.passive_income_runs (invoked_at DESC);

ALTER TABLE public.passive_income_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS passive_income_runs_admin_only ON public.passive_income_runs;
CREATE POLICY passive_income_runs_admin_only ON public.passive_income_runs
  FOR SELECT
  USING (false);
