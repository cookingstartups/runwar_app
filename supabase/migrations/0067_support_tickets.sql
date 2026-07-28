-- =============================================================================
-- 0067_support_tickets.sql
-- Support/bug/account-deletion ticket intake for the settings-screen initiative
-- (spec R4; infra/meta/specs/runwar/settings-screen/design.md section 3.3/4).
--
-- Regular users may create and read their own tickets, but never edit or
-- delete them after submission - status transitions (open -> in_progress ->
-- resolved/rejected) happen only through the service role. This table is
-- also written atomically alongside account_deletion_requests by
-- submit_support_ticket (0068), for tickets of kind account_deletion.
-- =============================================================================

CREATE TABLE IF NOT EXISTS support_tickets (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind         TEXT        NOT NULL CHECK (kind IN ('support', 'bug', 'account_deletion')),
  subject      TEXT,
  body         TEXT        NOT NULL,
  status       TEXT        NOT NULL DEFAULT 'open'
               CHECK (status IN ('open', 'in_progress', 'resolved', 'rejected')),
  app_version  TEXT,
  platform     TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY support_tickets_insert_own
  ON support_tickets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY support_tickets_select_own
  ON support_tickets FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Deliberately no UPDATE/DELETE policy for regular users: a ticket, once
-- submitted, can only have its status moved forward by the service role.
-- Users can never edit or delete their own tickets after creation.
