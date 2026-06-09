import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/connectivity_provider.dart';
import '../theme.dart';

class OfflineOverlay extends ConsumerWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityProvider);

    final isOnline = connectivityAsync.when(
      data: (online) => online,
      loading: () => false,
      error: (_, __) => true,
    );

    if (!isOnline) return _OfflineScreen();
    return child;
  }
}

class _OfflineScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.signal_wifi_off_rounded,
                  size: 52,
                  color: kFgMuted,
                ),
                const SizedBox(height: 24),
                Text(
                  'NO CONNECTION',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 3,
                    color: kAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'RunWar needs a connection\nto track territory.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    color: kFgMuted,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: kFgFaint,
                    strokeWidth: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for connection…',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: kFgFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
