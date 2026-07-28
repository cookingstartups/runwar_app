/// Distinguishes a plain support/bug ticket from an account-deletion request
/// routed through the same shared SupportTicketScreen (design.md section 3.3).
enum SupportTicketKind { support, bug, accountDeletion }

/// Mirrors support_tickets.status in migration 0067 - server-side transitions
/// only, never written by the client directly.
enum SupportTicketStatus { open, inProgress, resolved, rejected }

/// Maps a [SupportTicketKind] to the literal `kind` column value expected by
/// the submit_support_ticket RPC (migration 0068).
extension SupportTicketKindRpc on SupportTicketKind {
  String get rpcValue {
    switch (this) {
      case SupportTicketKind.support:
        return 'support';
      case SupportTicketKind.bug:
        return 'bug';
      case SupportTicketKind.accountDeletion:
        return 'account_deletion';
    }
  }
}
