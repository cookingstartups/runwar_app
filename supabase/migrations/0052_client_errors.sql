-- client_errors: persistent log of Flutter client-side errors
-- Ingested exclusively by the log-client-error edge function via service_role.
-- No RLS policies are defined because service_role bypasses RLS entirely;
-- no direct client access is permitted.

CREATE TABLE IF NOT EXISTS public.client_errors (
  id               uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  ts               timestamptz NOT NULL DEFAULT now(),
  user_id          uuid        NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  provider         text        NOT NULL,
  error_class      text        NOT NULL,
  error_message    text        NOT NULL,
  stack_first_line text        NOT NULL,
  retry_count      int         NOT NULL DEFAULT 0,
  app_version      text        NOT NULL,
  device           text        NOT NULL,
  platform         text        NOT NULL CHECK (platform IN ('android', 'ios'))
);

CREATE INDEX idx_client_errors_ts
  ON public.client_errors (ts DESC);

CREATE INDEX idx_client_errors_provider_ts
  ON public.client_errors (provider, ts DESC);

CREATE INDEX idx_client_errors_user_id_ts
  ON public.client_errors (user_id, ts DESC)
  WHERE user_id IS NOT NULL;

ALTER TABLE public.client_errors ENABLE ROW LEVEL SECURITY;
