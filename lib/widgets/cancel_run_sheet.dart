import 'package:flutter/material.dart';

import '../theme.dart';
import 'valencia_button.dart';

/// Blocking bottom-sheet confirmation shown before a mid-run cancel
/// executes (Option C, locked). Matches the existing DailyMissionsSheet
/// bottom-sheet idiom. "Keep Running" dismisses the sheet with no state
/// change; "Cancel Run" is the only action that invokes the cancel
/// callback.
class CancelRunSheet extends StatelessWidget {
  const CancelRunSheet({
    required this.currentDistanceM,
    required this.onCancelConfirmed,
    super.key,
  });

  final double currentDistanceM;
  final VoidCallback onCancelConfirmed;

  @override
  Widget build(BuildContext context) {
    final distanceKm = (currentDistanceM / 1000).toStringAsFixed(1);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kFgFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Cancel This Run?', style: displayStyle(size: 22)),
            const SizedBox(height: 8),
            Text(
              '$distanceKm km won\'t be saved. This can\'t be undone.',
              style: bodyStyle(size: 14),
            ),
            const SizedBox(height: 20),
            ValenciaButton(
              label: 'Keep Running',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 10),
            ValenciaButton(
              label: 'Cancel Run',
              variant: ValenciaButtonVariant.ghost,
              onPressed: () {
                onCancelConfirmed();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
