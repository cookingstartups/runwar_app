import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/connectivity_provider.dart';
import '../providers/run_recorder_provider.dart';
import '../services/run_recorder_service.dart';
import '../theme.dart';

class OfflineOverlay extends ConsumerWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityProvider);
    final isRecording = ref.watch(runRecorderProvider) == RecorderState.recording;

    final isOnline = connectivityAsync.when(
      data: (online) => online,
      loading: () => false,
      error: (e, __) {
        debugPrint('[Connectivity] provider error: $e');
        return false; // fail closed - unknown state treated as offline
      },
    );

    if (isOnline) return child;
    // GPS tracking needs no network — never hide an active run behind a
    // full-screen block. Degrade to a top banner instead.
    if (isRecording) {
      return Stack(
        children: [
          child,
          const _OfflineBanner(),
        ],
      );
    }
    return _OfflineScreen();
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          color: kDanger.withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.signal_wifi_off_rounded, size: 16, color: kFg),
              SizedBox(width: 8),
              Text(
                'NO CONNECTION - GPS STILL TRACKING',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: kFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
