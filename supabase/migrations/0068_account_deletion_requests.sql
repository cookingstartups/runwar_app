-- =============================================================================
-- 0068_account_deletion_requests.sql
-- The 30-day account deactivation/deletion audit trail, plus the two
-- load-bearing RPCs that read/write it (spec R5-R7;
-- infra/meta/specs/runwar/settings-screen/design.md section 3.4/3.6/4).
--
-- user_id is ON DELETE SET NULL (unlike support_tickets' CASCADE) - this row
-- is the surviving audit trail after the eventual auth.users deletion, so it
-- must not be removed along with the user.
--
-- Depends on: 0067 (support_tickets), since submit_support_ticket inserts
-- into both tables atomically.
-- =============================================================================

CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  requested_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  scheduled_deletion_at TIMESTAMPTZ NOT NULL,
  status                TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'reactivated', 'executed'))
);

ALTER TABLE account_deletion_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY account_deletion_requests_select_own
  ON account_deletion_requests FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Deliberately no client INSERT/UPDATE/DELETE policy on this table - every
-- write happens only through submit_support_ticket, reactivate_account
-- (both SECURITY DEFINER, below), or the service-role executor (0069).

-- ── submit_support_ticket ──────────────────────────────────────────────────
-- Atomic write: inserts the ticket row, and, for kind = account_deletion,
-- the matching deletion-request row in the same transaction - one client RPC
-- call instead of two unprotected sequential inserts.
CREATE OR REPLACE FUNCTION submit_support_ticket(
  p_kind TEXT, p_subject TEXT, p_body TEXT, p_app_version TEXT, p_platform TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ticket_id UUID;
BEGIN
  INSERT INTO support_tickets (user_id, kind, subject, body, app_version, platform)
  VALUES (auth.uid(), p_kind, p_subject, p_body, p_app_version, p_platform)
  RETURNING id INTO v_ticket_id;

  IF p_kind = 'account_deletion' THEN
    INSERT INTO account_deletion_requests (user_id, requested_at, scheduled_deletion_at, status)
    VALUES (auth.uid(), now(), now() + interval '30 days', 'pending');
  END IF;

  RETURN v_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION submit_support_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_support_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ── reactivate_account ─────────────────────────────────────────────────────
-- Flips the calling user's own still-pending deletion request back to
-- reactivated. Only ever touches the caller's own row.
CREATE OR REPLACE FUNCTION reactivate_account() RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE account_deletion_requests
     SET status = 'reactivated'
   WHERE user_id = auth.uid() AND status = 'pending';
$$;

REVOKE ALL ON FUNCTION reactivate_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reactivate_account() TO authenticated;
