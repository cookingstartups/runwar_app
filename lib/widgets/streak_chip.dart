import 'package:flutter/material.dart';

import '../theme.dart';
import 'daily_missions_sheet.dart';

/// Small pill chip displaying the player's current daily streak.
/// Matches the height and padding of [CreditsChip].
/// Tapping opens [DailyMissionsSheet] as a modal bottom sheet.
class StreakChip extends StatelessWidget {
  const StreakChip({
    required this.streak,
    required this.userId,
    super.key,
  });

  final int streak;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openMissionsSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department,
              size: 14,
              color: kAccent,
            ),
            const SizedBox(width: 5),
            Text(
              streak.toString(),
              style: const TextStyle(
                color: kFg,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMissionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DailyMissionsSheet(userId: userId),
    );
  }
}
