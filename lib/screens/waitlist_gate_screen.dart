import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';

/// Shown when the signed-in user has no invite (profiles.invited_at IS NULL).
/// AC-14 / AC-15.
class WaitlistGateScreen extends ConsumerWidget {
  const WaitlistGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "YOU'RE ON THE WAITLIST",
                textAlign: TextAlign.center,
                style: displayStyle(size: 36, color: kAccent),
              ),
              const SizedBox(height: 16),
              Text(
                "We'll notify you when your invite is ready.",
                textAlign: TextAlign.center,
                style: bodyStyle(size: 16),
              ),
              const SizedBox(height: 48),
              OutlinedButton(
                onPressed: () =>
                    ref.read(authProvider.notifier).signOut(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBorder),
                  minimumSize: const Size(220, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'LOG OUT',
                  style: bodyStyle(size: 12, color: kFg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
