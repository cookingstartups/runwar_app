// lib/widgets/kickback_history_tile.dart
// Phase 3 trust layer — one row in the referral kickback history list.
//
// Receives a raw credit_transactions row (Map<String, dynamic>) from
// [kickbackHistoryProvider] and renders invitee ID, date, and amount.

import 'package:flutter/material.dart';

import '../theme.dart';

/// ListTile for a single referral kickback credit_transactions row.
///
/// Expected map keys (from Supabase):
///   - `metadata.invitee_id` (String) or falls back to `user_id`
///   - `amount` (num)
///   - `created_at` (ISO-8601 String)
class KickbackHistoryTile extends StatelessWidget {
  const KickbackHistoryTile({super.key, required this.entry});

  /// Raw row from `credit_transactions` where `reason = 'referral_kickback'`.
  final Map<String, dynamic> entry;

  String get _displayName {
    final meta = entry['metadata'];
    if (meta is Map) {
      final id = meta['invitee_id'];
      if (id != null && id.toString().isNotEmpty) return id.toString();
    }
    // Fallback to the transaction's own user_id
    return entry['user_id']?.toString() ?? '—';
  }

  String get _dateLabel {
    final raw = entry['created_at'];
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString();
    }
  }

  int get _amount => (entry['amount'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.people_outline, color: kFgMuted, size: 20),
      title: Text(
        _displayName,
        style: const TextStyle(color: kFg, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _dateLabel,
        style: const TextStyle(color: kFgMuted, fontSize: 12),
      ),
      trailing: Text(
        '+$_amount cr',
        style: const TextStyle(
          color: Color(0xFF4CAF50),
          fontWeight: FontWeight.w700,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
