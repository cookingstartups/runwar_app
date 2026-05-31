// lib/services/database/models/dispute.dart
//
// Immutable Dispute model parsed from the disputes table.
// Design.md §1 — Dispute.fromRow contract.

/// Immutable snapshot of a dispute record.
class Dispute {
  const Dispute({
    required this.id,
    required this.zoneId,
    required this.attackerId,
    required this.defenderId,
    required this.expiresAt,
    required this.createdAt,
    this.resolvedAt,
    this.winnerId,
  });

  final String id;
  final String zoneId;
  final String attackerId;
  final String defenderId;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? winnerId;

  /// Parse a row from the disputes table.
  ///
  /// Required fields: id, zone_id, attacker_id, defender_id, expires_at, created_at.
  /// Optional: resolved_at, winner_id (null for open disputes).
  factory Dispute.fromRow(Map<String, dynamic> row) {
    return Dispute(
      id: row['id'] as String,
      zoneId: row['zone_id'] as String,
      attackerId: row['attacker_id'] as String,
      defenderId: row['defender_id'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String).toUtc(),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      resolvedAt: row['resolved_at'] != null
          ? DateTime.parse(row['resolved_at'] as String).toUtc()
          : null,
      winnerId: row['winner_id'] as String?,
    );
  }

  /// Whether this dispute is still open (not resolved, not expired) at [now].
  bool isActive(DateTime now) =>
      resolvedAt == null && expiresAt.isAfter(now);

  /// Time remaining until expiry, clamped to non-negative.
  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  String toString() =>
      'Dispute(id: $id, zone: $zoneId, expires: $expiresAt, resolved: $resolvedAt)';
}
